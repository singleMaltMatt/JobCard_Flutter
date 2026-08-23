import 'package:flutter/foundation.dart';
import '../models/sales_order.dart';
import '../models/week_job.dart';
import '../services/sales_order_service.dart';

class SalesProvider extends ChangeNotifier {
  final SalesOrderService _service;

  SalesProvider(this._service) {
    _weekStart = _mondayOf(DateTime.now());
  }

  late DateTime _weekStart;
  List<SalesOrder> _orders = [];
  List<WeekJob> _jobs = [];
  bool _isLoading = false;
  String? _error;

  DateTime get weekStart => _weekStart;
  DateTime get weekEnd => _weekStart.add(const Duration(days: 6));
  List<SalesOrder> get orders => _orders;
  List<WeekJob> get jobs => _jobs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get isCurrentWeek => _weekStart == _mondayOf(DateTime.now());

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  Future<void> loadWeek() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _service.getOrdersForWeek(_weekStart),
        _service.getJobsForWeek(_weekStart),
      ]);
      _orders = results[0] as List<SalesOrder>;
      _jobs = results[1] as List<WeekJob>;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> previousWeek() async {
    _weekStart = _weekStart.subtract(const Duration(days: 7));
    await loadWeek();
  }

  Future<void> nextWeek() async {
    _weekStart = _weekStart.add(const Duration(days: 7));
    await loadWeek();
  }

  Future<void> goToThisWeek() async {
    _weekStart = _mondayOf(DateTime.now());
    await loadWeek();
  }

  /// Orders scheduled on a specific calendar day.
  List<SalesOrder> ordersForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _orders.where((o) => o.scheduledDay == d).toList();
  }

  /// Orders with no scheduled date yet.
  List<SalesOrder> get unscheduledOrders =>
      _orders.where((o) => o.scheduledDay == null).toList();

  /// Jobs on a specific calendar day.
  List<WeekJob> jobsForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _jobs.where((j) => j.calendarDay == d).toList();
  }
}
