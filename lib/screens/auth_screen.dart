import 'package:flutter/material.dart';
import '../main.dart';
import '../services/storage_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.storage, required this.onLoggedIn});
  final StorageService storage;
  final ValueChanged<AppUser> onLoggedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_register && _password.text != _confirmPassword.text) {
      setState(() => _error = 'Паролі не збігаються.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final user = _register
          ? await widget.storage.register(_email.text, _password.text)
          : await widget.storage.login(_email.text, _password.text);
      if (mounted) widget.onLoggedIn(user);
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : 'Не вдалося виконати вхід або реєстрацію. Спробуй ще раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchMode() {
    setState(() {
      _register = !_register;
      _error = null;
      _confirmPassword.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(
                width: 76, height: 76,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: AppColors.line),
                ),
                child: Image.asset('assets/icon.png'),
              )),
              const SizedBox(height: 16),
              const Text('ДесьЧУВ?', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: .3)),
              const SizedBox(height: 7),
              Text(_register ? 'Створи акаунт і почни гру' : 'З поверненням!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 28),
              Text(_register ? 'Реєстрація' : 'Вхід',
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Електронна пошта', prefixIcon: Icon(Icons.alternate_email_rounded)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                onSubmitted: _register ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Сховати пароль' : 'Показати пароль',
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPassword,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Повтори пароль', prefixIcon: Icon(Icons.verified_user_outlined)),
                ),
              ],
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: AppColors.coral)),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 23, height: 23,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.background))
                    : Text(_register ? 'Створити акаунт' : 'Увійти'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : _switchMode,
                child: Text(_register ? 'У мене вже є акаунт' : 'Зареєструватися'),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}
