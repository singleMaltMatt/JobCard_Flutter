import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
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
              return JobCard(job: job);
            },
          ),
        );
      },
    );
  }
}