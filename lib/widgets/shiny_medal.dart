import 'package:flutter/material.dart';

class ShinyMedal extends StatefulWidget {
  const ShinyMedal({super.key});
  @override State<ShinyMedal> createState() => _ShinyMedalState();
}

class _ShinyMedalState extends State<ShinyMedal> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _rotate;
  late Animation<double> _scale;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _rotate = Tween<double>(begin: -0.08, end: 0.08).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.25), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1.25, end: 1.0), weight: 85),
    ]).animate(_ctrl);
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, _) => Transform.rotate(
          angle: _rotate.value,
          child: Transform.scale(
            scale: _scale.value,
            child: const Stack(alignment: Alignment.center, children: [
              // Outer colorful glow rings
              Icon(Icons.military_tech, size: 50, color: Color(0x30E94560)),
              Icon(Icons.military_tech, size: 46, color: Color(0x30F9CA24)),
              Icon(Icons.military_tech, size: 42, color: Color(0x304ECDC4)),
              Icon(Icons.military_tech, size: 38, color: Color(0x306C5CE7)),
              // Main multicolored layer
              Icon(Icons.military_tech, size: 34, color: Color(0xFFF9CA24)),
              Icon(Icons.military_tech, size: 32, color: Color(0xFFE94560)),
            ]),
          ),
        ),
      ),
    );
  }
}
