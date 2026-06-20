import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../models/job.dart';

class JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback? onTap;

  const JobCard({super.key, required this.job, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFutureRecurring = _isFutureRecurring();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Date column
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isFutureRecurring
                      ? AppTheme.primaryBlue
                      : AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _getDay(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isFutureRecurring
                              ? AppTheme.primaryGrey
                              : AppTheme.primaryBlue,
                        ),
                      ),
                      Text(
                        _getMonth(),
                        style: TextStyle(
                          fontSize: 10,
                          color: isFutureRecurring
                              ? AppTheme.primaryGrey
                              : AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Job details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.clientName.isNotEmpty ? job.clientName : 'No client',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlack,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: AppTheme.primaryGrey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            job.clientAddress.isNotEmpty ? job.clientAddress : 'No address',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.primaryGrey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor().withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppConstants.statusLabel(job.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _statusColor(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.primaryGrey),
            ],
          ),
        ),
      ),
    );
  }

  bool _isFutureRecurring() {
    if (!job.isRecurring || job.calendarDate == null) return false;
    final date = DateTime.tryParse(job.calendarDate!);
    if (date == null) return false;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final jobDate = DateTime(date.year, date.month, date.day);
    return jobDate.isAfter(todayDate);
  }

  String _getDay() {
    if (job.calendarDate != null) {
      final date = DateTime.tryParse(job.calendarDate!);
      if (date != null) return DateFormat('d').format(date);
    }
    return DateFormat('d').format(job.createdAt);
  }

  String _getMonth() {
    if (job.calendarDate != null) {
      final date = DateTime.tryParse(job.calendarDate!);
      if (date != null) return DateFormat('MMM').format(date);
    }
    return DateFormat('MMM').format(job.createdAt);
  }

  Color _statusColor() {
    switch (job.status) {
      case 'completed':
        return Colors.green;
      case 'accepted':
        return Colors.blue;
      case 'on_route':
        return Colors.orange;
      case 'on_site':
        return Colors.purple;
      case 'pending':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}