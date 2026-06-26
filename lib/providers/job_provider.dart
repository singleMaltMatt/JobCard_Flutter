import 'package:flutter/foundation.dart';
import '../models/job.dart';
import '../models/client.dart';
import '../services/job_service.dart';
import '../services/client_service.dart';
import '../services/offline_queue_service.dart';
import '../services/connectivity_service.dart';

class JobProvider extends ChangeNotifier {
  final JobService _jobService;
  final ClientService _clientService;

  List<Job> _jobs = [];
  List<Job> _activeJobs = [];
  List<Job> _completedJobs = [];
  List<Client> _clients = [];
  bool _isLoading = false;
  String? _error;

  // Web-only offline sync state
  final OfflineQueueService _offlineQueue = OfflineQueueService();
  int _pendingSyncCount = 0;
  bool _isSyncing = false;

  JobProvider(this._jobService, this._clientService);

  List<Job> get jobs => _jobs;
  List<Job> get activeJobs => _activeJobs;
  List<Job> get completedJobs => _completedJobs;
  List<Client> get clients => _clients;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingSyncCount => _pendingSyncCount;
  bool get isSyncing => _isSyncing;

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
    required String jobType,
    String? calendarDate,
    bool isRecurring = false,
    String? recurrenceInterval,
  }) async {
    try {
      await _jobService.createJob(
        clientId: clientId,
        jobType: jobType,
        calendarDate: calendarDate,
        isRecurring: isRecurring,
        recurrenceInterval: recurrenceInterval,
      );
      await loadAll();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update job status.
  /// On web, failed/offline requests are queued in localStorage and replayed
  /// automatically when connectivity is restored. Android path is unchanged.
  Future<bool> updateJobStatus(String jobId, String status) async {
    if (kIsWeb && !webIsOnline) {
      await _queueStatusUpdate(jobId, status);
      return true;
    }
    try {
      await _jobService.updateJobStatus(jobId, status);
      await loadAll();
      return true;
    } catch (e) {
      if (kIsWeb) {
        await _queueStatusUpdate(jobId, status);
        return true;
      }
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> _queueStatusUpdate(String jobId, String status) async {
    await _offlineQueue.enqueue(PendingStatusUpdate(
      id: '${jobId}_${DateTime.now().millisecondsSinceEpoch}',
      jobId: jobId,
      status: status,
      capturedAt: DateTime.now(),
    ));
    _applyStatusLocally(jobId, status);
    _pendingSyncCount = await _offlineQueue.pendingCount();
    notifyListeners();
  }

  void _applyStatusLocally(String jobId, String status) {
    _jobs = _jobs
        .map((j) => j.id == jobId ? j.copyWith(status: status) : j)
        .toList();
    _activeJobs = _activeJobs
        .map((j) => j.id == jobId ? j.copyWith(status: status) : j)
        .toList();
  }

  /// Complete a job with description and email
  Future<bool> completeJob({
    required String jobId,
    required String description,
    required bool emailSent,
    Job? originalJob,
    DateTime? onSiteStartedAt,
  }) async {
    try {
      await _jobService.completeJob(
        jobId: jobId,
        description: description,
        emailSent: emailSent,
        originalJob: originalJob,
        onSiteStartedAt: onSiteStartedAt,
      );
      await loadAll();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Upload the generated job card PDF and attach it to the job record.
  /// Does NOT trigger loadAll() / notifyListeners() since this commonly
  /// runs as a background task after the dialog has already closed.
  Future<bool> uploadJobCardPdf({
    required String jobId,
    required List<int> pdfBytes,
    required String fileName,
  }) async {
    try {
      return await _jobService.uploadJobCardPdf(
        jobId: jobId,
        pdfBytes: pdfBytes,
        fileName: fileName,
      );
    } catch (e) {
      debugPrint('uploadJobCardPdf error: $e');
      return false;
    }
  }

  /// Reload clients only
  Future<void> loadClients() async {
    try {
      _clients = await _clientService.getClients();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Create a new client, returns the created Client or null on failure
  Future<Client?> createClient({
    required String name,
    required String email,
    required String phone,
    required String address,
  }) async {
    try {
      final client = await _clientService.createClient(
        name: name,
        email: email,
        phone: phone,
        address: address,
      );
      _clients = [..._clients, client];
      notifyListeners();
      return client;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Web-only offline sync ──────────────────────────────────────────────

  /// Replay queued status updates against the server.
  /// Stops at the first failure so the queue preserves order.
  Future<void> flushOfflineQueue() async {
    if (!kIsWeb || _isSyncing) return;
    final pending = await _offlineQueue.getAll();
    if (pending.isEmpty) return;

    _isSyncing = true;
    notifyListeners();

    for (final action in pending) {
      try {
        await _jobService.updateJobStatus(
          action.jobId,
          action.status,
          onSiteStartedAt:
              action.status == 'on_site' ? action.capturedAt : null,
        );
        await _offlineQueue.remove(action.id);
      } catch (_) {
        break; // still offline — leave remaining items in queue
      }
    }

    _pendingSyncCount = await _offlineQueue.pendingCount();
    _isSyncing = false;
    await loadAll();
  }

  /// Call once after login on web. Loads the pending count, wires up the
  /// online/offline listener, and flushes any queued actions immediately
  /// if connectivity is available.
  Future<void> initializeWebSync() async {
    if (!kIsWeb) return;
    _pendingSyncCount = await _offlineQueue.pendingCount();
    notifyListeners();

    listenToConnectivity((online) {
      if (online) flushOfflineQueue();
    });

    if (webIsOnline) await flushOfflineQueue();
  }
}