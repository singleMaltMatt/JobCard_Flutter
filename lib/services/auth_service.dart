import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import 'pocketbase_client.dart';

const _kUserKey = 'pb_user';

class AuthService {
  final PocketBaseClient _client;

  AuthService(this._client);

  /// Login with username/email and password
  Future<AppUser> login(String identity, String password) async {
    try {
      final response = await _client.post(
        ApiConfig.loginEndpoint,
        body: {
          'identity': identity,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String;
        final record = data['record'] as Map<String, dynamic>;
        final userId = record['id'] as String;

        _client.setAuth(token, userId);
        await _client.saveAuth();
        final user = AppUser.fromJson(record);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kUserKey, jsonEncode(record));
        return user;
      } else {
        final error = jsonDecode(response.body);
        throw AuthException(
          error['message'] ?? 'Login failed. Please check your credentials.',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Connection error. Please check your server URL.');
    }
  }

  /// Register a new user
  Future<AppUser> register(String email, String password, String passwordConfirm) async {
    try {
      final response = await _client.post(
        ApiConfig.registerEndpoint,
        body: {
          'email': email,
          'password': password,
          'passwordConfirm': passwordConfirm,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AppUser.fromJson(data);
      } else {
        final error = jsonDecode(response.body);
        throw AuthException(
          error['message'] ?? 'Registration failed.',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Connection error. Please check your server URL.');
    }
  }

  /// Restore a previously saved session. Returns the user if successful.
  Future<AppUser?> tryRestoreAuth() async {
    final restored = await _client.restoreAuth();
    if (!restored) return null;
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_kUserKey);
    if (userJson == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Logout
  void logout() {
    _client.clearSavedAuth();
    SharedPreferences.getInstance()
        .then((prefs) => prefs.remove(_kUserKey));
  }

  /// Check if user is authenticated
  bool get isAuthenticated => _client.isAuthenticated;

  /// Get current user ID
  String? get userId => _client.userId;
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}