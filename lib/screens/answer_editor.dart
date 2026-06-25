import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class AnswerEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool readOnly;
  const AnswerEditor({super.key, required this.controller, this.readOnly = false});
  @override
  State<AnswerEditor> createState() => AnswerEditorState();
}

class AnswerEditorState extends State<AnswerEditor> {
  String _tool = 'none'; // 'pen' | 'yellow' | 'red'
  final List<_Stroke> _strokes = [];
  _Stroke? _cur;
  final List<_Hl> _hls = [];
  final List<_Act> _undo = [];
  final FocusNode _fn = FocusNode();

  @override
  void dispose() { _fn.dispose(); super.dispose(); }

  void _applyHighlight(Color c) {
    final t = widget.controller.text;
    if (t.isEmpty) return;
    final sel = widget.controller.selection;
    int s, e;
    if (sel.isValid && sel.start < sel.end) { s = sel.start; e = sel.end; }
    else if (sel.isValid) {
      s = e = sel.baseOffset;
      while (s > 0 && !RegExp(r'[，。；！？、\s\n]').hasMatch(t[s - 1])) s--;
      while (e < t.length && !RegExp(r'[，。；！？、\s\n]').hasMatch(t[e])) e++;
      if (s >= e) return;
    } else return;
    final ex = _hls.where((x) => x.s == s && x.e == e).toList();
    if (ex.isNotEmpty) { for (final x in ex) { _hls.remove(x); _undo.add(_RmHl(x)); } }
    else { final h = _Hl(s, e, c); _hls.add(h); _undo.add(_AddHl(h)); }
    widget.controller.selection = TextSelection.collapsed(offset: e);
    setState(() {});
  }

  void _undoAct() { if (_undo.isEmpty) return; final a = _undo.removeLast(); a.undo(); setState(() {}); }
  void _clear() { _strokes.clear(); _hls.clear(); _undo.clear(); setState(() {}); }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!widget.readOnly)
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE8D5D5)))),
          child: Row(children: [
            _tb('🖊️', 'pen'), _tb('🟡', 'yellow'), _tb('🔴', 'red'),
            const SizedBox(width: 8),
            _icon(Icons.undo, _undo.isNotEmpty ? _undoAct : null),
            _icon(Icons.delete_outline, (_strokes.isNotEmpty || _hls.isNotEmpty) ? _clear : null),
          ]),
        ),
      ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: 200,
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        child: IntrinsicHeight(
          child: _tool == 'pen'
              ? RawGestureDetector(
                  gestures: <Type, GestureRecognizerFactory>{
                    _AEDrag: GestureRecognizerFactoryWithHandlers<_AEDrag>(
                      () => _AEDrag(),
                      (r) {
                        r.onStart = (pos) { _cur = _Stroke(const Color(0xCCE94560)); _cur!.pts.add(pos); setState(() {}); };
                        r.onUpdate = (pos) { _cur?.pts.add(pos); setState(() {}); };
                        r.onEnd = () { if (_cur != null && _cur!.pts.length > 1) { _strokes.add(_cur!); _undo.add(_Pen(_cur!)); } _cur = null; setState(() {}); };
                      },
                    ),
                  },
                  child: CustomPaint(
                    painter: _P(_strokes, _cur, _hls, true),
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          focusNode: _fn, controller: widget.controller, maxLines: null,
                          readOnly: true, textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(fontSize: 17, height: 1.65, color: Color(0xFF333333), letterSpacing: 1),
                          decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true),
                        ),
                      ),
                    ),
                  ),
                )
              : CustomPaint(
                  painter: _P(_strokes, _cur, _hls, false),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      focusNode: _fn, controller: widget.controller, maxLines: null,
                      readOnly: widget.readOnly, textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 17, height: 1.65, color: Color(0xFF333333), letterSpacing: 1),
                      decoration: InputDecoration(
                        hintText: widget.readOnly ? '' : '请在此作答...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        border: InputBorder.none, isCollapsed: true,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    ]);
  }

  Widget _tb(String i, String m) {
    final a = _tool == m;
    return GestureDetector(
      onTap: () {
        if (m == 'yellow' || m == 'red') {
          // 先选中文字，再点高亮按钮应用
          final c = m == 'red' ? const Color(0x40FF0000) : const Color(0x40FFD700);
          _applyHighlight(c);
        } else {
          // 画笔切换
          setState(() => _tool = a ? 'none' : m);
        }
      },
      child: Container(
        width: 36, height: 36, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: a ? const Color(0xFFFFF8F0) : Colors.transparent, borderRadius: BorderRadius.circular(8),
            border: a ? Border.all(color: const Color(0xFFCC3333), width: 1.5) : null),
        child: Center(child: Text(i, style: TextStyle(fontSize: a ? 18 : 16))),
      ),
    );
  }

  Widget _icon(IconData i, VoidCallback? cb) {
    return GestureDetector(
      onTap: cb,
      child: Container(width: 36, height: 36, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: cb != null ? Colors.grey.shade100 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
        child: Icon(i, size: 18, color: cb != null ? const Color(0xFF333333) : Colors.grey.shade300)),
    );
  }
}

