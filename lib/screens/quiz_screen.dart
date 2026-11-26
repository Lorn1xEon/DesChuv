import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../main.dart';
import '../models/track.dart';
import '../services/catalog.dart';
import '../services/deezer_service.dart';
import '../services/storage_service.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.storage, required this.user});
  final StorageService storage;
  final AppUser user;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with TickerProviderStateMixin {
  static const roundLimit = 10;
  static const answerSeconds = 15;
  static const clipSeconds = 15;

  final _deezer = DeezerService();
  final _player = AudioPlayer();
  final _random = Random();
  final Map<int, String> _audioFiles = {};
  final List<bool> _answers = [];
  List<Track> _tracks = [];
  List<Track> _choices = [];
  Timer? _clipTimer, _nextTimer;
  late final AnimationController _timerController;
  late final AnimationController _equalizerController;

  int _round = 0;
  int _prepared = 0;
  int _loadVersion = 0;
  Duration _clipDuration = const Duration(seconds: clipSeconds);
  Track? _chosen;
  bool _preparing = true;
  bool _roundLoading = false;
  bool _clipFinished = false;
  bool _answered = false;
  bool _finished = false;
  bool _advancing = false;
  bool _exitDialogOpen = false;
  String? _error;
  String? _saveError;

  Track get _current => _tracks[_round];
  int get _score => _answers.where((correct) => correct).length;

  @override
  void initState() {
    super.initState();
    // Єдиний таймер раунду: контролер рухає коло плавно, кадр за кадром.
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: answerSeconds),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted &&
            !_answered && !_roundLoading && !_finished && _error == null) {
          _answer(null);
        }
      });
    // Легка декоративна хвиля. Не аналізує реальні частоти аудіо.
    _equalizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    unawaited(_prepareGame());
  }

  @override
  void dispose() {
    ++_loadVersion;
    _cancelTimers();
    _timerController.dispose();
    _equalizerController.dispose();
    _player.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    _timerController.stop();
    _equalizerController.stop();
    _clipTimer?.cancel();
    _nextTimer?.cancel();
  }

  Future<void> _prepareGame() async {
    final version = ++_loadVersion;
    _cancelTimers();
    await _player.stop();
    if (!mounted || version != _loadVersion) return;
    setState(() {
      _preparing = true;
      _error = null;
      _saveError = null;
      _prepared = 0;
      _finished = false;
      _tracks = [];
      _choices = [];
      _answers.clear();
    });
    final candidates = List<Track>.of(demoTracks)..shuffle(_random);
    final ready = <Track>[];
    final cached = <int, String>{};

    // До гри завантажуємо десять аудіофайлів, по три одночасно.
    for (var i = 0; i < candidates.length && ready.length < roundLimit; i += 3) {
      final outcomes = await Future.wait(candidates.skip(i).take(3).map((song) async {
        try {
          return (song, await _deezer.cachedPreview(song));
        } catch (_) {
          return (song, null);
        }
      }));
      if (!mounted || version != _loadVersion) return;
      for (final outcome in outcomes) {
        if (outcome.$2 != null && ready.length < roundLimit) {
          ready.add(outcome.$1);
          cached[outcome.$1.id] = outcome.$2!;
        }
      }
      setState(() => _prepared = ready.length);
    }
    if (!mounted || version != _loadVersion) return;
    if (ready.length < roundLimit) {
      setState(() {
        _preparing = false;
        _error = 'Вдалося підготувати лише ${ready.length} із $roundLimit треків. Перевір інтернет-з’єднання та спробуй ще раз.';
      });
      return;
    }
    _audioFiles..clear()..addAll(cached);
    _tracks = ready..shuffle(_random);
    _answers.clear();
    _round = 0;
    setState(() => _preparing = false);
    unawaited(_startRound());
  }

  Future<void> _startRound() async {
    _cancelTimers();
    _timerController.reset();
    await _player.stop();
    if (!mounted || _finished) return;
    final thisRound = _round;
    final others = List<Track>.of(_tracks)..removeWhere((t) => t.id == _current.id);
    others.shuffle(_random);
    setState(() {
      _choices = [_current, ...others.take(3)]..shuffle(_random);
      _chosen = null;
      _answered = false;
      _clipFinished = false;
      _roundLoading = true;
      _error = null;
    });

    try {
      final duration = await _player.setFilePath(_audioFiles[_current.id]!);
      if (!mounted || thisRound != _round || _answered) return;
      // Якщо файл коротший за 15 с, використовуємо всю його тривалість.
      final lengthMs = duration?.inMilliseconds;
      final clipMs = lengthMs != null && lengthMs > 0
          ? min(clipSeconds * 1000, lengthMs)
          : clipSeconds * 1000;
      _clipDuration = Duration(milliseconds: clipMs);
      await _player.setClip(start: Duration.zero, end: _clipDuration);
      await _player.setLoopMode(LoopMode.off);
      if (!mounted || thisRound != _round || _answered) return;
      setState(() => _roundLoading = false);

      // Якщо користувач відкрив діалог виходу під час завантаження, чекаємо.
      if (_exitDialogOpen) return;
      // Один 15-секундний відлік і лише одне відтворення уривка.
      _timerController.forward(from: 0);
      unawaited(_playOnce(thisRound));
      _clipTimer = Timer(_clipDuration, () {
        if (!mounted || thisRound != _round || _answered) return;
        _equalizerController.stop();
        setState(() => _clipFinished = true);
        unawaited(_player.pause());
      });
    } catch (_) {
      if (mounted && thisRound == _round) {
        setState(() {
          _roundLoading = false;
          _error = 'Не вдалося відтворити трек. Спробуй ще раз.';
        });
      }
    }
  }

  Future<void> _playOnce(int thisRound) async {
    try {
      // Еквалайзер оживає тільки під час відтворення.
      _equalizerController.repeat();
      await _player.play();
      if (!mounted || _round != thisRound || _answered) return;
      _equalizerController.stop();
      // Пауза для діалогу виходу не означає, що уривок закінчився.
      if (_exitDialogOpen || !_player.playing) return;
      setState(() => _clipFinished = true);
    } catch (_) {
      if (!mounted || _round != thisRound || _answered) return;
      _cancelTimers();
      setState(() => _error = 'Помилка відтворення аудіо. Спробуй ще раз.');
    }
  }

  void _answer(Track? selected) {
    if (_answered || _roundLoading || (_error != null && selected != null)) return;
    _cancelTimers();
    unawaited(_player.stop());
    final correct = selected?.id == _current.id;
    setState(() {
      _chosen = selected;
      _answered = true;
      _answers.add(correct);
    });
    _nextTimer = Timer(const Duration(milliseconds: 1900),
        () => unawaited(_nextRound()));
  }

  Future<void> _nextRound() async {
    if (_advancing || _finished || !mounted) return;
    _advancing = true;
    _cancelTimers();
    try {
      if (_round + 1 < _tracks.length) {
        _round++;
        await _startRound();
      } else {
        setState(() => _finished = true);
        try {
          await widget.storage.saveResult(widget.user.id, _score, _tracks.length);
        } catch (_) {
          if (mounted) setState(() => _saveError = 'Не вдалося зберегти результат гри.');
        }
      }
    } finally {
      _advancing = false;
    }
  }

  // Перехоплюємо і стрілку, і системну кнопку/жест «Назад».
  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) return;
    // Після завершення результат уже збережений — просто повертаємося.
    if (_finished) {
      Navigator.of(context).pop();
      return;
    }
    _exitDialogOpen = true;

    final wasCounting = _timerController.isAnimating;
    final wasPlaying = _player.playing && !_clipFinished && !_answered;
    final wasAdvancing = _nextTimer?.isActive == true;
    _timerController.stop();
    _equalizerController.stop();
    _clipTimer?.cancel();
    _nextTimer?.cancel();
    if (wasPlaying) {
      try { await _player.pause(); } catch (_) {}
    }
    if (!mounted) return;

    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 370),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.logout_rounded, color: AppColors.coral, size: 38),
              const SizedBox(height: 14),
              const Text('Вийти з гри?', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 9),
              const Text('Поточна гра не збережеться.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 14)),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Продовжити')),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.coral,
                  side: const BorderSide(color: AppColors.coral),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Вийти'),
              ),
            ]),
          ),
        ),
      ),
    );
    _exitDialogOpen = false;
    if (!mounted) return;
    if (leave == true) {
      _cancelTimers();
      try { await _player.stop(); } catch (_) {}
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (_answered && wasAdvancing) {
      _nextTimer = Timer(const Duration(milliseconds: 900),
          () => unawaited(_nextRound()));
    } else if (!_answered && !_finished && !_preparing && !_roundLoading &&
        _error == null && _tracks.isNotEmpty) {
      // Продовжуємо з того ж місця, без повторного програвання фрагмента.
      if (wasCounting) _timerController.forward();
      // Початок раунду міг завершитися вже під час відкритого діалогу.
      final startAfterLoading = !wasCounting && !wasPlaying &&
          _timerController.value == 0 && !_clipFinished;
      if (startAfterLoading) _timerController.forward(from: 0);
      if (wasPlaying || startAfterLoading) {
        final remaining = _clipDuration - _player.position;
        if (remaining > Duration.zero) {
          unawaited(_playOnce(_round));
          _clipTimer = Timer(remaining, () {
            if (!mounted || _answered || _finished) return;
            _equalizerController.stop();
            setState(() => _clipFinished = true);
            unawaited(_player.pause());
          });
        } else {
          setState(() => _clipFinished = true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_confirmExit());
    },
    child: Scaffold(
    appBar: AppBar(
      toolbarHeight: 51,
      leading: IconButton(
        tooltip: 'Вийти з гри',
        onPressed: _confirmExit,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: _preparing ? _loadingView() : _finished ? _resultView() :
          _tracks.isEmpty ? _failedView() : _gameView(),
    ))),
    ),
  );

  Widget _loadingView() => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.library_music_outlined, size: 64, color: AppColors.cyan),
      const SizedBox(height: 22),
      const Text('Готуємо музичний раунд', style: TextStyle(
        fontSize: 23, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Text('Завантажено $_prepared / $roundLimit уривків',
          style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 18),
      LinearProgressIndicator(value: _prepared / roundLimit,
          color: AppColors.cyan, minHeight: 9),
    ]),
  );

  Widget _failedView() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(_error ?? 'Не вдалося почати гру', textAlign: TextAlign.center),
      const SizedBox(height: 16),
      FilledButton(onPressed: _prepareGame, child: const Text('Повторити підготовку')),
    ]),
  );

  // Немає ListView: гра займає рівно доступну висоту без прокрутки.
  // Область відповідей розтягується залежно від висоти екрана.
  Widget _gameView() => LayoutBuilder(builder: (context, constraints) {
    final compact = constraints.maxHeight < 600;
    final gap = compact ? 8.0 : 13.0;
    final pad = compact ? 12.0 : 18.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 10),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Раунд ${_round + 1} / $roundLimit',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: .12),
              border: Border.all(color: AppColors.cyan.withValues(alpha: .55)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.emoji_events_rounded, color: AppColors.cyan, size: 20),
              const SizedBox(width: 7),
              Text('$_score', style: const TextStyle(
                fontSize: 23, fontWeight: FontWeight.w900,
                color: Colors.white,
              )),
            ]),
          ),
        ]),
        SizedBox(height: gap),
        Row(children: List.generate(roundLimit, (i) => Expanded(child: Container(
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: i < _answers.length
                ? (_answers[i] ? AppColors.cyan : AppColors.coral)
                : i == _round ? Colors.amber : AppColors.card,
          ),
        )))),
        SizedBox(height: gap),
        Expanded(flex: 4, child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 5),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _timeRing(compact),
              const SizedBox(height: 10),
              _equalizer(compact),
              const SizedBox(height: 5),
              if (_error != null) ...[
                Text('Помилка відтворення',
                  style: const TextStyle(color: AppColors.coral, fontSize: 12)),
                TextButton(onPressed: _startRound,
                  child: const Text('Спробувати ще раз')),
              ] else if (_answered || _roundLoading)
                Text(_answered
                    ? (_chosen?.id == _current.id ? 'Правильно!' : 'Це: ${_current.label}')
                    : 'Готуємо звук…',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        )),
        SizedBox(height: gap),
        Expanded(flex: 6, child: Column(children: List.generate(_choices.length, (i) {
          final track = _choices[i];
          final isCorrect = _answered && track.id == _current.id;
          final isWrong = _answered && _chosen?.id == track.id && !isCorrect;
          return Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: SizedBox(width: double.infinity, child: OutlinedButton(
              onPressed: _answered || _roundLoading || _error != null
                  ? null : () => _answer(track),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 17),
                backgroundColor: isCorrect ? AppColors.cyan.withValues(alpha: .16)
                    : isWrong ? AppColors.coral.withValues(alpha: .16) : AppColors.card,
                side: BorderSide(color: isCorrect ? AppColors.cyan
                    : isWrong ? AppColors.coral : const Color(0xFF37445E)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(track.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: compact ? 13 : 15)),
            )),
          ));
        }))),
      ]),
    );
  });


  // Плавний 15-секундний індикатор: без другого таймера й зайвої смуги.
  Widget _timeRing(bool compact) => AnimatedBuilder(
    animation: _timerController,
    builder: (context, _) {
      final fraction = (1.0 - _timerController.value).clamp(0.0, 1.0);
      final left = (answerSeconds * fraction).ceil();
      final tint = left <= 5 ? AppColors.coral : AppColors.cyan;
      final side = compact ? 78.0 : 104.0;
      return Container(
        width: side,
        height: side,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(color: tint.withValues(alpha: .16), blurRadius: 24),
        ]),
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(child: CircularProgressIndicator(
            value: fraction,
            strokeCap: StrokeCap.round,
            strokeWidth: 7,
            color: tint,
            backgroundColor: const Color(0xFF3B4659),
          )),
          Text('$left', style: TextStyle(
            fontSize: compact ? 32 : 42,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          )),
        ]),
      );
    },
  );

  // Візуалізація звучання: легка анімація, не справжній FFT-еквалайзер.
  Widget _equalizer(bool compact) {
    final maxHeight = compact ? 20.0 : 27.0;
    return SizedBox(
      height: maxHeight,
      child: AnimatedBuilder(
        animation: _equalizerController,
        builder: (context, _) {
          final active = _equalizerController.isAnimating &&
              !_clipFinished && !_answered && !_roundLoading;
          final phase = _equalizerController.value * 2 * pi;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(11, (i) {
              final wave = sin(phase + i * .65).abs();
              final detail = sin(phase * 2 + i * 1.13).abs();
              final fraction = active ? .20 + .53 * wave + .24 * detail : .18;
              return Container(
                width: compact ? 3.4 : 4.2,
                height: max(4.0, maxHeight * fraction),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i.isEven ? AppColors.cyan : AppColors.coral,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _resultView() => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.emoji_events_outlined, color: AppColors.cyan, size: 78),
      const SizedBox(height: 18),
      const Text('Гру завершено!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 18),
      Text('$_score / ${_tracks.length}',
          style: const TextStyle(fontSize: 58, fontWeight: FontWeight.bold)),
      const Text('правильних відповідей',
          style: TextStyle(color: AppColors.muted)),
      if (_saveError != null) Padding(padding: const EdgeInsets.all(12),
          child: Text(_saveError!, style: const TextStyle(color: AppColors.coral))),
      const SizedBox(height: 26),
      FilledButton(onPressed: () => Navigator.of(context).pop(),
          child: const Text('На головну')),
    ]),
  );
}
