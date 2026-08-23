import 'dart:convert';
import '../config/api_config.dart';
import '../models/sales_order.dart';
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
