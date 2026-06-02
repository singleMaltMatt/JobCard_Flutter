import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';

class JobCardTrackerApp extends StatelessWidget {
  const JobCardTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JobCard Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}