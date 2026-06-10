import 'package:flutter/material.dart';

class SignaturePad extends StatefulWidget {
  final void Function(dynamic imageData) onSign;
  final bool readOnly;

  const SignaturePad({super.key, required this.onSign, this.readOnly = false});

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _points = [];
  List<Offset> _currentLine = [];
  bool _isLocked = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _isLocked ? Colors.green : Colors.grey[400]!,
              width: _isLocked ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: GestureDetector(
              onPanStart: widget.readOnly || _isLocked ? null : (details) {
                setState(() {
                  _currentLine = [details.localPosition];
                });
              },
              onPanUpdate: widget.readOnly || _isLocked ? null : (details) {
                setState(() {
                  _currentLine.add(details.localPosition);
                });
              },
              onPanEnd: widget.readOnly || _isLocked ? null : (details) {
                setState(() {
                  _points.add(List.from(_currentLine));
                  _currentLine = [];
                });
              },
              child: Container(
                width: double.infinity,
                height: 200,
                color: Colors.white,
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _SignaturePainter(
                        points: _points,
                        currentLine: _currentLine,
                      ),
                    ),
                    if (_isLocked)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Signed', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: (widget.readOnly || _isLocked) ? null : () {
                setState(() {
                  _points.clear();
                  _currentLine.clear();
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
            if (!_isLocked)
              TextButton.icon(
                onPressed: _points.isNotEmpty || _currentLine.isNotEmpty
                    ? () {
                        setState(() => _isLocked = true);
                        widget.onSign(true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Signature accepted and locked!')),
                        );
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: const Text('Accept Signature'),
                style: TextButton.styleFrom(foregroundColor: Colors.green),
              )
            else
              TextButton.icon(
                onPressed: () {
                  setState(() => _isLocked = false);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
              ),
          ],
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> points;
  final List<Offset> currentLine;

  _SignaturePainter({required this.points, required this.currentLine});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Draw completed lines using smooth quadratic bezier curves
    for (final line in points) {
      _drawSmoothLine(canvas, line, paint);
    }

    // Draw current line in progress using smooth curves
    if (currentLine.length >= 2) {
      _drawSmoothLine(canvas, currentLine, paint);
    }
  }

  void _drawSmoothLine(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      // Single dot
      canvas.drawCircle(points[0], paint.strokeWidth / 2, paint);
      return;
    }

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
    } else {
      // Use quadratic bezier curves for smooth lines
      for (int i = 1; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        // Midpoint between current and next point
        final midX = (p0.dx + p1.dx) / 2;
        final midY = (p0.dy + p1.dy) / 2;
        path.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
      }
      // Connect to the last point
      path.lineTo(points.last.dx, points.last.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.currentLine != currentLine;
}