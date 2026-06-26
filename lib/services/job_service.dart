import 'dart:convert';
import '../config/api_config.dart';
import '../models/job.dart';
import 'pocketbase_client.dart';

class JobService {
  final PocketBaseClient _client;

  JobService(this._client);

  /// Get all jobs for current user
  Future<List<Job>> getJobs() async {
    try {
      final userId = _client.userId;
      if (userId == null) throw Exception('Not authenticated');

      final response = await _client.get(
        ApiConfig.jobsEndpoint,
        queryParams: {
          'filter': '(user="$userId")',
          'sort': '-created',
          'expand': 'client',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>;
        return items.map((item) => Job.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load jobs');
      }
    } catch (e) {
      throw Exception('Failed to load jobs: $e');
    }
  }

  /// Get active jobs (not completed, not pending)
  Future<List<Job>> getActiveJobs() async {
    try {
      final userId = _client.userId;
      if (userId == null) throw Exception('Not authenticated');

      final response = await _client.get(
        ApiConfig.jobsEndpoint,
        queryParams: {
          'filter': '(user="$userId" && status != "completed" && status != "pending")',
          'sort': '-updated',
          'expand': 'client',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>;
        return items.map((item) => Job.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load active jobs');
      }
    } catch (e) {
      throw Exception('Failed to load active jobs: $e');
    }
  }

  /// Get completed jobs
  Future<List<Job>> getCompletedJobs() async {
    try {
      final userId = _client.userId;
      if (userId == null) throw Exception('Not authenticated');

      final response = await _client.get(
        ApiConfig.jobsEndpoint,
        queryParams: {
          'filter': '(user="$userId" && status = "completed")',
          'sort': '-updated',
          'expand': 'client',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>;
        return items.map((item) => Job.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load completed jobs');
      }
    } catch (e) {
      throw Exception('Failed to load completed jobs: $e');
    }
  }

  /// Generate next job number (GS_0001 format)
  Future<String> _generateJobNumber() async {
    try {
      final response = await _client.get(
        ApiConfig.jobsEndpoint,
        queryParams: {'perPage': '1'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final total = (data['totalItems'] as int? ?? 0) + 1;
        return 'GS_${total.toString().padLeft(4, '0')}';
      }
    } catch (_) {}
    return 'GS_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Create a new job
  Future<Job> createJob({
    required String clientId,
    required String jobType,
    String? calendarDate,
    bool isRecurring = false,
    String? recurrenceInterval,
  }) async {
    try {
      final userId = _client.userId;
      if (userId == null) throw Exception('Not authenticated');

      final now = DateTime.now();
      final date = calendarDate ??
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final body = <String, dynamic>{
        'client': clientId,
        'user': userId,
        'status': 'pending',
        'calendar_date': date,
        'job_type': jobType,
        'is_recurring': isRecurring,
      };

      if (isRecurring && recurrenceInterval != null) {
        body['recurrence_interval'] = recurrenceInterval;
      }

      final response = await _client.post(ApiConfig.jobsEndpoint, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Job.fromJson(data);
      } else {
        throw Exception('Failed to create job: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to create job: $e');
    }
  }

  /// Update job status
  Future<void> updateJobStatus(String jobId, String status) async {
    try {
      final body = <String, dynamic>{'status': status};
      if (status == 'on_site') {
        body['on_site_started_at'] = DateTime.now().toUtc().toIso8601String();
      }
      final response = await _client.patch(ApiConfig.jobEndpoint(jobId), body: body);

      if (response.statusCode != 200) {
        throw Exception('Failed to update job status');
      }
    } catch (e) {
      throw Exception('Failed to update job status: $e');
    }
  }

  /// Complete job and optionally spawn next recurring occurrence
  Future<void> completeJob({
    required String jobId,
    required String description,
    required bool emailSent,
    Job? originalJob,
    DateTime? onSiteStartedAt,
  }) async {
    try {
      final body = <String, dynamic>{
        'status': 'completed',
        'description': description,
        'email_sent': emailSent,
        'on_site_ended_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (onSiteStartedAt != null) {
        body['on_site_started_at'] = onSiteStartedAt.toUtc().toIso8601String();
      }
      final response = await _client.patch(
        ApiConfig.jobEndpoint(jobId),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to complete job');
      }

      // Spawn next occurrence if recurring
      if (originalJob != null &&
          originalJob.isRecurring &&
          originalJob.recurrenceInterval != null &&
          originalJob.calendarDate != null) {
        final nextDate = _nextOccurrence(
          originalJob.calendarDate!,
          originalJob.recurrenceInterval!,
        );
        await createJob(
          clientId: originalJob.clientId,
          jobType: originalJob.jobType,
          calendarDate: nextDate,
          isRecurring: true,
          recurrenceInterval: originalJob.recurrenceInterval,
        );
      }
    } catch (e) {
      throw Exception('Failed to complete job: $e');
    }
  }

  /// Upload a generated job card PDF and attach it to the job record's
  /// `job_card_pdf` file field via multipart PATCH.
  Future<bool> uploadJobCardPdf({
    required String jobId,
    required List<int> pdfBytes,
    required String fileName,
  }) async {
    try {
      final response = await _client.patchMultipart(
        ApiConfig.jobEndpoint(jobId),
        fileFieldName: 'job_card_pdf',
        fileBytes: pdfBytes,
        fileName: fileName,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Upload failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to upload job card PDF: $e');
    }
  }

  /// Calculate next occurrence date
  String _nextOccurrence(String currentDate, String interval) {
    final date = DateTime.tryParse(currentDate) ?? DateTime.now();
    DateTime next;
    switch (interval) {
      case 'fortnightly':
        next = date.add(const Duration(days: 14));
        break;
      case 'monthly':
        next = DateTime(date.year, date.month + 1, date.day);
        break;
      case 'weekly':
      default:
        next = date.add(const Duration(days: 7));
    }
    return '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
  }
}