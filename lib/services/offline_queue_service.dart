import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingStatusUpdate {
  final String id;
  final String jobId;
  final String status;
  final DateTime capturedAt;

  PendingStatusUpdate({
    required this.id,
    required this.jobId,
    required this.status,
    required this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'status': status,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory PendingStatusUpdate.fromJson(Map<String, dynamic> json) =>
      PendingStatusUpdate(
        id: json['id'] as String,
        jobId: json['jobId'] as String,
        status: json['status'] as String,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );
}

class OfflineQueueService {
  static const _key = 'offline_status_queue';

  Future<void> enqueue(PendingStatusUpdate action) async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final list = _read(prefs);
    // A newer update for the same job supersedes the previous one
    list.removeWhere((a) => a.jobId == action.jobId);
    list.add(action);
    await prefs.setString(
        _key, jsonEncode(list.map((a) => a.toJson()).toList()));
  }

  Future<List<PendingStatusUpdate>> getAll() async {
    if (!kIsWeb) return [];
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs);
  }

  Future<void> remove(String id) async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final list = _read(prefs)..removeWhere((a) => a.id == id);
    await prefs.setString(
        _key, jsonEncode(list.map((a) => a.toJson()).toList()));
  }

  Future<int> pendingCount() async {
    if (!kIsWeb) return 0;
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs).length;
  }

  List<PendingStatusUpdate> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((j) =>
              PendingStatusUpdate.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
