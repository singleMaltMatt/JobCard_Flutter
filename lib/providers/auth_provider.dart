import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AppUser? _user;
  bool _isLoading = false;
  String? _error;

  AuthProvider(this._authService);

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  String? get error => _error;
  String? get userId => _user?.id;

  /// Login with username/email and password
  Future<bool> login(String identity, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.login(identity, password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Register a new user
  Future<bool> register(String email, String password, String passwordConfirm) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.register(email, password, passwordConfirm);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout
  void logout() {
    _authService.logout();
    _user = null;
    _error = null;
    notifyListeners();
  }

  /// Try restoring a saved session from storage (call on app start)
  Future<bool> tryRestoreAuth() async {
    final user = await _authService.tryRestoreAuth();
    if (user != null) {
      _user = user;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}