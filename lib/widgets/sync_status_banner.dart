import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/job_provider.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<JobProvider>(
      builder: (context, provider, _) {
        final syncCount = kIsWeb ? provider.pendingSyncCount : 0;
        final pdfCount = provider.pendingPdfCount;

        if (syncCount == 0 && pdfCount == 0) return const SizedBox.shrink();

        // PDF queue takes priority in the message when both are non-zero.
        if (pdfCount > 0) {
          return _Banner(
            icon: Icons.picture_as_pdf_outlined,
            message: pdfCount == 1
                ? '1 job card PDF pending — will retry when connected'
                : '$pdfCount job card PDFs pending — will retry when connected',
          );
        }

        final syncing = provider.isSyncing;
        return _Banner(
          spinner: syncing,
          icon: Icons.sync_problem,
          message: syncing
              ? 'Syncing $syncCount pending update${syncCount == 1 ? '' : 's'}…'
              : '$syncCount update${syncCount == 1 ? '' : 's'} waiting to sync — no connection',
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool spinner;

  const _Banner({
    required this.icon,
    required this.message,
    this.spinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange[700],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (spinner)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
