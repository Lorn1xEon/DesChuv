import 'package:flutter/material.dart';
import '../main.dart';
import '../services/storage_service.dart';

// Вводимо нікнейм один раз — після реєстрації або для старого акаунта.
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key, required this.storage,
    required this.user, required this.onSaved});

  final StorageService storage;
  final AppUser user;
  final ValueChanged<AppUser> onSaved;

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      final user = await widget.storage.setNickname(widget.user, _controller.text);
      if (mounted) widget.onSaved(user);
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : 'Не вдалося зберегти нікнейм. Спробуй ще раз.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(
            width: 86, height: 86,
            decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.line)),
            child: const Icon(Icons.person_outline_rounded, size: 44, color: AppColors.cyan),
          )),
          const SizedBox(height: 20),
          const Text('Як тебе називати?', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Це ім’я побачиш на головному екрані.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 28),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Нікнейм', hintText: 'Наприклад, MusicFox'),
          ),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: const TextStyle(color: AppColors.coral)),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
              ? const SizedBox(width: 23, height: 23,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.background))
              : const Text('Продовжити'),
          ),
        ]),
      ),
    ))),
  );
}
