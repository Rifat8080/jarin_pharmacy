import 'package:flutter/foundation.dart';

import '../security/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({AuthService? authService})
    : _authService = authService ?? AuthService();

  final AuthService _authService;

  bool _initialized = false;
  bool _isAuthenticated = false;
  bool _hasAccount = false;
  bool _rememberMe = false;
  bool _isBusy = false;
  int _remainingAttempts = 5;
  DateTime? _lockedUntil;
  String? _registeredEmail;
  String? _errorMessage;

  bool get initialized => _initialized;
  bool get isAuthenticated => _isAuthenticated;
  bool get hasAccount => _hasAccount;
  bool get rememberMe => _rememberMe;
  bool get isBusy => _isBusy;
  int get remainingAttempts => _remainingAttempts;
  DateTime? get lockedUntil => _lockedUntil;
  String? get registeredEmail => _registeredEmail;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final hasAccount = await _authService.hasUser();
    final remembered = await _authService.isRememberedSession();
    final email = await _authService.getRegisteredEmail();
    final lockInfo = await _authService.getLockInfo();

    _hasAccount = hasAccount;
    _registeredEmail = email;
    _rememberMe = remembered;
    _lockedUntil = lockInfo.lockedUntil;
    _isAuthenticated = hasAccount && remembered;
    _errorMessage = null;
    _initialized = true;
    notifyListeners();
  }

  void setRememberMe(bool value) {
    _rememberMe = value;
    notifyListeners();
  }

  /// Re-runs initialization from scratch — call after restoring a backup so
  /// the gate picks up the newly-restored user account.
  Future<void> forceReinitialize() async {
    _initialized = false;
    _isAuthenticated = false;
    _hasAccount = false;
    _registeredEmail = null;
    _errorMessage = null;
    await initialize();
  }

  Future<bool> signIn({required String email, required String password}) async {
    if (!_hasAccount) {
      _errorMessage = 'No account found. Please create an account first.';
      notifyListeners();
      return false;
    }

    final normalizedEmail = email.trim().toLowerCase();

    if (!_isValidEmail(normalizedEmail)) {
      _errorMessage = 'Enter a valid email address.';
      notifyListeners();
      return false;
    }

    if (password.isEmpty) {
      _errorMessage = 'Password cannot be empty.';
      notifyListeners();
      return false;
    }

    _setBusy(true);
    try {
      final result = await _authService.signIn(
        email: normalizedEmail,
        password: password,
        rememberMe: _rememberMe,
      );
      if (result.success) {
        _isAuthenticated = true;
        _registeredEmail = normalizedEmail;
        _errorMessage = null;
        _lockedUntil = null;
        _remainingAttempts = 5;
        notifyListeners();
        return true;
      }

      _isAuthenticated = false;
      _lockedUntil = result.lockedUntil;
      _remainingAttempts = result.remainingAttempts;
      if (_lockedUntil != null) {
        _errorMessage = 'Too many failed attempts. Please try again later.';
      } else if (result.remainingAttempts == 0) {
        _errorMessage = 'Authentication failed.';
      } else {
        _errorMessage =
            'Invalid email or password. Remaining attempts: $_remainingAttempts';
      }
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Creates a new account on first launch.
  Future<bool> createAccount({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!_isValidEmail(normalized)) {
      _errorMessage = 'Enter a valid email address.';
      notifyListeners();
      return false;
    }
    if (password.length < 6) {
      _errorMessage = 'Password must be at least 6 characters.';
      notifyListeners();
      return false;
    }
    _setBusy(true);
    try {
      await _authService.register(email: normalized, password: password);
      _hasAccount = true;
      _registeredEmail = normalized;
      _isAuthenticated = true;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Changes the password, requires current password for verification.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      _errorMessage = 'New password must be at least 6 characters.';
      notifyListeners();
      return false;
    }
    _setBusy(true);
    try {
      final ok = await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (!ok) {
        _errorMessage = 'Current password is incorrect.';
        notifyListeners();
        return false;
      }
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Updates the account email, requires current password for verification.
  Future<bool> updateEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final normalized = newEmail.trim().toLowerCase();
    if (!_isValidEmail(normalized)) {
      _errorMessage = 'Enter a valid email address.';
      notifyListeners();
      return false;
    }
    _setBusy(true);
    try {
      final ok = await _authService.updateEmail(
        currentPassword: currentPassword,
        newEmail: normalized,
      );
      if (!ok) {
        _errorMessage = 'Password is incorrect.';
        notifyListeners();
        return false;
      }
      _registeredEmail = normalized;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> lock() async {
    _isAuthenticated = false;
    _rememberMe = false;
    await _authService.signOut(forgetRemembered: true);
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  bool _isValidEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) {
      return false;
    }
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return regex.hasMatch(email);
  }
}
