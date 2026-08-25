import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/sales_order.dart';
import '../models/user.dart';
import '../models/week_job.dart';
import 'pocketbase_client.dart';

class SalesOrderService {
  final PocketBaseClient _client;

  SalesOrderService(this._client);

  String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Sales orders scheduled inside [weekStart, weekStart + 7 days), plus
  /// any unscheduled orders (empty scheduled_date) so they stay visible
  /// until the sales user gives them a date.
  Future<List<SalesOrder>> getOrdersForWeek(DateTime weekStart) async {
    final start = _dateOnly(weekStart);
    final end = _dateOnly(weekStart.add(const Duration(days: 7)));

    try {
      final all = <SalesOrder>[];
      int page = 1;
      const perPage = 200;

      while (true) {
        final response = await _client.get(
          ApiConfig.salesOrdersEndpoint,
          queryParams: {
            'filter':
                '((scheduled_date >= "$start 00:00:00" && scheduled_date < "$end 00:00:00") || scheduled_date = "")',
            'sort': 'scheduled_date,order_number',
            'expand': 'client,supplier,assigned_to',
            'page': '$page',
            'perPage': '$perPage',
          },
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to load sales orders');
        }

        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>;
        all.addAll(items
            .map((item) => SalesOrder.fromJson(item as Map<String, dynamic>)));

        final totalPages = (data['totalPages'] as int? ?? 1);
        if (page >= totalPages) break;
        page++;
      }

      return all;
    } catch (e) {
      throw Exception('Failed to load sales orders: $e');
    }
  }

