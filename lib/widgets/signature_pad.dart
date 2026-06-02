import 'package:flutter/material.dart';

class SignaturePad extends StatefulWidget {
  final void Function(dynamic imageData) onSign;

  const SignaturePad({super.key, required this.onSign});

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  List<List<Offset>> _points = [];
  List<Offset> _currentLine = [];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[400]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: GestureDetector(
              onPanStart: (details) {
                setState(() {
                  _currentLine = [details.localPosition];
                });
              },
              onPanUpdate: (details) {
                setState(() {
                  _currentLine.add(details.localPosition);
                });
              },
              onPanEnd: (details) {
                setState(() {
                  _points.add(List.from(_currentLine));
                  _currentLine = [];
                });
              },
              child: Container(
                width: double.infinity,
                height: 200,
                color: Colors.white,
                child: CustomPaint(
                  painter: _SignaturePainter(
                    points: _points,
                    currentLine: _currentLine,
                  ),
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
              onPressed: () {
                setState(() {
                  _points.clear();
                  _currentLine.clear();
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
            TextButton.icon(
              onPressed: _points.isNotEmpty || _currentLine.isNotEmpty
                  ? () {
                      // In a real app, you'd capture the canvas as an image
                      // For now, we just signal that a signature was made
                      widget.onSign(true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Signature captured!')),
                      );
                    }
                  : null,
              icon: const Icon(Icons.check),
              label: const Text('Accept Signature'),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
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
      ..strokeJoin = StrokeJoin.round;

    for (final line in points) {
      if (line.length < 2) continue;
      for (int i = 0; i < line.length - 1; i++) {
        canvas.drawLine(line[i], line[i + 1], paint);
      }
    }

    if (currentLine.length >= 2) {
      for (int i = 0; i < currentLine.length - 1; i++) {
        canvas.drawLine(currentLine[i], currentLine[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.currentLine != currentLine;
}