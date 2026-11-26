import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppUser {
  const AppUser(this.id, this.email, {this.nickname});
  final int id;
  final String email;
  final String? nickname;
}

class GameStats {
  const GameStats(this.played, this.best);
  final int played;
  final int best;
}

class GameResult {
  const GameResult(this.score, this.total, this.playedAt);
  final int score;
  final int total;
  final DateTime playedAt;
}

// Локальна база даних: користувачі, результати ігор та активна сесія.
class StorageService {
  Database? _database;
  final _pbkdf2 = Pbkdf2.hmacSha256(iterations: 100000, bits: 256);

  Future<Database> get database async {
    if (_database != null) return _database!;
    final location = p.join(await getDatabasesPath(), 'deschuv.sqlite');
    return _database = await openDatabase(
      location,
      version: 3,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            nickname TEXT,
            salt TEXT NOT NULL,
            password_hash TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE game_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            score INTEGER NOT NULL,
            total INTEGER NOT NULL,
            played_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE app_session (
            slot INTEGER PRIMARY KEY CHECK (slot = 1),
            user_id INTEGER NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');

      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Оновлення старої БД v1 без втрати акаунтів та історії ігор.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE users ADD COLUMN nickname TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE app_session (
              slot INTEGER PRIMARY KEY CHECK (slot = 1),
              user_id INTEGER NOT NULL,
              FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
          ''');
        }
      },
    );
  }

  // Зберігаємо лише ID активного користувача. Пароль не зберігається.
  // Це локальна сесія цього телефона, а не синхронізація між пристроями.
  Future<void> saveSession(AppUser user) async {
    final db = await database;
    await db.insert('app_session', {'slot': 1, 'user_id': user.id},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AppUser?> savedUser() async {
    final db = await database;
    final sessions = await db.query('app_session', where: 'slot = 1', limit: 1);
    if (sessions.isEmpty) return null;
    final rows = await db.query('users',
        where: 'id = ?', whereArgs: [sessions.first['user_id']], limit: 1);
    if (rows.isEmpty) {
      await db.delete('app_session', where: 'slot = 1');
      return null;
    }
    final row = rows.first;
    return AppUser(row['id'] as int, row['email'] as String,
        nickname: row['nickname'] as String?);
  }

  Future<void> clearSession() async {
    final db = await database;
    await db.delete('app_session', where: 'slot = 1');
  }

  Future<String> _hash(String password, List<int> salt) async {
    final key = await _pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
    return base64Encode(await key.extractBytes());
  }

  Future<AppUser> register(String email, String password) async {
    email = email.trim().toLowerCase();
    if (!email.contains('@') || !email.contains('.') || password.length < 6) {
      throw const FormatException('Вкажи коректну електронну пошту та пароль із щонайменше 6 символів.');
    }
    final db = await database;
    if ((await db.query('users', where: 'email = ?', whereArgs: [email])).isNotEmpty) {
      throw const FormatException('Цю електронну адресу вже зареєстровано.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await _hash(password, salt);
    final id = await db.insert('users', {
      'email': email,
      'salt': base64Encode(salt),
      'password_hash': hash,
    });
    return AppUser(id, email);
  }

  Future<AppUser> login(String email, String password) async {
    email = email.trim().toLowerCase();
    final db = await database;
    final rows = await db.query('users', where: 'email = ?', whereArgs: [email], limit: 1);
    if (rows.isEmpty) throw const FormatException('Неправильна електронна пошта або пароль.');
    final row = rows.first;
    final salt = base64Decode(row['salt'] as String);
    if (await _hash(password, salt) != row['password_hash']) {
      throw const FormatException('Неправильна електронна пошта або пароль.');
    }
    return AppUser(row['id'] as int, email, nickname: row['nickname'] as String?);
  }

  Future<AppUser> setNickname(AppUser user, String nickname) async {
    nickname = nickname.trim();
    if (nickname.length < 2 || nickname.length > 24 || nickname.contains('\n')) {
      throw const FormatException('Нікнейм має містити від 2 до 24 символів.');
    }
    final db = await database;
    await db.update('users', {'nickname': nickname},
        where: 'id = ?', whereArgs: [user.id]);
    return AppUser(user.id, user.email, nickname: nickname);
  }

  Future<void> deleteAccount(AppUser user, String password) async {
    await login(user.email, password); // Видалення підтверджує власник акаунта.
    final db = await database;
    await db.delete('users', where: 'id = ?', whereArgs: [user.id]);
  }

  Future<void> saveResult(int userId, int score, int total) async {
    final db = await database;
    await db.insert('game_results', {
      'user_id': userId,
      'score': score,
      'total': total,
      'played_at': DateTime.now().toIso8601String(),
    });
  }

  // Загальна статистика без обмеження останніми п'ятьма іграми.
  Future<GameStats> stats(int userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS played, MAX(score) AS best FROM game_results WHERE user_id = ?',
      [userId],
    );
    final row = rows.first;
    return GameStats((row['played'] as int?) ?? 0, (row['best'] as int?) ?? 0);
  }

  Future<List<GameResult>> results(int userId) async {
    final db = await database;
    final rows = await db.query('game_results',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'id DESC', limit: 5);
    return rows.map((r) => GameResult(
      r['score'] as int,
      r['total'] as int,
      DateTime.parse(r['played_at'] as String),
    )).toList();
  }
}
