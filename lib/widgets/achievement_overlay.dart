import 'package:flutter/material.dart';

class AchievementOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final String? imageAsset;
  final String title;
  final String content;
  final String tagline;
  final bool useIcon;
  final String? iconTier;

  const AchievementOverlay({
    super.key,
    required this.onDismiss,
    this.imageAsset,
    this.title = '情书不朽',
    this.content = '与你的下一次邂逅，是十二万亿九千六百年后',
    this.tagline = '情书再不朽 也磨成沙漏。你已获得成就',
    this.useIcon = false,
    this.iconTier,
  });

  @override State<AchievementOverlay> createState() => _AchievementOverlayState();
}

class _AchievementOverlayState extends State<AchievementOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slide;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _slide = Tween<double>(begin: -120, end: 20).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) { if (mounted) widget.onDismiss(); });
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) => Positioned(
        top: _slide.value, left: 16, right: 16,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _dismiss,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withOpacity(0.95),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF9CA24).withOpacity(0.4)),
                boxShadow: [BoxShadow(color: const Color(0xFFF9CA24).withOpacity(0.15), blurRadius: 20)],
              ),
              child: Row(children: [
                if (widget.imageAsset != null)
                  ClipRRect(borderRadius: BorderRadius.circular(10),
                    child: Image.asset(widget.imageAsset!, width: 64, height: 64, fit: BoxFit.cover))
                else
                  const SizedBox(width: 64),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [const Icon(Icons.emoji_events, color: Color(0xFFF9CA24), size: 16), const SizedBox(width: 6), Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))]),
                  const SizedBox(height: 4),
                  Text(widget.content, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFF9CA24).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(widget.tagline, style: const TextStyle(color: Color(0xFFF9CA24), fontSize: 10, fontWeight: FontWeight.w600))),
                ])),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
