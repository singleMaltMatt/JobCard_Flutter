import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/job_provider.dart';
import '../services/version_service.dart';
import '../widgets/update_available_dialog.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    final authProvider = context.read<AuthProvider>();

    // Restore saved session and show splash for at least 2 seconds in parallel
    await Future.wait([
      authProvider.tryRestoreAuth(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      // Load data and go to dashboard
      final jobProvider = context.read<JobProvider>();
      await jobProvider.loadAll();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      // Go to login
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }

    // After landing on the first real screen, prompt for an APK update if the
    // server reports a newer version (Android only; no-op elsewhere).
    _promptUpdateIfAvailable();
  }

  Future<void> _promptUpdateIfAvailable() async {
    final update = await VersionService.checkForUpdate();
    if (update == null) return;
    // Use the root navigator's context — this SplashScreen has already been
    // replaced, so the dialog belongs to the Dashboard/Login screen.
    final navState = navigatorKey.currentState;
    if (navState == null || !navState.mounted) return;
    await UpdateAvailableDialog.show(navState.context, update);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Placeholder logo
            Image.asset(
              'assets/images/logo.png',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
    ),
            const SizedBox(height: 24),
            const Text(
              'JobCard Tracker',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage your jobs efficiently',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}