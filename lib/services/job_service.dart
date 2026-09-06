import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  /// Update job status.
  ///
  /// [onSiteStartedAt] lets the offline queue replay an accurately-timed
  /// on_site timestamp instead of using DateTime.now() at flush time.
  ///
  /// [currentJob], when supplied, enables two guards that exist because a
  /// tech re-selecting a status on a finished job has twice caused real
  /// damage: once corrupting a duration (GS Richards Bay) and once reverting
  /// GS_0238 to `pending`, which dropped it off the tech's Completed list and
  /// blocked its email at the hook's first guard.
  ///   1. A completed job cannot move backwards.
  ///   2. `on_site_started_at` is never overwritten once set.
  Future<void> updateJobStatus(String jobId, String status,
      {DateTime? onSiteStartedAt, Job? currentJob}) async {
    try {
      if (currentJob != null &&
          currentJob.status == 'completed' &&
          status != 'completed') {
        throw Exception(
            'This job is already completed and cannot be moved back to '
            '"${status.replaceAll('_', ' ')}".');
      }

      final body = <String, dynamic>{'status': status};

      if (status == 'on_site') {
        // Only stamp the arrival time the first time. Re-selecting "on site"
        // on a job that already has one would silently reset the duration.
        final alreadyStarted = currentJob?.onSiteStartedAt != null;
        if (!alreadyStarted) {
          body['on_site_started_at'] =
              (onSiteStartedAt ?? DateTime.now()).toUtc().toIso8601String();
        }
      }

      final response = await _client.patch(ApiConfig.jobEndpoint(jobId), body: body);

      if (response.statusCode != 200) {
        throw Exception('Failed to update job status');
      }
    } catch (e) {
      throw Exception('Failed to update job status: $e');
    }
  }

  /// Complete job and optionally spawn next recurring occurrence.
  ///
  /// [emailRequested] records the technician's intent. It does NOT mean the
  /// email went out — `email_sent` is written by the server-side job_email
  /// hook only after the mailer confirms. Previously `email_sent` was set
  /// here from the checkbox, so it was true even when nothing was sent.
  Future<void> completeJob({
    required String jobId,
    required String description,
    required bool emailRequested,
    Job? originalJob,
    DateTime? onSiteStartedAt,
  }) async {
    try {
      final body = <String, dynamic>{
        'status': 'completed',
        'description': description,
        'email_requested': emailRequested,
        'email_sent': false,
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

  /// Upload the captured signature PNG and attach it to the `signature` field.
  Future<bool> uploadSignature({
    required String jobId,
    required List<int> pngBytes,
    required String fileName,
  }) async {
    try {
      final response = await _client.patchMultipart(
        ApiConfig.jobEndpoint(jobId),
        fileFieldName: 'signature',
        fileBytes: pngBytes,
        fileName: fileName,
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('uploadSignature error: $e');
      return false;
    }
  }

  /// Download raw bytes from a PocketBase file URL path (e.g. /api/files/…).
  Future<List<int>?> downloadFileBytes(String filePath) async {
    try {
      final response = await _client.get(filePath);
      if (response.statusCode == 200) return response.bodyBytes;
      debugPrint('downloadFileBytes failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('downloadFileBytes error: $e');
    }
    return null;
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

  /// Flag a job for (re)sending. The server-side job_email hook watches for
  /// email_requested && !email_sent on a completed job with a PDF attached,
  /// so flipping these is all that's needed to trigger a send.
  Future<bool> requestEmailSend(String jobId) async {
    try {
      final response = await _client.patch(
        ApiConfig.jobEndpoint(jobId),
        body: {'email_requested': true, 'email_sent': false},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}