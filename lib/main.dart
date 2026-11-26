import 'dart:async';

import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/nickname_screen.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DesChuvApp());
}

class AppColors {
  static const background = Color(0xFF151C2B);
  static const card = Color(0xFF222C3E);
  static const cyan = Color(0xFF3CD7DE);
  static const coral = Color(0xFFF77D93);
  static const muted = Color(0xFF9BA9BF);
  static const line = Color(0xFF37465C);
}

class DesChuvApp extends StatelessWidget {
  const DesChuvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ДесьЧУВ?',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.cyan,
            brightness: Brightness.dark,
            surface: AppColors.card,
          ),
          scaffoldBackgroundColor: AppColors.background,
          appBarTheme: const AppBarTheme(backgroundColor: AppColors.background),
          cardTheme: CardThemeData(
            color: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.cyan, width: 1.8),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.background,
              minimumSize: const Size.fromHeight(54),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cyan,
              side: const BorderSide(color: AppColors.cyan, width: 1.2),
              minimumSize: const Size.fromHeight(54),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
            ),
          ),
        ),
        home: const AppShell(),
      );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final StorageService _storage = StorageService();
  AppUser? _user;
  bool _showSplash = true;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
    Future.delayed(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  Future<void> _restoreSession() async {
    try {
      final user = await _storage.savedUser();
      if (mounted) setState(() { _user = user; _restoringSession = false; });
    } catch (error) {
      debugPrint('Session restore failed: $error');
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  Future<void> _openSession(AppUser user) async {
    try {
      await _storage.saveSession(user);
    } catch (error) {
      debugPrint('Session save failed: $error');
    }
    if (mounted) setState(() => _user = user);
  }

  Future<void> _logout() async {
    try {
      await _storage.clearSession();
    } catch (error) {
      debugPrint('Session clear failed: $error');
    }
    if (mounted) setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash || _restoringSession) {
      return const Scaffold(
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image(image: AssetImage('assets/icon.png'), width: 116, height: 116),
          SizedBox(height: 20),
          Text('ДесьЧУВ?', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          Text('Слухай. Вгадуй. Перемагай.', style: TextStyle(color: AppColors.muted)),
        ])),
      );
    }
    if (_user == null) {
      return AuthScreen(
        storage: _storage,
        onLoggedIn: (user) => unawaited(_openSession(user)),
      );
    }
    // Нові й старі акаунти без нікнейму проходять цей крок лише один раз.
    if (_user!.nickname == null || _user!.nickname!.trim().isEmpty) {
      return NicknameScreen(
        storage: _storage,
        user: _user!,
        onSaved: (user) => setState(() => _user = user),
      );
    }
    return HomeScreen(
      storage: _storage,
      user: _user!,
      onLogout: () => unawaited(_logout()),
    );
  }
}
