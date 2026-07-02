import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class PatternDrawWidget extends StatefulWidget {
  final String? initialPattern; // e.g. "1-5-9"
  final ValueChanged<String?> onPatternChanged;

  const PatternDrawWidget({
    super.key,
    this.initialPattern,
    required this.onPatternChanged,
  });

  @override
  State<PatternDrawWidget> createState() => _PatternDrawWidgetState();
}

class _PatternDrawWidgetState extends State<PatternDrawWidget> {
  List<int> _pattern = []; // 0-based indices (0=node1 ... 8=node9)
  Offset? _drag;
  final _key = GlobalKey();

  static const double _gridSize = 210;
  static const double _hitRadius = 28;

  @override
  void initState() {
    super.initState();
    if (widget.initialPattern != null && widget.initialPattern!.isNotEmpty) {
      _pattern = widget.initialPattern!
          .split('-')
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .map((n) => n - 1)
          .where((n) => n >= 0 && n < 9)
          .toList();
    }
  }

  Offset _nodeCenter(int idx) {
    const cell = _gridSize / 3;
    final row = idx ~/ 3;
    final col = idx % 3;
    return Offset(cell * col + cell / 2, cell * row + cell / 2);
  }

  int? _hitTest(Offset local) {
    for (int i = 0; i < 9; i++) {
      if ((_nodeCenter(i) - local).distance <= _hitRadius) return i;
    }
    return null;
  }

  Offset _globalToLocal(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  void _onPanStart(DragStartDetails d) {
    final local = _globalToLocal(d.globalPosition);
    final hit = _hitTest(local);
    setState(() {
      _pattern = [];
      _drag = local;
      if (hit != null) _pattern.add(hit);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final local = _globalToLocal(d.globalPosition);
    final hit = _hitTest(local);
    setState(() {
      _drag = local;
      if (hit != null && !_pattern.contains(hit)) _pattern.add(hit);
    });
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _drag = null);
    widget.onPatternChanged(
      _pattern.isEmpty ? null : _pattern.map((i) => '${i + 1}').join('-'),
    );
  }

  void _clear() {
    setState(() {
      _pattern = [];
      _drag = null;
    });
    widget.onPatternChanged(null);
  }

  String get _patternText =>
      _pattern.map((i) => '${i + 1}').join(' → ');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: SizedBox(
            key: _key,
            width: _gridSize,
            height: _gridSize,
            child: CustomPaint(
              painter: _PatternPainter(pattern: _pattern, drag: _drag),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_pattern.isEmpty)
          Text(
            'Dibuje el patron en la cuadricula de 9 puntos',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            textAlign: TextAlign.center,
          )
        else
          Column(
            children: [
              Text(
                'Patron: $_patternText',
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Inicio: nodo ${_pattern.first + 1}  |  Fin: nodo ${_pattern.last + 1}  |  ${_pattern.length} puntos',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Borrar patron', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
      ],
    );
  }
}

class _PatternPainter extends CustomPainter {
  final List<int> pattern;
  final Offset? drag;

  const _PatternPainter({required this.pattern, this.drag});

  static const double _cell = 70.0; // 210 / 3
  static const double _nodeR = 14.0;

  Offset _center(int idx) {
    final row = idx ~/ 3;
    final col = idx % 3;
    return Offset(_cell * col + _cell / 2, _cell * row + _cell / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dragLinePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Lines between selected nodes
    for (int i = 0; i < pattern.length - 1; i++) {
      canvas.drawLine(_center(pattern[i]), _center(pattern[i + 1]), linePaint);
    }

    // Line from last node to current drag position
    if (pattern.isNotEmpty && drag != null) {
      canvas.drawLine(_center(pattern.last), drag!, dragLinePaint);
    }

    // Draw each node
    for (int i = 0; i < 9; i++) {
      final c = _center(i);
      final active = pattern.contains(i);
      final isFirst = pattern.isNotEmpty && pattern.first == i;
      final isLast = pattern.length > 1 && pattern.last == i;

      // Background fill
      canvas.drawCircle(
        c,
        _nodeR,
        Paint()
          ..color = active
              ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06)
          ..style = PaintingStyle.fill,
      );

      // Outer ring
      canvas.drawCircle(
        c,
        _nodeR,
        Paint()
          ..color = active ? const Color(0xFF00E5FF) : Colors.grey.withValues(alpha: 0.35)
          ..strokeWidth = active ? 2 : 1
          ..style = PaintingStyle.stroke,
      );

      // Inner dot
      canvas.drawCircle(
        c,
        5.5,
        Paint()
          ..color = active ? const Color(0xFF00E5FF) : Colors.grey.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill,
      );

      // Start marker (green ring)
      if (isFirst) {
        canvas.drawCircle(c, _nodeR + 5,
            Paint()
              ..color = const Color(0xFF4CAF50).withValues(alpha: 0.7)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke);
      }

      // End marker (red ring)
      if (isLast) {
        canvas.drawCircle(c, _nodeR + 5,
            Paint()
              ..color = const Color(0xFFF44336).withValues(alpha: 0.7)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke);
      }

      // Node number
      _drawText(canvas, '${i + 1}', c,
          active ? Colors.white : Colors.grey.withValues(alpha: 0.6), 9);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, Color color, double size) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: size,
      fontWeight: ui.FontWeight.bold,
    ))
      ..pushStyle(ui.TextStyle(color: color))
      ..addText(text);
    final p = pb.build()..layout(const ui.ParagraphConstraints(width: 20));
    canvas.drawParagraph(p, Offset(center.dx - 10, center.dy - p.height / 2));
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.pattern != pattern || old.drag != drag;
}
