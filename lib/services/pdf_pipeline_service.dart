import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class PdfPipelineService {
  /// Call /pdf/generate-pdf with [pdfPayload]. Returns raw PDF bytes on
  /// success, null on any network or server failure.
  static Future<List<int>?> generatePdf(Map<String, dynamic> pdfPayload) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/pdf/generate-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(pdfPayload),
      );
      if (response.statusCode == 200) return response.bodyBytes;
      debugPrint('PDF generation failed (${response.statusCode}): ${response.body}');
    } catch (e) {
      debugPrint('PDF generation error: $e');
    }
    return null;
  }

  /// Call /email/send-email. [emailPayload] must contain all fields except
  /// pdfBase64; [pdfBytes] are base64-encoded internally before sending.
  /// Returns true on success.
  static Future<bool> sendEmail(
      Map<String, dynamic> emailPayload, List<int> pdfBytes) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/email/send-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          ...emailPayload,
          'pdfBase64': base64Encode(pdfBytes),
        }),
      );
      if (response.statusCode == 200) return true;
      debugPrint('Email failed (${response.statusCode}): ${response.body}');
    } catch (e) {
      debugPrint('Email error: $e');
    }
    return false;
  }
}
