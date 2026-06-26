import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';

// flutter_foreground_task is a native-only plugin — guard it from web.
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    if (dart.library.html) 'app_foreground_stub.dart';

class JobCardTrackerApp extends StatelessWidget {
  const JobCardTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'JobCard Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
    if (kIsWeb) return app;
    return WithForegroundTask(child: app);
  }
}