  /// Internal technicians for the assignment dropdown.
  Future<List<AppUser>> getInternalTechs() async {
    try {
      final response = await _client.get(
        ApiConfig.usersEndpoint,
        queryParams: {
          'filter': '(is_internal = true)',
          'sort': 'name',
          'perPage': '200',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load technicians');
      }

      final data = jsonDecode(response.body);
      final items = data['items'] as List<dynamic>;
      return items
          .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load technicians: $e');
    }
  }

  /// Open sales orders assigned to [userId] that are due: scheduled today
  /// or earlier (so a missed Tuesday collection still shows on Thursday),
  /// and not yet completed. Unscheduled orders are excluded — those are
  /// still being planned in the portal.
  Future<List<SalesOrder>> getMyDueOrders(String userId) async {
    final today = _dateOnly(DateTime.now());

    try {
      final response = await _client.get(
        ApiConfig.salesOrdersEndpoint,
        queryParams: {
          'filter':
              '(assigned_to = "$userId" && status != "completed" && scheduled_date != "" && scheduled_date < "$today 23:59:59")',
          'sort': 'scheduled_date,order_number',
          'expand': 'client,supplier,assigned_to',
          'perPage': '200',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load sales orders');
      }

      final data = jsonDecode(response.body);
      final items = data['items'] as List<dynamic>;
      return items
          .map((item) => SalesOrder.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load sales orders: $e');
    }
  }

  /// Download the SAGE PDF attached to an order, as raw bytes.
  /// Returns null when there is no attachment or the fetch fails.
  Future<List<int>?> fetchAttachedPdf(SalesOrder order) async {
    final name = order.attachedPdfName;
    if (name == null) return null;
    try {
      final response = await http.get(Uri.parse(
          ApiConfig.fileUrl('sales_orders', order.id, name)));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {
      // fall through
    }
    return null;
  }

  /// Mark an order signed and completed. Status is the technician's to set
  /// here — the portal never moves an order out of completed.
  Future<bool> markCompleted({
    required String orderId,
    required String signatureName,
    required DateTime signedAt,
    bool emailSent = false,
  }) async {
    try {
      final response = await _client.patch(
        ApiConfig.salesOrderEndpoint(orderId),
        body: {
          'status': 'completed',
          'signature_name': signatureName,
          'signed_at': signedAt.toUtc().toIso8601String(),
          'email_sent': emailSent,
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Upload the merged (cover + SAGE) PDF to generated_pdf.
  Future<bool> uploadGeneratedPdf({
    required String orderId,
    required List<int> pdfBytes,
    required String fileName,
  }) async {
    try {
      final response = await _client.patchMultipart(
        ApiConfig.salesOrderEndpoint(orderId),
        fileFieldName: 'generated_pdf',
        fileBytes: pdfBytes,
        fileName: fileName,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Upload the raw signature PNG so the note can be regenerated later.
  Future<bool> uploadSignature({
    required String orderId,
    required List<int> pngBytes,
    required String fileName,
  }) async {
    try {
      final response = await _client.patchMultipart(
        ApiConfig.salesOrderEndpoint(orderId),
        fileFieldName: 'signature',
        fileBytes: pngBytes,
        fileName: fileName,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Candidate jobs a delivery can be attached to: same client, not yet
  /// completed, scheduled within +/- [windowDays] of the delivery date.
  /// A completed job can no longer merge in a delivery note, so those are
  /// excluded.
  Future<List<WeekJob>> getAttachableJobs({
    required String clientId,
    required DateTime aroundDate,
    int windowDays = 3,
  }) async {
    final start = _dateOnly(aroundDate.subtract(Duration(days: windowDays)));
    final end = _dateOnly(aroundDate.add(Duration(days: windowDays + 1)));

    try {
      final response = await _client.get(
        ApiConfig.jobsEndpoint,
        queryParams: {
          'filter':
              '(client = "$clientId" && status != "completed" && calendar_date >= "$start" && calendar_date < "$end")',
          'sort': 'calendar_date,job_number',
          'expand': 'client,user',
          'perPage': '200',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load jobs for client');
      }

      final data = jsonDecode(response.body);
      final items = data['items'] as List<dynamic>;
      return items
          .map((item) => WeekJob.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load jobs for client: $e');
    }
  }

  /// Create a sales order. The order_number is set server-side by the
  /// pb_hooks numbering script. Empty-string relation values are how
  /// PocketBase clears/omits a single relation.
  Future<SalesOrder> createOrder({
    required String type,
    required String clientId,
    required String supplierId,
    required String assignedToId,
    required String scheduledDate,
    required String reference,
    required String description,
    required String status,
    String relatedJobId = '',
  }) async {
    try {
      final response = await _client.post(
        ApiConfig.salesOrdersEndpoint,
        body: {
          'type': type,
          'client': clientId,
          'supplier': supplierId,
          'assigned_to': assignedToId,
          'scheduled_date': scheduledDate,
          'reference': reference,
          'description': description,
          'status': status,
          'related_job': relatedJobId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return SalesOrder.fromJson(data);
      } else {
        throw Exception('Failed to create order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to create order: $e');
    }
  }

  /// Update an existing sales order.
  Future<void> updateOrder(
    String orderId, {
    required String type,
    required String clientId,
    required String supplierId,
    required String assignedToId,
    required String scheduledDate,
    required String reference,
    required String description,
    required String status,
    String relatedJobId = '',
  }) async {
    try {
      final response = await _client.patch(
        ApiConfig.salesOrderEndpoint(orderId),
        body: {
          'type': type,
          'client': clientId,
          'supplier': supplierId,
          'assigned_to': assignedToId,
          'scheduled_date': scheduledDate,
          'reference': reference,
          'description': description,
          'status': status,
          'related_job': relatedJobId,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to update order: $e');
    }
  }

  /// Upload the SAGE PDF and attach it to the attached_pdf file field.
  Future<bool> uploadAttachedPdf({
    required String orderId,
    required List<int> pdfBytes,
    required String fileName,
  }) async {
    try {
      final response = await _client.patchMultipart(
        ApiConfig.salesOrderEndpoint(orderId),
        fileFieldName: 'attached_pdf',
        fileBytes: pdfBytes,
        fileName: fileName,
      );
      return response.statusCode == 200;
    } catch (e) {
      throw Exception('Failed to upload PDF: $e');
    }
  }

  /// All jobs with a calendar_date inside the week, read-only, so the
  /// sales user can see which technician is where. calendar_date is a
  /// plain YYYY-MM-DD string, so ISO string comparison is safe.
  Future<List<WeekJob>> getJobsForWeek(DateTime weekStart) async {
    final start = _dateOnly(weekStart);
    final end = _dateOnly(weekStart.add(const Duration(days: 7)));

    try {
      final all = <WeekJob>[];
      int page = 1;
      const perPage = 200;

      while (true) {
        final response = await _client.get(
          ApiConfig.jobsEndpoint,
          queryParams: {
            'filter': '(calendar_date >= "$start" && calendar_date < "$end")',
            'sort': 'calendar_date,job_number',
            'expand': 'client,user',
            'page': '$page',
            'perPage': '$perPage',
          },
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to load jobs');
        }

        final data = jsonDecode(response.body);
        final items = data['items'] as List<dynamic>;
        all.addAll(
            items.map((item) => WeekJob.fromJson(item as Map<String, dynamic>)));

        final totalPages = (data['totalPages'] as int? ?? 1);
        if (page >= totalPages) break;
        page++;
      }

      return all;
    } catch (e) {
      throw Exception('Failed to load jobs: $e');
    }
  }
}
