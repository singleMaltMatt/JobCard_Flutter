import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Calls to the sales-order PDF endpoint. Kept separate from
/// PdfPipelineService so the job-card pipeline stays untouched.
class SalesPdfService {
  /// Generate the delivery/collection note. The service renders a branded
  /// cover page and, when [attachedPdfBytes] is supplied, appends the SAGE
  /// document as pages 2+. Returns merged PDF bytes, or null on failure.
  static Future<List<int>?> generateSalesPdf(
    Map<String, dynamic> payload, {
    List<int>? attachedPdfBytes,
  }) async {
    try {
      final body = <String, dynamic>{
        ...payload,
        if (attachedPdfBytes != null)
          'attachedPdf': base64Encode(attachedPdfBytes),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/pdf/generate-sales-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) return response.bodyBytes;
      debugPrint(
          'Sales PDF generation failed (${response.statusCode}): ${response.body}');
    } catch (e) {
      debugPrint('Sales PDF generation error: $e');
    }
    return null;
  }

  /// Send the signed delivery/collection note. Uses the dedicated
  /// /send-sales-email endpoint — the job-card endpoint's template is
  /// worded for completed jobs and would be wrong here.
  static Future<bool> sendSalesEmail(
    Map<String, dynamic> emailPayload,
    List<int> pdfBytes,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/email/send-sales-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          ...emailPayload,
          'pdfBase64': base64Encode(pdfBytes),
        }),
      );
      if (response.statusCode == 200) return true;
      debugPrint(
          'Sales email failed (${response.statusCode}): ${response.body}');
    } catch (e) {
      debugPrint('Sales email error: $e');
    }
    return false;
  }
}
