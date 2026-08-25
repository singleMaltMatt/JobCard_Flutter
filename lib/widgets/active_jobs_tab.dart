import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/sales_order.dart';
import '../providers/auth_provider.dart';
import '../providers/job_provider.dart';
import '../providers/tech_sales_provider.dart';
import '../services/timer_notification_service.dart';
import 'workflow_dropdown.dart';
import 'complete_job_dialog.dart';
import 'sales_order_sheet.dart';

class ActiveJobsTab extends StatefulWidget {
  const ActiveJobsTab({super.key});

  @override
  State<ActiveJobsTab> createState() => _ActiveJobsTabState();
}

class _ActiveJobsTabState extends State<ActiveJobsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSalesOrders());
  }

  void _loadSalesOrders() {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id ?? '';
    if (userId.isNotEmpty) {
      context.read<TechSalesProvider>().load(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<JobProvider, TechSalesProvider>(
      builder: (context, jobProvider, salesProvider, _) {
        // Only show full-screen spinner on the very first load (list still empty)
        if (jobProvider.isLoading &&
            jobProvider.activeJobs.isEmpty &&
            !salesProvider.hasOrders) {
          return const Center(child: CircularProgressIndicator());
        }

        final salesOrders = salesProvider.orders;
        final hasNothing =
            jobProvider.activeJobs.isEmpty && salesOrders.isEmpty;

        return RefreshIndicator(
          onRefresh: () async {
            _loadSalesOrders();
            await jobProvider.loadAll();
          },
          child: hasNothing
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
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Deliveries & collections due today or overdue. Signing
                    // one of these never touches job status or the timer.
                    if (salesOrders.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Text(
                          'Deliveries & Collections',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryGrey,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      ...salesOrders.map(
                        (o) => _SalesOrderCard(key: ValueKey(o.id), order: o),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          'Active Jobs',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryGrey,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                    if (jobProvider.activeJobs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Text(
                          'No active jobs right now',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[600]),
                        ),
                      ),
                    ...jobProvider.activeJobs.map(
                      // ValueKey preserves timer state across list rebuilds
                      (job) => _ActiveJobCard(key: ValueKey(job.id), job: job),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Compact card for a delivery/collection assigned to this technician.
class _SalesOrderCard extends StatelessWidget {
  final SalesOrder order;

  const _SalesOrderCard({super.key, required this.order});

  bool get _isOverdue {
    final day = order.scheduledDay;
    if (day == null) return false;
    final now = DateTime.now();
    return day.isBefore(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isOverdue
              ? Colors.orange.withValues(alpha: 0.6)
              : AppTheme.primaryBlue.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => SalesOrderSheet(order: order),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  order.isCollection
                      ? Icons.archive_outlined
                      : Icons.local_shipping_outlined,
                  color: AppTheme.primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.orderNumber,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlack,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          order.typeLabel,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryGrey),
                        ),
                      ],
                    ),
                    Text(
                      order.partyName,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.darkGrey),
                    ),
                    if (_isOverdue && order.scheduledDay != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Overdue \u00b7 was ${DateFormat('d MMM').format(order.scheduledDay!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.primaryGrey),
            ],
          ),
        ),
      ),
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

            const SizedBox(height: 12),

            // Cancel job — sends the job back to the Jobs pool (pending) so it
            // can be picked up again on a later scheduled visit (e.g. arrived
            // on site but no one was there to let the technician in).
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Job'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _confirmCancelJob,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancelJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Job'),
        content: Text(
          'Send this job for ${widget.job.clientName ?? 'this client'} back to '
          'the jobs pool? It will return to pending so it can be picked up on a '
          'later visit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Job'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Job', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Stop any running on-site timer before the card leaves the active list.
    _stopTimer();

    if (!mounted) return;
    await context.read<JobProvider>().updateJobStatus(widget.job.id, 'pending');
  }
}
