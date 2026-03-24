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
  bool _seededUserThisLaunch = false;
  int _remainingAttempts = 5;
  DateTime? _lockedUntil;
  String? _registeredEmail;
  String? _errorMessage;

  bool get initialized => _initialized;
  bool get isAuthenticated => _isAuthenticated;
  bool get hasAccount => _hasAccount;
  bool get rememberMe => _rememberMe;
  bool get isBusy => _isBusy;
  bool get seededUserThisLaunch => _seededUserThisLaunch;
  int get remainingAttempts => _remainingAttempts;
  DateTime? get lockedUntil => _lockedUntil;
  String? get registeredEmail => _registeredEmail;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    var hasAccount = await _authService.hasUser();
    final seedNoticeDismissed = await _authService.hasDismissedSeedNotice();
    const defaultEmail = 'admin@jarin.com';
    const defaultPassword = 'Jarin@2026';

    if (!hasAccount) {
      await _authService.register(email: defaultEmail, password: defaultPassword);
      await _authService.signOut(forgetRemembered: true);
      hasAccount = true;
      _seededUserThisLaunch = !seedNoticeDismissed;
    }

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

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    if (!_hasAccount) {
      _errorMessage =
          'No account exists in the app database yet. Restart once to auto-create the default user (admin@jarin.com).';
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
        await _authService.dismissSeedNoticePermanently();
        _isAuthenticated = true;
        _registeredEmail = normalizedEmail;
        _errorMessage = null;
        _lockedUntil = null;
        _remainingAttempts = 5;
        _seededUserThisLaunch = false;
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
        _errorMessage = 'Invalid email or password. Remaining attempts: $_remainingAttempts';
      }
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

  void clearSeededUserNotice() {
    if (!_seededUserThisLaunch) {
      return;
    }
    _seededUserThisLaunch = false;
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
