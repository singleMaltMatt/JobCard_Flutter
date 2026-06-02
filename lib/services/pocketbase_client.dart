import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class PocketBaseClient {
  String? _token;
  String? _userId;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  bool get isAuthenticated => _token != null;
  String? get token => _token;
  String? get userId => _userId;

  void setAuth(String token, String userId) {
    _token = token;
    _userId = userId;
  }

  void clearAuth() {
    _token = null;
    _userId = null;
  }

  String get baseUrl => ApiConfig.baseUrl;

  /// GET request to PocketBase
  Future<http.Response> get(String endpoint, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
    return await http.get(uri, headers: _headers);
  }

  /// POST request to PocketBase
  Future<http.Response> post(String endpoint, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    return await http.post(uri, headers: _headers, body: body != null ? jsonEncode(body) : null);
  }

  /// PATCH request to PocketBase
  Future<http.Response> patch(String endpoint, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    return await http.patch(uri, headers: _headers, body: body != null ? jsonEncode(body) : null);
  }

  /// DELETE request to PocketBase
  Future<http.Response> delete(String endpoint) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    return await http.delete(uri, headers: _headers);
  }
}