import 'package:flutter/material.dart';
import '../models/job.dart';
import '../models/client.dart';
import '../services/job_service.dart';
import '../services/client_service.dart';

class JobProvider extends ChangeNotifier {
  final JobService _jobService;
  final ClientService _clientService;

  List<Job> _jobs = [];
  List<Job> _activeJobs = [];
  List<Job> _completedJobs = [];
  List<Client> _clients = [];
  bool _isLoading = false;
  String? _error;
  int _selectedTabIndex = 0;

  JobProvider(this._jobService, this._clientService);

  List<Job> get jobs => _jobs;
  List<Job> get activeJobs => _activeJobs;
  List<Job> get completedJobs => _completedJobs;
  List<Client> get clients => _clients;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get selectedTabIndex => _selectedTabIndex;

  set selectedTabIndex(int index) {
    _selectedTabIndex = index;
    notifyListeners();
  }

  /// Load all job data
  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _jobService.getJobs(),
        _jobService.getActiveJobs(),
        _jobService.getCompletedJobs(),
        _clientService.getClients(),
      ]);

      _jobs = results[0] as List<Job>;
      _activeJobs = results[1] as List<Job>;
      _completedJobs = results[2] as List<Job>;
      _clients = results[3] as List<Client>;

      // Auto-select tab: if active jobs exist, go to Active tab
      if (_activeJobs.isNotEmpty && _selectedTabIndex == 0) {
        _selectedTabIndex = 1;
      } else if (_activeJobs.isEmpty && _selectedTabIndex == 1) {
        _selectedTabIndex = 0;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new job
  Future<bool> createJob({
    required String clientId,
    required String calendarDate,
  }) async {
    try {
      await _jobService.createJob(clientId: clientId, calendarDate: calendarDate);
      await loadAll();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update job status
  Future<bool> updateJobStatus(String jobId, String status) async {
    try {
      await _jobService.updateJobStatus(jobId, status);
      await loadAll();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Complete a job with description and email
  Future<bool> completeJob({
    required String jobId,
    required String description,
    required bool emailSent,
  }) async {
    try {
      await _jobService.completeJob(
        jobId: jobId,
        description: description,
        emailSent: emailSent,
      );
      await loadAll();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}