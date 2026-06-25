import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class GrandFinaleScreen extends StatefulWidget {
  const GrandFinaleScreen({super.key});
  @override State<GrandFinaleScreen> createState() => _GrandFinaleScreenState();
}

class _GrandFinaleScreenState extends State<GrandFinaleScreen> with TickerProviderStateMixin {
  late ConfettiController _confetti;
  final _audioPlayer = AudioPlayer();
  bool _dialogShown = false;
  bool _heartsRunning = true;
  final List<_Heart> _hearts = [];

  @override void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 8));
    _confetti.play();
    _audioPlayer.play(AssetSource('yongchun.mp3'));
    _audioPlayer.onPlayerComplete.listen((_) {
      _audioPlayer.dispose();
    });
    _spawnHearts();
  }

  void _spawnHearts() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted || !_heartsRunning) return false;
      setState(() {
        _hearts.add(_Heart(
          x: (DateTime.now().millisecondsSinceEpoch % 400) / 400.0,
          birth: DateTime.now(),
        ));
        _hearts.removeWhere((h) => DateTime.now().difference(h.birth).inSeconds > 4);
      });
      return _hearts.length < 30;
    });
  }

  @override void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dialogShown) {
      _dialogShown = true;
      Future.delayed(const Duration(milliseconds: 500), () => _showThanks(context));
    }
  }

  void _showThanks(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('🎉 开发者真心感谢你的使用', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('练申论 v1.0.0-alpha.58', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('隐藏版本号：build-${DateTime.now().millisecondsSinceEpoch ~/ 1000}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
        actions: [TextButton(onPressed: () { Navigator.pop(c); _goBack(); }, child: const Text('感谢'))],
      ),
    );
  }

  void _goBack() { _heartsRunning = false; _confetti.stop(); Navigator.of(context).popUntil((r) => r.isFirst); }

  @override void dispose() { _confetti.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        ..._hearts.map((h) => _HeartWidget(heart: h, vsync: this)),
        Align(alignment: Alignment.topCenter, child: ConfettiWidget(
          confettiController: _confetti, blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: true,
          colors: const [Color(0xFFE94560), Color(0xFFF9CA24), Color(0xFF4ECDC4), Color(0xFF6C5CE7), Color(0xFF00B894)],
          numberOfParticles: 20, maxBlastForce: 15, minBlastForce: 5)),
        const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.emoji_events, size: 80, color: Color(0xFFF9CA24)),
          SizedBox(height: 16),
          Text('全部成就已解锁！', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        ])),
      ]),
    );
  }
}

class _Heart {
  final double x;
  final DateTime birth;
  _Heart({required this.x, required this.birth});
}

class _HeartWidget extends StatefulWidget {
  final _Heart heart;
  final TickerProvider vsync;
  const _HeartWidget({required this.heart, required this.vsync});
  @override State<_HeartWidget> createState() => _HeartWidgetState();
}

class _HeartWidgetState extends State<_HeartWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(seconds: 3), vsync: this);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 70),
    ]).animate(_ctrl);
    _ctrl.forward().then((_) { if (mounted) setState(() {}); });
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.heart.birth).inMilliseconds;
    if (elapsed > 4000) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) => Positioned(
        left: MediaQuery.of(context).size.width * widget.heart.x,
        top: 100 - (elapsed / 40),
        child: Opacity(
          opacity: _opacity.value,
          child: const Icon(Icons.favorite, color: Color(0xFFE94560), size: 32),
        ),
      ),
    );
  }
}
