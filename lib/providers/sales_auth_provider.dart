import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../services/pocketbase_client.dart';

// Deliberately distinct keys from the main app's pb_token/pb_user_id:
// /app/ and /sales/ share the same web origin, so SharedPreferences
// (localStorage) is shared between them. Reusing the same keys would
// let a login in one portal clobber the other's session.
const _kSalesTokenKey = 'sales_pb_token';
const _kSalesUserIdKey = 'sales_pb_user_id';
const _kSalesRecordKey = 'sales_pb_record';
const _kSalesSuperKey = 'sales_pb_is_super';

class SalesAuthProvider extends ChangeNotifier {
  final PocketBaseClient _client;

  SalesAuthProvider(this._client);

  Map<String, dynamic>? _record;
  bool _isSuperuser = false;
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _client.isAuthenticated;
  bool get isSuperuser => _isSuperuser;

  String get displayName {
    final name = _record?['name'] as String?;
    if (name != null && name.isNotEmpty) return name;
    return _record?['email'] as String? ?? 'Sales';
  }

  bool get _hasSalesAccess =>
      _isSuperuser ||
      _record?['is_sales'] == true ||
      _record?['is_head_office'] == true;

  Future<bool> login(String identity, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Normal users collection
      var response = await _client.post(
        ApiConfig.loginEndpoint,
        body: {'identity': identity, 'password': password},
      );
      var isSuper = false;

      // 2. Fall back to the PocketBase superusers collection so the
      // admin account works here too (superusers are a separate auth
      // collection and never appear in `users`).
      if (response.statusCode != 200) {
        response = await _client.post(
          ApiConfig.superuserLoginEndpoint,
          body: {'identity': identity, 'password': password},
        );
        isSuper = response.statusCode == 200;
      }

      if (response.statusCode != 200) {
        _error = 'Login failed. Please check your credentials.';
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _record = data['record'] as Map<String, dynamic>;
      _isSuperuser = isSuper;

      if (!_hasSalesAccess) {
        _record = null;
        _isSuperuser = false;
        _error = 'This account does not have access to the sales portal.';
        return false;
      }

      _client.setAuth(data['token'] as String, _record!['id'] as String);
      await _persist(data['token'] as String);
      return true;
    } catch (e) {
      _error = 'Connection error. Please try again.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _persist(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSalesTokenKey, token);
    await prefs.setString(_kSalesUserIdKey, _record!['id'] as String);
    await prefs.setString(_kSalesRecordKey, jsonEncode(_record));
    await prefs.setBool(_kSalesSuperKey, _isSuperuser);
  }

  /// Restore a previously saved session. Returns true if successful.
  Future<bool> tryRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kSalesTokenKey);
    final userId = prefs.getString(_kSalesUserIdKey);
    final recordJson = prefs.getString(_kSalesRecordKey);
    if (token == null || userId == null || recordJson == null) return false;
    try {
      _record = jsonDecode(recordJson) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    _isSuperuser = prefs.getBool(_kSalesSuperKey) ?? false;
    if (!_hasSalesAccess) return false;
    _client.setAuth(token, userId);
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _client.clearAuth();
    _record = null;
    _isSuperuser = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSalesTokenKey);
    await prefs.remove(_kSalesUserIdKey);
    await prefs.remove(_kSalesRecordKey);
    await prefs.remove(_kSalesSuperKey);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