// ── Models ──
class _Stroke { final Color c; final List<Offset> pts = []; _Stroke(this.c); }
class _Hl { int s, e; Color c; _Hl(this.s, this.e, this.c); }
abstract class _Act { void undo(); }
class _Pen extends _Act { final _Stroke s; _Pen(this.s); void undo() {} }
class _AddHl extends _Act { final _Hl h; _AddHl(this.h); void undo() {} }
class _RmHl extends _Act { final _Hl h; _RmHl(this.h); void undo() {} }

// ── Painter ──
class _P extends CustomPainter {
  final List<_Stroke> ss; final _Stroke? cur; final List<_Hl> hs; final bool anyTool;
  _P(this.ss, this.cur, this.hs, this.anyTool);

  static const lineHeight = 28.0;
  static const leftMargin = 16.0;

  @override
  void paint(Canvas c, Size sz) {
    // Horizontal writing lines
    final linePaint = Paint()..color = const Color(0xFFDDCCCC)..strokeWidth = 0.8;
    for (double y = lineHeight; y <= sz.height; y += lineHeight)
      c.drawLine(Offset(0, y), Offset(sz.width, y), linePaint);

    // Red left margin
    c.drawLine(const Offset(leftMargin, 0), Offset(leftMargin, sz.height),
        Paint()..color = const Color(0xFFCC3333)..strokeWidth = 1.5);

    // Highlights
    for (final h in hs) {
      final row = (h.s / 25).floor();
      final col = h.s % 25;
      final span = (h.e - h.s).clamp(1, 25);
      final l = leftMargin + 4 + col * 12.5;
      final w = span * 12.5;
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(l, row * lineHeight + 3, w, 22), const Radius.circular(3)),
        Paint()..color = h.c,
      );
    }

    // Strokes
    final sp = Paint()..strokeWidth = 2.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final s in ss) { sp.color = s.c; _draw(c, s, sp); }
    if (cur != null) { sp.color = cur!.c; _draw(c, cur!, sp); }

    if (anyTool) {
      final tp = TextPainter(
        text: const TextSpan(text: '✏️ 标注模式（点工具栏退出）', style: TextStyle(fontSize: 11, color: Color(0x99CC3333))),
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: sz.width - 32);
      tp.paint(c, Offset(20, sz.height - 24));
    }
  }

  void _draw(Canvas c, _Stroke s, Paint p) {
    if (s.pts.length < 2) return;
    final path = Path()..moveTo(s.pts.first.dx, s.pts.first.dy);
    for (int i = 1; i < s.pts.length; i++) path.lineTo(s.pts[i].dx, s.pts[i].dy);
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

/// 水平拖拽手势 — 只认水平画线，垂直穿透给外层滚动
class _AEDrag extends OneSequenceGestureRecognizer {
  Offset? _sp; bool _h = false;
  void Function(Offset)? onStart; void Function(Offset)? onUpdate; VoidCallback? onEnd;
  @override void addAllowedPointer(PointerDownEvent e) { startTrackingPointer(e.pointer); _sp = e.localPosition; _h = false; }
  @override void handleEvent(PointerEvent e) {
    if (e is PointerMoveEvent && _sp != null) {
      final dx = (e.localPosition.dx - _sp!.dx).abs(), dy = (e.localPosition.dy - _sp!.dy).abs();
      if (!_h && (dx > 3 || dy > 3)) { if (dx >= dy) { _h = true; resolve(GestureDisposition.accepted); onStart?.call(_sp!); } else { resolve(GestureDisposition.rejected); stopTrackingPointer(e.pointer); } }
      if (_h) onUpdate?.call(e.localPosition);
    }
    if (e is PointerUpEvent || e is PointerCancelEvent) { if (_h) onEnd?.call(); _sp = null; _h = false; stopTrackingPointer(e.pointer); }
  }
  @override String get debugDescription => '_AEDrag';
  @override void didStopTrackingLastPointer(int p) { _sp = null; _h = false; }
}
