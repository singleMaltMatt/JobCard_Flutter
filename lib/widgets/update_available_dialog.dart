import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../services/version_service.dart';

/// Prompts the technician that a newer APK is available, with a direct
/// download link. When [info.forceUpdate] is true the dialog cannot be
/// dismissed — the only way forward is to download the update.
class UpdateAvailableDialog extends StatelessWidget {
  final AppUpdateInfo info;

  const UpdateAvailableDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (_) => UpdateAvailableDialog(info: info),
    );
  }

  Future<void> _download() async {
    final uri = Uri.parse(info.apkUrl);
    // externalApplication opens the system browser, which handles the APK
    // download and hands off to the package installer.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block the Android back button on a forced update.
      canPop: !info.forceUpdate,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: AppTheme.primaryBlue),
            SizedBox(width: 12),
            Text('Update Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of JobCard Tracker is available.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Text(
              'Installed: ${info.installedVersion}\nLatest: ${info.latestVersion}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                info.releaseNotes,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
            if (info.forceUpdate) ...[
              const SizedBox(height: 12),
              const Text(
                'This update is required to continue.',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.red,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          if (!info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          FilledButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Download & Install'),
            onPressed: () async {
              await _download();
              if (!info.forceUpdate && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}
