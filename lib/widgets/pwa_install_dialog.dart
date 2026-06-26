import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import 'pwa_detection_stub.dart'
    if (dart.library.html) 'pwa_detection_web.dart';

class PwaInstallDialog {
  static const _shownKey = 'pwa_prompt_shown';

  static Future<bool> _shouldShow() async {
    if (!kIsWeb) return false;
    if (isRunningAsPwa()) return false;
    if (!isIOSSafari()) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_shownKey) ?? false);
  }

  static Future<void> _markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownKey, true);
  }

  static Future<void> show(BuildContext context) async {
    if (!await _shouldShow()) return;
    await _markShown();
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _PwaDialogWidget(),
    );
  }
}

class _PwaDialogWidget extends StatelessWidget {
  const _PwaDialogWidget();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.install_mobile, color: AppTheme.primaryBlue),
          SizedBox(width: 10),
          Text('Install App'),
        ],
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'For the best experience — especially when on site — install JobCard Tracker on your home screen.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 20),
            _Step(
              icon: Icons.ios_share,
              label: '1. Tap the Share button',
              sub: 'The box-with-arrow icon at the bottom of Safari',
            ),
            SizedBox(height: 12),
            _Step(
              icon: Icons.add_box_outlined,
              label: '2. Tap "Add to Home Screen"',
              sub: 'Scroll down in the share sheet to find it',
            ),
            SizedBox(height: 12),
            _Step(
              icon: Icons.check_circle_outline,
              label: '3. Tap "Add"',
              sub: 'The app will appear on your home screen like a native app',
            ),
            SizedBox(height: 16),
            Text(
              'This keeps the app reliable on site and lets you re-open it instantly when you need to complete a job.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.primaryGrey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Maybe Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got It'),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;

  const _Step({
    required this.icon,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppTheme.primaryBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.primaryGrey)),
            ],
          ),
        ),
      ],
    );
  }
}
