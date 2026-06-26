import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/job_provider.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return Consumer<JobProvider>(
      builder: (context, provider, _) {
        final count = provider.pendingSyncCount;
        if (count == 0) return const SizedBox.shrink();
        final syncing = provider.isSyncing;
        return Material(
          color: Colors.orange[700],
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (syncing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.sync_problem,
                      color: Colors.white, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    syncing
                        ? 'Syncing $count pending update${count == 1 ? '' : 's'}…'
                        : '$count update${count == 1 ? '' : 's'} waiting to sync — no connection',
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
      },
    );
  }
}
