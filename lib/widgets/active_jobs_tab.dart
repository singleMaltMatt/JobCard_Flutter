import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../providers/job_provider.dart';
import '../services/timer_notification_service.dart';
import 'workflow_dropdown.dart';
import 'complete_job_dialog.dart';

class ActiveJobsTab extends StatelessWidget {
  const ActiveJobsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<JobProvider>(
      builder: (context, jobProvider, _) {
        // Only show full-screen spinner on the very first load (list still empty)
        if (jobProvider.isLoading && jobProvider.activeJobs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () => jobProvider.loadAll(),
          child: jobProvider.activeJobs.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.work_off_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No active jobs',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            Text('When a job is in progress, it will appear here',
                                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: jobProvider.activeJobs.length,
                  itemBuilder: (context, index) {
                    final job = jobProvider.activeJobs[index];
                    // ValueKey preserves timer state across list rebuilds
                    return _ActiveJobCard(key: ValueKey(job.id), job: job);
                  },
                ),
        );
      },
    );
  }
}

class _ActiveJobCard extends StatefulWidget {
  final dynamic job;

  const _ActiveJobCard({super.key, required this.job});

  @override
  State<_ActiveJobCard> createState() => _ActiveJobCardState();
}

class _ActiveJobCardState extends State<_ActiveJobCard> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  // Fallback when on_site_started_at is not in PocketBase yet
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _startTimerIfOnSite();
  }

  @override
  void didUpdateWidget(_ActiveJobCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.status != widget.job.status) {
      _stopTimer();
      _startTimerIfOnSite();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _startTimerIfOnSite() {
    if (widget.job.status != 'on_site') return;

    // Use the PocketBase timestamp when available; otherwise count from when
    // the card first observed the on_site status (survives list rebuilds via ValueKey)
    _sessionStart ??= DateTime.now();
    final startTime = widget.job.onSiteStartedAt ?? _sessionStart!;
    _elapsed = DateTime.now().difference(startTime);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(startTime));
    });

    // Start the lock-screen / notification timer with whatever start time we have
    TimerNotificationService.startTimer(startTime)
        .catchError((e) => debugPrint('Timer notification error: $e'));
  }

  void _stopTimer() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _sessionStart = null;
      TimerNotificationService.stopTimer()
          .catchError((e) => debugPrint('Stop notification error: $e'));
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.work,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.job.clientName ?? 'Client',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlack,
                        ),
                      ),
                      Text(
                        widget.job.clientAddress ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Calendar date
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: AppTheme.primaryGrey),
                const SizedBox(width: 6),
                Text(
                  widget.job.calendarDate != null
                      ? DateFormat('MMM d, yyyy').format(DateTime.parse(widget.job.calendarDate!))
                      : DateFormat('MMM d, yyyy').format(widget.job.createdAt),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.darkGrey,
                  ),
                ),
              ],
            ),

            // On-site timer
            if (widget.job.status == 'on_site') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.purple),
                    const SizedBox(width: 6),
                    Text(
                      'On site: ${_formatDuration(_elapsed)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Workflow dropdown
            WorkflowDropdown(
              currentStatus: widget.job.status,
              onChanged: (newStatus) {
                if (newStatus == 'completed') {
                  // Don't pre-update status — CompleteJobDialog owns the full
                  // transition. Setting it early means a cancel leaves the job
                  // stuck as completed with no description recorded.
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    isDismissible: false,
                    enableDrag: false,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => CompleteJobDialog(job: widget.job),
                  );
                } else {
                  context.read<JobProvider>().updateJobStatus(
                    widget.job.id,
                    newStatus,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
