import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import 'pocketbase_client.dart';

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
        return AppUser.fromJson(record);
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

  /// Logout
  void logout() {
    _client.clearAuth();
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