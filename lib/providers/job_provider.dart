import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../config/api_config.dart';
import '../models/job.dart';
import '../models/client.dart';
import '../services/job_service.dart';
import '../services/client_service.dart';
import '../services/offline_queue_service.dart';
import '../services/connectivity_service.dart';
import '../services/pdf_queue_service.dart';
import '../services/pdf_pipeline_service.dart';

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

  // PDF/email retry queue — all platforms
  final PdfQueueService _pdfQueue = PdfQueueService();
  int _pendingPdfCount = 0;
  bool _isFlushingPdf = false;

  JobProvider(this._jobService, this._clientService);

  List<Job> get jobs => _jobs;
  List<Job> get activeJobs => _activeJobs;
  List<Job> get completedJobs => _completedJobs;
  List<Client> get clients => _clients;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingSyncCount => _pendingSyncCount;
  bool get isSyncing => _isSyncing;
  int get pendingPdfCount => _pendingPdfCount;

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

      // Load pending PDF count so the banner shows immediately.
      _pendingPdfCount = await _pdfQueue.pendingCount();
      _isLoading = false;
      notifyListeners();

      // Attempt to flush any queued PDF jobs in the background.
      _tryFlushPdfQueue();
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
    required bool emailRequested,
    Job? originalJob,
    DateTime? onSiteStartedAt,
  }) async {
    try {
      await _jobService.completeJob(
        jobId: jobId,
        description: description,
        emailRequested: emailRequested,
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

  // ── PDF/email retry queue (all platforms) ────────────────────────────────

  /// Store a failed PDF+email job so it can be retried on next [loadAll].
  Future<void> queuePdfJob({
    required String jobId,
    required String fileName,
    required Map<String, dynamic> pdfPayload,
    required bool sendEmail,
    Map<String, dynamic>? emailPayload,
  }) async {
    await _pdfQueue.enqueue(PendingPdfJob(
      id: '${jobId}_${DateTime.now().millisecondsSinceEpoch}',
      jobId: jobId,
      fileName: fileName,
      pdfPayload: pdfPayload,
      sendEmail: sendEmail,
      emailPayload: emailPayload,
    ));
    _pendingPdfCount = await _pdfQueue.pendingCount();
    notifyListeners();
  }

  /// Attempt to generate, upload, and email any queued PDF jobs.
  /// Called automatically at the end of [loadAll]. Skips if already running.
  Future<void> _tryFlushPdfQueue() async {
    if (_isFlushingPdf) return;
    _isFlushingPdf = true;

    final pending = await _pdfQueue.getAll();
    for (final job in pending) {
      final pdfBytes = await PdfPipelineService.generatePdf(job.pdfPayload);
      if (pdfBytes == null) break; // still offline — leave queue intact

      final uploaded = await uploadJobCardPdf(
        jobId: job.jobId,
        pdfBytes: pdfBytes,
        fileName: job.fileName,
      );
      if (!uploaded) break; // still offline

      // No email call here — attaching the PDF triggers the server-side
      // job_email hook, which sends if email_requested is set and
      // email_sent is still false. Sending here too would double up.

      await _pdfQueue.remove(job.id);
    }

    _pendingPdfCount = await _pdfQueue.pendingCount();
    _isFlushingPdf = false;
    notifyListeners();
  }

  // ── Signature upload ──────────────────────────────────────────────────────

  Future<bool> uploadSignature({
    required String jobId,
    required List<int> pngBytes,
    required String fileName,
  }) async {
    try {
      return await _jobService.uploadSignature(
        jobId: jobId,
        pngBytes: pngBytes,
        fileName: fileName,
      );
    } catch (e) {
      debugPrint('uploadSignature error: $e');
      return false;
    }
  }

  // ── Resend job card email ─────────────────────────────────────────────────

  /// Re-send the job card email for a completed job.
  /// If the PDF already exists on PocketBase it is downloaded and reused.
  /// Otherwise it is regenerated from the stored job data and signature.
  /// Returns true if the email was dispatched successfully.
  Future<bool> resendJobEmail({
    required Job job,
    required String technicianName,
  }) async {
    // Stored PDF present: send that exact document, untouched.

    // ── Try to reuse the existing PDF ────────────────────────────────────
    // The stored PDF is the document the client actually signed, so reuse it
    // untouched. We only need to know it exists — the hook sends whatever is
    // on the record, so there's no need to download it here.
    if (job.jobCardPdfName?.isNotEmpty == true) {
      return _jobService.requestEmailSend(job.id);
    }

    // ── Regenerate if no PDF was found ───────────────────────────────────
    String? signatureBase64;
    if (job.signatureUrl?.isNotEmpty == true) {
      final path = '/api/files/jobs/${job.id}/${job.signatureUrl}';
      final bytes = await _jobService.downloadFileBytes(path);
      if (bytes != null) {
        signatureBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
      }
    }

    final pdfPayload = _buildPdfPayload(job, technicianName, signatureBase64);
    final pdfBytes = await PdfPipelineService.generatePdf(pdfPayload);
    if (pdfBytes == null) return false;

    final fileName =
        '${job.jobNumber.isNotEmpty ? job.jobNumber : job.id}.pdf';
    final uploaded = await uploadJobCardPdf(
        jobId: job.id, pdfBytes: pdfBytes, fileName: fileName);
    if (!uploaded) return false;

    // Hand off to the server-side hook: flipping email_requested/email_sent
    // triggers job_email, which sends the PDF now on the record.
    return _jobService.requestEmailSend(job.id);
  }

  Map<String, dynamic> _buildPdfPayload(
      Job job, String technicianName, String? signatureBase64) {
    final arrived = job.onSiteStartedAt?.toLocal();
    final departed = job.onSiteEndedAt?.toLocal() ?? DateTime.now().toLocal();
    final timeFmt = DateFormat('HH:mm');
    final dateFmt = DateFormat('d MMM yyyy HH:mm');

    String timeSpent = '';
    if (arrived != null) {
      final diff = departed.difference(arrived);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      timeSpent = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    return {
      'clientName': job.clientName,
      'clientAddress': job.clientAddress,
      'jobNumber': job.jobNumber,
      'jobType': job.jobTypeLabel,
      // Completion date, date only — see note in complete_job_dialog.
      'appointmentDetails': DateFormat('d MMM yyyy').format(departed),
      'arrivedTime': arrived != null ? timeFmt.format(arrived) : '',
      'departedTime': timeFmt.format(departed),
      'timeSpent': timeSpent,
      'description': job.description ?? '',
      'signatureName': job.clientName,
      'signature': signatureBase64 ?? '',
      'technicianName': technicianName,
      'completedDate': dateFmt.format(departed),
      'companyLogo': '${ApiConfig.baseUrl}/static/logo.png',
    };
  }
}