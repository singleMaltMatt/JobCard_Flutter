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

  /// Create a new job
  Future<Job> createJob({
    required String clientId,
    required String calendarDate,
  }) async {
    try {
      final userId = _client.userId;
      if (userId == null) throw Exception('Not authenticated');

      final response = await _client.post(
        ApiConfig.jobsEndpoint,
        body: {
          'client': clientId,
          'user': userId,
          'status': 'pending',
          'calendar_date': calendarDate,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Job.fromJson(data);
      } else {
        throw Exception('Failed to create job');
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
      final response = await _client.patch(
        ApiConfig.jobEndpoint(jobId),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update job status');
      }
    } catch (e) {
      throw Exception('Failed to update job status: $e');
    }
  }

  /// Update job with description and signature
  Future<void> completeJob({
    required String jobId,
    required String description,
    required bool emailSent,
  }) async {
    try {
      final response = await _client.patch(
        ApiConfig.jobEndpoint(jobId),
        body: {
          'status': 'completed',
          'description': description,
          'email_sent': emailSent,
          'on_site_ended_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to complete job');
      }
    } catch (e) {
      throw Exception('Failed to complete job: $e');
    }
  }
}