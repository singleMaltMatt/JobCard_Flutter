class Job {
  final String id;
  final String clientId;
  final String clientName;
  final String clientAddress;
  final String clientEmail;
  final String userId;
  final String status;
  final String? description;
  final String? signatureUrl;
  final bool emailSent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? calendarDate;
  final DateTime? onSiteStartedAt;
  final DateTime? onSiteEndedAt;
  final String jobType;
  final String jobNumber;
  final bool isRecurring;
  final String? recurrenceInterval;

  Job({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.clientAddress,
    required this.clientEmail,
    required this.userId,
    required this.status,
    this.description,
    this.signatureUrl,
    this.emailSent = false,
    required this.createdAt,
    required this.updatedAt,
    this.calendarDate,
    this.onSiteStartedAt,
    this.onSiteEndedAt,
    this.jobType = 'site_visit',
    this.jobNumber = '',
    this.isRecurring = false,
    this.recurrenceInterval,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    final expand = json['expand'] as Map<String, dynamic>?;
    String clientName = '';
    String clientAddress = '';

    if (expand != null && expand['client'] != null) {
      final clientData = expand['client'] as Map<String, dynamic>;
      clientName = clientData['name'] ?? '';
      clientAddress = clientData['address'] ?? '';
    }

    return Job(
      id: json['id'] ?? '',
      clientId: json['client'] ?? '',
      clientName: clientName,
      clientAddress: clientAddress,
      clientEmail: expand?['client']?['email'] ?? '',
      userId: json['user'] ?? '',
      status: json['status'] ?? 'pending',
      description: json['description'],
      signatureUrl: json['signature'],
      emailSent: json['email_sent'] ?? false,
      createdAt: DateTime.tryParse(json['created'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated'] ?? '') ?? DateTime.now(),
      calendarDate: json['calendar_date'],
      onSiteStartedAt: DateTime.tryParse(json['on_site_started_at'] ?? ''),
      onSiteEndedAt: DateTime.tryParse(json['on_site_ended_at'] ?? ''),
      jobType: json['job_type'] ?? 'site_visit',
      jobNumber: json['job_number'] ?? '',
      isRecurring: json['is_recurring'] ?? false,
      recurrenceInterval: json['recurrence_interval'],
    );
  }

  /// Display label for job type
  String get jobTypeLabel {
    switch (jobType) {
      case 'maintenance': return 'Maintenance';
      case 'call_out': return 'Call Out';
      case 'site_visit':
      default: return 'Site Visit';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'client': clientId,
      'user': userId,
      'status': status,
      'description': description,
      'email_sent': emailSent,
      'calendar_date': calendarDate,
      'job_type': jobType,
      'job_number': jobNumber,
      'is_recurring': isRecurring,
      'recurrence_interval': recurrenceInterval,
    };
  }

  bool get isActive => status != 'completed' && status != 'pending';
  bool get isCompleted => status == 'completed';

  Job copyWith({
    String? id,
    String? clientId,
    String? clientName,
    String? clientAddress,
    String? clientEmail,
    String? userId,
    String? status,
    String? description,
    String? signatureUrl,
    bool? emailSent,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? calendarDate,
    DateTime? onSiteStartedAt,
    DateTime? onSiteEndedAt,
    String? jobType,
    String? jobNumber,
    bool? isRecurring,
    String? recurrenceInterval,
  }) {
    return Job(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      clientAddress: clientAddress ?? this.clientAddress,
      clientEmail: clientEmail ?? this.clientEmail,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      description: description ?? this.description,
      signatureUrl: signatureUrl ?? this.signatureUrl,
      emailSent: emailSent ?? this.emailSent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      calendarDate: calendarDate ?? this.calendarDate,
      onSiteStartedAt: onSiteStartedAt ?? this.onSiteStartedAt,
      onSiteEndedAt: onSiteEndedAt ?? this.onSiteEndedAt,
      jobType: jobType ?? this.jobType,
      jobNumber: jobNumber ?? this.jobNumber,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
    );
  }
}