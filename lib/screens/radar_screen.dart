import 'package:flutter/material.dart';
import 'dart:math';
import '../database/db_helper.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});
  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final _db = DatabaseHelper();
  Map<String, double> _scores = {};
  int _totalPractice = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await _db.getPracticeHistory(limit: 200);
      final typeScores = <String, List<int>>{};

      for (final r in history) {
        final qid = r['question_id'] as String?;
        final score = r['score'] as int?;
        if (qid == null || score == null) continue;
        final q = await _db.getQuestionById(qid);
        if (q == null) continue;
        var qt = q['question_type'] as String? ?? '';
        if (qt.contains('应用文')) qt = '应用文';
        if (qt.contains('大作文') || qt.contains('文章论述')) qt = '大作文';
        typeScores.putIfAbsent(qt, () => []).add(score);
      }

      final scores = <String, double>{};
      for (final e in typeScores.entries) {
        final avg = e.value.reduce((a, b) => a + b) / e.value.length;
        scores[e.key] = (avg / 30).clamp(0.1, 1.0); // normalize to 0-1
      }

      if (mounted) setState(() {
        _scores = scores;
        _totalPractice = history.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自我分析')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                if (_totalPractice == 0)
                  Container(
                    padding: const EdgeInsets.all(40),
                    child: Column(children: [
                      Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('暂无练习数据', style: TextStyle(color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('完成练习后这里会展示能力分析图', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                    ]),
                  )
                else ...[
                  const Text('能力雷达图', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 280,
                    child: CustomPaint(
                      size: const Size(280, 280),
                      painter: _RadarPainter(_scores),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('总练习次数：$_totalPractice', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ],
              ]),
            ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Map<String, double> scores;
  _RadarPainter(this.scores);

  static const _labels = ['概括归纳', '综合分析', '提出对策', '应用文', '大作文'];
  static const _colors = [
    Color(0xFF4ECDC4), Color(0xFFA29BFE), Color(0xFFF9CA24),
    Color(0xFF6C5CE7), Color(0xFFE94560),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 30;
    final n = _labels.length;

    // Draw grid
    final gridPaint = Paint()..color = Colors.grey.shade300..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (int level = 1; level <= 5; level++) {
      final r = radius * level / 5;
      final path = Path();
      for (int i = 0; i < n; i++) {
        final angle = -pi / 2 + 2 * pi * i / n;
        final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
        if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Draw axes
    final axisPaint = Paint()..color = Colors.grey.shade400..strokeWidth = 1;
    for (int i = 0; i < n; i++) {
      final angle = -pi / 2 + 2 * pi * i / n;
      canvas.drawLine(center, Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle)), axisPaint);
    }

    // Draw data
    final dataPath = Path();
    final fillPaint = Paint()..color = const Color(0xFF4ECDC4).withOpacity(0.2)..style = PaintingStyle.fill;
    final strokePaint = Paint()..color = const Color(0xFF4ECDC4)..style = PaintingStyle.stroke..strokeWidth = 2;

    for (int i = 0; i < n; i++) {
      final v = scores[_labels[i]] ?? 0.3;
      final r = radius * v;
      final angle = -pi / 2 + 2 * pi * i / n;
      final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
      if (i == 0) dataPath.moveTo(p.dx, p.dy); else dataPath.lineTo(p.dx, p.dy);
    }
    dataPath.close();
    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, strokePaint);

    // Draw labels
    for (int i = 0; i < n; i++) {
      final angle = -pi / 2 + 2 * pi * i / n;
      final lp = Offset(center.dx + (radius + 24) * cos(angle), center.dy + (radius + 24) * sin(angle));
      final tp = TextPainter(
        text: TextSpan(text: _labels[i], style: TextStyle(fontSize: 11, color: _colors[i], fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lp.dx - tp.width / 2, lp.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
