// Stub so app.dart compiles on web without flutter_foreground_task.
import 'package:flutter/widgets.dart';

class WithForegroundTask extends StatelessWidget {
  final Widget child;
  const WithForegroundTask({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
