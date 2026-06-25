import 'package:flutter/material.dart';
import '../services/daily_push.dart';

class DailyPushCard extends StatelessWidget {
  final DailyPush push;
  final VoidCallback? onClose;
  const DailyPushCard({super.key, required this.push, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: push.bgColor.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [push.bgColor, push.bgColor.withOpacity(0.8)],
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(children: [
                const Icon(Icons.wb_sunny, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text('${push.theme} · ${push.date}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white54, size: 16),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(push.summary,
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.8),
                  maxLines: 20,
                  overflow: TextOverflow.ellipsis),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.08)),
              child: Text(push.quote, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 全屏推送查看页
class DailyPushScreen extends StatelessWidget {
  final DailyPush push;
  const DailyPushScreen({super.key, required this.push});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [push.bgColor, push.bgColor.withOpacity(0.6)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const Spacer(flex: 1),
              Text(push.date, style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 16),
              Text(push.theme, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              Text(push.summary, style: const TextStyle(color: Colors.white70, fontSize: 17, height: 1.8)),
              const Spacer(flex: 2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                child: Text(push.quote, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontStyle: FontStyle.italic, height: 1.4)),
              ),
              const Spacer(flex: 1),
            ]),
          ),
        ),
      ),
    );
  }
}
