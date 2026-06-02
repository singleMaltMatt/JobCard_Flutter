import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/job_provider.dart';
import 'workflow_dropdown.dart';
import 'complete_job_dialog.dart';

class ActiveJobsTab extends StatelessWidget {
  const ActiveJobsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<JobProvider>(
      builder: (context, jobProvider, _) {
        if (jobProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (jobProvider.activeJobs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.work_off_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No active jobs',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'When a job is in progress, it will appear here',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => jobProvider.loadAll(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: jobProvider.activeJobs.length,
            itemBuilder: (context, index) {
              final job = jobProvider.activeJobs[index];
              return _ActiveJobCard(job: job);
            },
          ),
        );
      },
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  final dynamic job;

  const _ActiveJobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.primaryBlue.withOpacity(0.3),
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
                    color: Colors.green.withOpacity(0.1),
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
                        job.clientName ?? 'Client',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlack,
                        ),
                      ),
                      Text(
                        job.clientAddress ?? '',
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
                  job.calendarDate != null
                      ? DateFormat('MMM d, yyyy').format(DateTime.parse(job.calendarDate!))
                      : DateFormat('MMM d, yyyy').format(job.createdAt),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.darkGrey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Workflow dropdown
            WorkflowDropdown(
              currentStatus: job.status,
              onChanged: (newStatus) {
                context.read<JobProvider>().updateJobStatus(
                      job.id,
                      newStatus,
                    );

                // If moving to completed, show the dialog
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
          ],
        ),
      ),
    );
  }
}