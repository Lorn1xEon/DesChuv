import 'package:flutter/material.dart';
import '../main.dart';
import '../services/storage_service.dart';
import 'quiz_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.storage, required this.user, required this.onLogout});
  final StorageService storage;
  final AppUser user;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<GameResult>> _history;
  late Future<GameStats> _stats;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _history = widget.storage.results(widget.user.id);
    _stats = widget.storage.stats(widget.user.id);
  }

  Future<void> _play() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      QuizScreen(storage: widget.storage, user: widget.user)));
    if (mounted) setState(_refresh);
  }

  Future<void> _delete() async {
    final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DeleteAccountScreen(storage: widget.storage, user: widget.user),
    ));
    if (mounted && deleted == true) widget.onLogout();
  }

  Widget _statCard(IconData icon, String value, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 23),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ДесьЧУВ?', style: TextStyle(fontWeight: FontWeight.w900)),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Акаунт',
          icon: const Icon(Icons.account_circle_outlined, size: 28),
          onSelected: (value) {
            if (value == 'logout') widget.onLogout();
            if (value == 'delete') _delete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'logout', child: Text('Вийти з акаунта')),
            PopupMenuItem(value: 'delete', child: Text('Видалити акаунт')),
          ],
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 550),
      child: ListView(padding: const EdgeInsets.fromLTRB(22, 12, 22, 24), children: [
        Text('Привіт, ${widget.user.nickname ?? 'Гравцю'}!',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 17),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 27, 22, 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF2A3555), Color(0xFF1B283C), Color(0xFF192B37)],
            ),
            border: Border.all(color: const Color(0xFF455874)),
            borderRadius: BorderRadius.circular(27),
          ),
          child: Column(children: [
            Container(
              width: 105, height: 105,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: .55),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cyan.withValues(alpha: .5)),
              ),
              child: Image.asset('assets/icon.png'),
            ),
            const SizedBox(height: 16),
            const Text('Впізнаєш цей трек?', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('10 раундів  ·  15 секунд',
              style: TextStyle(color: AppColors.muted, fontSize: 14)),
            const SizedBox(height: 25),
            SizedBox(width: double.infinity,
              child: FilledButton.icon(
                onPressed: _play,
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: const Text('Грати', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Твій прогрес', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<GameStats>(
          future: _stats,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            return Row(children: [
              _statCard(Icons.emoji_events_outlined,
                stats == null || stats.played == 0 ? '—' : '${stats.best}/10',
                'Найкращий результат', AppColors.cyan),
              const SizedBox(width: 12),
              _statCard(Icons.sports_esports_outlined,
                stats?.played.toString() ?? '—', 'Зіграно ігор', AppColors.coral),
            ]);
          },
        ),
        const SizedBox(height: 25),
        const Text('Останні ігри', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        FutureBuilder<List<GameResult>>(
          future: _history,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            );
            final items = snapshot.data!;
            if (items.isEmpty) return const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Тут з’являться твої результати.',
                style: TextStyle(color: AppColors.muted)),
            );
            return Column(children: items.take(3).map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppColors.line),
                ),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.music_note_rounded, color: AppColors.cyan),
                  title: Text('${r.score} / ${r.total}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                  trailing: Text(
                    '${r.playedAt.day.toString().padLeft(2, '0')}.${r.playedAt.month.toString().padLeft(2, '0')}.${r.playedAt.year}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ),
            )).toList());
          },
        ),
      ]),
    ))),
  );
}

// Екран підтвердження видалення акаунта.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.storage, required this.user});
  final StorageService storage;
  final AppUser user;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.storage.deleteAccount(widget.user, _password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : 'Не вдалося видалити акаунт. Спробуй ще раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Видалення акаунта')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(
            width: 78, height: 78,
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.coral.withValues(alpha: .4))),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.coral, size: 39),
          )),
          const SizedBox(height: 21),
          const Text('Видалити акаунт?', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Акаунт і всі результати буде видалено безповоротно.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 25),
          TextField(controller: _password, obscureText: true,
            decoration: const InputDecoration(labelText: 'Підтверди паролем',
              prefixIcon: Icon(Icons.lock_outline_rounded))),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: AppColors.coral)),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
              foregroundColor: AppColors.background),
            child: _busy
              ? const SizedBox(width: 23, height: 23,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.background))
              : const Text('Видалити назавжди'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Скасувати')),
        ]),
      ),
    ))),
  );
}
