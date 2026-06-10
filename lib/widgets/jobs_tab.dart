import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:jobcard_tracker/widgets/complete_job_dialog.dart';
import '../config/theme.dart';
import '../providers/job_provider.dart';
import 'job_card.dart';
import 'workflow_dropdown.dart';

class JobsTab extends StatelessWidget {
  const JobsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<JobProvider>(
      builder: (context, jobProvider, _) {
        if (jobProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final pendingAndActiveJobs = jobProvider.jobs
            .where((job) => job.status != 'completed')
            .toList();

        return RefreshIndicator(
          onRefresh: () => jobProvider.loadAll(),
          child: pendingAndActiveJobs.isEmpty
              ? CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('No jobs yet',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            Text('Tap the + button to create your first job',
                                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: pendingAndActiveJobs.length,
                  itemBuilder: (context, index) {
                    final job = pendingAndActiveJobs[index];
                    return JobCard(
                      job: job,
                      onTap: () => _showJobDetailSheet(context, job),
                    );
                  },
                ),
        );
      },
    );
  }

  void _showJobDetailSheet(BuildContext context, dynamic job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    job.clientName ?? 'Client',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlack,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.clientAddress ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.primaryGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: AppTheme.primaryGrey),
                      const SizedBox(width: 6),
                      Text(
                        job.calendarDate != null
                            ? DateFormat('MMM d, yyyy').format(DateTime.parse(job.calendarDate!))
                            : DateFormat('MMM d, yyyy').format(job.createdAt),
                        style: const TextStyle(fontSize: 13, color: AppTheme.darkGrey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Workflow status section
                  const Text(
                    'Job Status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  WorkflowDropdown(
                    currentStatus: job.status,
                    onChanged: (newStatus) {
                      context.read<JobProvider>().updateJobStatus(
                        job.id,
                        newStatus,
                      );
                      Navigator.of(context).pop();
                      // If moving to completed, show CompleteJobDialog
                      if (newStatus == 'completed') {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) => CompleteJobDialog(job: job),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  // Complete Job button (if not already completed)
                  if (job.status != 'completed')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => CompleteJobDialog(job: job),
                          );
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Complete Job'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
