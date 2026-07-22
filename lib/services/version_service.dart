import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/api_config.dart';

/// Details of an available APK update, parsed from the server's version.json.
class AppUpdateInfo {
  final String latestVersion;
  final String installedVersion;
  final String apkUrl;
  final String releaseNotes;
  final bool forceUpdate;

  AppUpdateInfo({
    required this.latestVersion,
    required this.installedVersion,
    required this.apkUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });
}

/// Checks the server for a newer Android build and reports whether the
/// installed app is out of date. This is an Android-only concern — the web
/// app updates itself, and there is no APK on iOS — so the check is a no-op
/// on every other platform.
class VersionService {
  /// Endpoint holding the latest version metadata. Served with no-cache
  /// headers by nginx so this always reflects the newest release.
  static String get versionUrl => '${ApiConfig.baseUrl}/version.json';

  /// Returns update details if a newer APK is available, otherwise null.
  /// Never throws — any network/parse failure resolves to null so a launch
  /// is never blocked by the update check.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    // Only Android installs can side-load an APK update.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final installed = info.version; // e.g. "1.2.0"

      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = (data['latest_version'] as String?)?.trim();
      final apkUrl = (data['apk_url'] as String?)?.trim();
      if (latest == null || latest.isEmpty || apkUrl == null || apkUrl.isEmpty) {
        return null;
      }

      if (_compareVersions(latest, installed) <= 0) return null; // up to date

      return AppUpdateInfo(
        latestVersion: latest,
        installedVersion: installed,
        apkUrl: apkUrl,
        releaseNotes: (data['release_notes'] as String?)?.trim() ?? '',
        forceUpdate: data['force_update'] == true,
      );
    } catch (e) {
      debugPrint('VersionService.checkForUpdate failed: $e');
      return null;
    }
  }

  /// Compares two dotted version strings (e.g. "1.2.0" vs "1.10.1").
  /// Returns >0 if [a] is newer than [b], 0 if equal, <0 if older.
  /// Non-numeric or missing segments are treated as 0.
  static int _compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final na = i < pa.length ? pa[i] : 0;
      final nb = i < pb.length ? pb[i] : 0;
      if (na != nb) return na - nb;
    }
    return 0;
  }

  static List<int> _parse(String v) {
    // Drop any build metadata after '+' (e.g. "1.2.0+2" -> "1.2.0").
    final core = v.split('+').first.trim();
    return core.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  }
}
