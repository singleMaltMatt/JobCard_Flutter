import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PendingPdfJob {
  final String id;
  final String jobId;
  final String fileName;
  final Map<String, dynamic> pdfPayload;
  final bool sendEmail;
  // Email payload without pdfBase64 — that gets regenerated at retry time.
  final Map<String, dynamic>? emailPayload;

  PendingPdfJob({
    required this.id,
    required this.jobId,
    required this.fileName,
    required this.pdfPayload,
    required this.sendEmail,
    this.emailPayload,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'fileName': fileName,
        'pdfPayload': pdfPayload,
        'sendEmail': sendEmail,
        'emailPayload': emailPayload,
      };

  factory PendingPdfJob.fromJson(Map<String, dynamic> json) => PendingPdfJob(
        id: json['id'] as String,
        jobId: json['jobId'] as String,
        fileName: json['fileName'] as String,
        pdfPayload: Map<String, dynamic>.from(json['pdfPayload'] as Map),
        sendEmail: json['sendEmail'] as bool,
        emailPayload: json['emailPayload'] != null
            ? Map<String, dynamic>.from(json['emailPayload'] as Map)
            : null,
      );
}

class PdfQueueService {
  static const _key = 'pending_pdf_queue';

  Future<void> enqueue(PendingPdfJob job) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _read(prefs);
    // A newer attempt for the same job supersedes the previous one.
    list.removeWhere((j) => j.jobId == job.jobId);
    list.add(job);
    await prefs.setString(
        _key, jsonEncode(list.map((j) => j.toJson()).toList()));
  }

  Future<List<PendingPdfJob>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs);
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _read(prefs)..removeWhere((j) => j.id == id);
    await prefs.setString(
        _key, jsonEncode(list.map((j) => j.toJson()).toList()));
  }

  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs).length;
  }

  List<PendingPdfJob> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((j) => PendingPdfJob.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
