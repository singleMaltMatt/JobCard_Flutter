/// Read-only view of a job for the sales portal's week view.
///
/// Deliberately separate from the app's Job model: the portal needs the
/// technician's name (expand.user), which Job doesn't parse, and touching
/// the production model for a read-only screen isn't worth the risk.
class WeekJob {
  final String id;
  final String jobNumber;
  final String jobType;
  final String status;
  final String clientName;
  final String techName;

  /// Raw calendar_date string (YYYY-MM-DD) from the job record.
  final String? calendarDate;

  WeekJob({
    required this.id,
    required this.jobNumber,
    required this.jobType,
    required this.status,
    required this.clientName,
    required this.techName,
    this.calendarDate,
  });

  factory WeekJob.fromJson(Map<String, dynamic> json) {
    final expand = json['expand'] as Map<String, dynamic>?;

    final clientData = expand?['client'] as Map<String, dynamic>?;
    final userData = expand?['user'] as Map<String, dynamic>?;

    String techName = '';
    if (userData != null) {
      final name = userData['name'] as String?;
      techName = (name != null && name.isNotEmpty)
          ? name
          : (userData['email'] ?? '');
    }

    return WeekJob(
      id: json['id'] ?? '',
      jobNumber: json['job_number'] ?? '',
      jobType: json['job_type'] ?? 'site_visit',
      status: json['status'] ?? 'pending',
      clientName: clientData?['name'] ?? '',
      techName: techName,
      calendarDate: json['calendar_date'],
    );
  }

  String get jobTypeLabel {
    switch (jobType) {
      case 'maintenance':
        return 'Maintenance';
      case 'call_out':
        return 'Call Out';
      case 'cctv_access_control':
        return 'CCTV / Access Control';
      case 'site_visit':
      default:
        return 'Site Visit';
    }
  }

  /// Calendar day, or null when the job has no calendar_date.
  DateTime? get calendarDay {
    if (calendarDate == null || calendarDate!.isEmpty) return null;
    final parsed = DateTime.tryParse(calendarDate!);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}
