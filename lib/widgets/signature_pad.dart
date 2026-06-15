import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignaturePad extends StatefulWidget {
  final void Function(String? base64Image) onSign;

  const SignaturePad({super.key, required this.onSign});

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  // Path grows incrementally — never rebuilt, just extended
  Path _path = Path();
  Offset? _lastPoint;

  // Incrementing this triggers only the canvas repaint, not a widget rebuild
  final _repaintTick = ValueNotifier<int>(0);
  final _repaintKey = GlobalKey();

  bool _hasStrokes = false;
  bool _isCapturing = false;

  @override
  void dispose() {
    _repaintTick.dispose();  // ValueNotifier is disposable
    super.dispose();
  }

  void _onPanStart(DragStartDetails d) {
    final p = d.localPosition;
    _path.moveTo(p.dx, p.dy);
    _lastPoint = p;
    if (!_hasStrokes) {
      // Only setState here to enable the Accept button and hide the hint
      setState(() => _hasStrokes = true);
    } else {
      _repaintTick.value++;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = d.localPosition;
    if (_lastPoint != null) {
      // Quadratic Bezier through the midpoint gives smooth curves without
      // needing to reprocess previously drawn segments
      final mid = Offset(
        (p.dx + _lastPoint!.dx) / 2,
        (p.dy + _lastPoint!.dy) / 2,
      );
      _path.quadraticBezierTo(_lastPoint!.dx, _lastPoint!.dy, mid.dx, mid.dy);
    }
    _lastPoint = p;
    // No setState — only the painter repaints
    _repaintTick.value++;
  }

  void _onPanEnd(DragEndDetails d) {
    if (_lastPoint != null) {
      _path.lineTo(_lastPoint!.dx, _lastPoint!.dy);
    }
    _lastPoint = null;
    _repaintTick.value++;
  }

  void _clear() {
    setState(() {
      _path = Path();
      _lastPoint = null;
      _hasStrokes = false;
    });
  }

  Future<void> _accept() async {
    setState(() => _isCapturing = true);
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final b64 = base64Encode(byteData.buffer.asUint8List());
        widget.onSign('data:image/png;base64,$b64');
      } else {
        widget.onSign(null);
      }
    } catch (_) {
      widget.onSign(null);
    }
    if (mounted) setState(() => _isCapturing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RepaintBoundary(
            key: _repaintKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Container(
                color: Colors.white,
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _SignaturePainter(
                        path: _path,
                        repaint: _repaintTick,
                      ),
                      child: const SizedBox.expand(),
                    ),
                    if (!_hasStrokes)
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.draw_outlined,
                                size: 52, color: Color(0xFFCCCCCC)),
                            SizedBox(height: 10),
                            Text(
                              'Sign here',
                              style: TextStyle(
                                  color: Color(0xFFCCCCCC), fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _hasStrokes ? _clear : null,
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_hasStrokes && !_isCapturing) ? _accept : null,
                icon: _isCapturing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: const Text('Accept Signature'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final Path path;

  _SignaturePainter({required this.path, required Listenable repaint})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
