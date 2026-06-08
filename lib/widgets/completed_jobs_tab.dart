import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/job_provider.dart';
import 'job_card.dart';

class CompletedJobsTab extends StatelessWidget {
  const CompletedJobsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<JobProvider>(
      builder: (context, jobProvider, _) {
        if (jobProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (jobProvider.completedJobs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No completed jobs',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Completed jobs will be listed here',
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
            itemCount: jobProvider.completedJobs.length,
            itemBuilder: (context, index) {
              final job = jobProvider.completedJobs[index];
              return JobCard(job: job, onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _CompletedJobDetail(job: job),
                );
              });
            },
          ),
        );
      },
    );
  }
}

class _CompletedJobDetail extends StatelessWidget {
  final job;
  const _CompletedJobDetail({required this.job});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Text(job.clientName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(job.clientAddress,
                    style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const Divider(height: 32),
                const Text('Work Description',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(job.description ?? 'No description provided.',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.email, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(job.emailSent ? 'Email sent' : 'Email not sent',
                        style: TextStyle(
                            fontSize: 13,
                            color: job.emailSent ? Colors.green : Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}