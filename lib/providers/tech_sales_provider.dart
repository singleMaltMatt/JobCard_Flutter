import 'package:flutter/foundation.dart';
import '../models/sales_order.dart';
import '../services/sales_order_service.dart';

/// Technician-side sales orders (deliveries/collections assigned to them).
///
/// Deliberately separate from JobProvider: sales orders never touch job
/// status or the on-site timer, and keeping them in their own provider
/// means a reload here can never trigger a rebuild that disturbs a
/// running job card.
class TechSalesProvider extends ChangeNotifier {
  final SalesOrderService _service;

  TechSalesProvider(this._service);

  List<SalesOrder> _orders = [];
  bool _isLoading = false;
  String? _error;

  List<SalesOrder> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasOrders => _orders.isNotEmpty;

  Future<void> load(String userId) async {
    if (userId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _orders = await _service.getMyDueOrders(userId);
    } catch (e) {
      _error = e.toString();
      _orders = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Drop an order from the local list once it's been signed off, so the
  /// card disappears without waiting for a full reload.
  void removeLocally(String orderId) {
    _orders = _orders.where((o) => o.id != orderId).toList();
    notifyListeners();
  }
}
