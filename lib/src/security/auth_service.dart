import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/db/app_database.dart';

class AuthService {
  AuthService({FlutterSecureStorage? storage})
    : _legacyStorage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _legacyStorage;
  static const Uuid _uuid = Uuid();

  static const int _hashRounds = 60000;
  static const int _maxFailedAttempts = 5;
  static const Duration _lockDuration = Duration(minutes: 2);

  static const String _emailKey = 'auth.user.email';
  static const String _hashKey = 'auth.user.password.hash';
  static const String _saltKey = 'auth.user.password.salt';
  static const String _failedAttemptsKey = 'auth.failed_attempts';
  static const String _lockedUntilKey = 'auth.locked_until';
  static const String _sessionActiveKey = 'auth.session.active';
  static const String _rememberMeKey = 'auth.session.remember_me';
  static const String _seedNoticeDismissedKey = 'auth.seed.notice.dismissed';

  bool _legacyMigrated = false;

  Future<Database> get _db async => AppDatabase.instance.database;

  Future<bool> hasUser() async {
    await _migrateLegacyStorageIfNeeded();
    final db = await _db;
    final rows = await db.query('auth_users', columns: ['id'], limit: 1);
    return rows.isNotEmpty;
  }

  Future<String?> getRegisteredEmail() async {
    await _migrateLegacyStorageIfNeeded();
    final db = await _db;
    final rows = await db.query(
      'auth_users',
      columns: ['email'],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['email'] as String;
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    await _migrateLegacyStorageIfNeeded();
    final db = await _db;
    final salt = _generateSalt();
    final digest = _computeHash(password, salt);
    final normalizedEmail = email.trim().toLowerCase();
    final now = DateTime.now().toIso8601String();

    final existing = await db.query(
      'auth_users',
      columns: ['id'],
      orderBy: 'created_at ASC',
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('auth_users', {
        'id': _uuid.v4(),
        'email': normalizedEmail,
        'password_hash': digest,
        'password_salt': base64Encode(salt),
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update(
        'auth_users',
        {
          'email': normalizedEmail,
          'password_hash': digest,
          'password_salt': base64Encode(salt),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }

    await _writeState(_failedAttemptsKey, '0');
    await _writeState(_sessionActiveKey, '1');
    await _writeState(_rememberMeKey, '0');
    await _deleteState(_lockedUntilKey);
  }

  Future<bool> isRememberedSession() async {
    await _migrateLegacyStorageIfNeeded();
    final active = await _readState(_sessionActiveKey);
    final remember = await _readState(_rememberMeKey);
    return active == '1' || remember == '1';
  }

  Future<bool> hasDismissedSeedNotice() async {
    await _migrateLegacyStorageIfNeeded();
    return await _readState(_seedNoticeDismissedKey) == '1';
  }

  Future<void> dismissSeedNoticePermanently() async {
    await _migrateLegacyStorageIfNeeded();
    await _writeState(_seedNoticeDismissedKey, '1');
  }

  Future<VerificationResult> signIn({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    await _migrateLegacyStorageIfNeeded();
    final lockInfo = await getLockInfo();
    if (lockInfo.isLocked) {
      return VerificationResult(
        success: false,
        remainingAttempts: 0,
        lockedUntil: lockInfo.lockedUntil,
      );
    }

    final db = await _db;
    final rows = await db.query(
      'auth_users',
      columns: ['email', 'password_hash', 'password_salt'],
      where: 'LOWER(email) = LOWER(?)',
      whereArgs: [email.trim()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return const VerificationResult(success: false, remainingAttempts: 0);
    }

    final row = rows.first;
    final hash = row['password_hash'] as String;
    final saltEncoded = row['password_salt'] as String;

    final salt = base64Decode(saltEncoded);
    final computed = _computeHash(password, salt);

    if (_constantTimeEquals(hash, computed)) {
      await _writeState(_failedAttemptsKey, '0');
      await _deleteState(_lockedUntilKey);
      await _writeState(_sessionActiveKey, '1');
      await _writeState(_rememberMeKey, rememberMe ? '1' : '0');
      return const VerificationResult(
        success: true,
        remainingAttempts: _maxFailedAttempts,
      );
    }

    final failedAttempts =
        (int.tryParse(await _readState(_failedAttemptsKey) ?? '0') ?? 0) + 1;

    if (failedAttempts >= _maxFailedAttempts) {
      final lockedUntil = DateTime.now().add(_lockDuration);
      await _writeState(_failedAttemptsKey, '0');
      await _writeState(_lockedUntilKey, lockedUntil.toIso8601String());
      return VerificationResult(
        success: false,
        remainingAttempts: 0,
        lockedUntil: lockedUntil,
      );
    }

    await _writeState(_failedAttemptsKey, failedAttempts.toString());
    return VerificationResult(
      success: false,
      remainingAttempts: _maxFailedAttempts - failedAttempts,
    );
  }

  Future<bool> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    await _migrateLegacyStorageIfNeeded();
    final db = await _db;
    final normalizedEmail = email.trim().toLowerCase();
    final existing = await db.query(
      'auth_users',
      columns: ['id'],
      where: 'LOWER(email) = LOWER(?)',
      whereArgs: [normalizedEmail],
      limit: 1,
    );
    if (existing.isEmpty) {
      return false;
    }

    final salt = _generateSalt();
    final digest = _computeHash(newPassword, salt);
    await db.update(
      'auth_users',
      {
        'password_salt': base64Encode(salt),
        'password_hash': digest,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [existing.first['id']],
    );
    await _writeState(_failedAttemptsKey, '0');
    await _deleteState(_lockedUntilKey);
    await _writeState(_sessionActiveKey, '0');
    return true;
  }

  /// Changes the password for the currently signed-in user.
  /// Requires [currentPassword] for verification.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _migrateLegacyStorageIfNeeded();
    final db = await _db;
    final rows = await db.query(
      'auth_users',
      columns: ['id', 'password_hash', 'password_salt'],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final row = rows.first;
    final salt = base64Decode(row['password_salt'] as String);
    final computed = _computeHash(currentPassword, salt);
    if (!_constantTimeEquals(row['password_hash'] as String, computed)) {
      return false;
    }

    final newSalt = _generateSalt();
    final newDigest = _computeHash(newPassword, newSalt);
    await db.update(
      'auth_users',
      {
        'password_hash': newDigest,
        'password_salt': base64Encode(newSalt),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    return true;
  }

  /// Updates the email for the currently signed-in user.
  /// Requires [currentPassword] for verification.
  Future<bool> updateEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    await _migrateLegacyStorageIfNeeded();
    final db = await _db;
    final rows = await db.query(
      'auth_users',
      columns: ['id', 'password_hash', 'password_salt'],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final row = rows.first;
    final salt = base64Decode(row['password_salt'] as String);
    final computed = _computeHash(currentPassword, salt);
    if (!_constantTimeEquals(row['password_hash'] as String, computed)) {
      return false;
    }

    final normalized = newEmail.trim().toLowerCase();
    await db.update(
      'auth_users',
      {'email': normalized, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    return true;
  }

  Future<void> signOut({bool forgetRemembered = false}) async {
    await _migrateLegacyStorageIfNeeded();
    await _writeState(_sessionActiveKey, '0');
    if (forgetRemembered) {
      await _writeState(_rememberMeKey, '0');
    }
  }

  Future<LockInfo> getLockInfo() async {
    await _migrateLegacyStorageIfNeeded();
    final raw = await _readState(_lockedUntilKey);
    if (raw == null || raw.isEmpty) {
      return const LockInfo(isLocked: false, lockedUntil: null);
    }

    final lockedUntil = DateTime.tryParse(raw);
    if (lockedUntil == null) {
      await _deleteState(_lockedUntilKey);
      return const LockInfo(isLocked: false, lockedUntil: null);
    }

    if (DateTime.now().isAfter(lockedUntil)) {
      await _deleteState(_lockedUntilKey);
      return const LockInfo(isLocked: false, lockedUntil: null);
    }

    return LockInfo(isLocked: true, lockedUntil: lockedUntil);
  }

  Future<void> clearAuth() async {
    final db = await _db;
    await db.delete('auth_users');
    await db.delete('auth_state');
    await _legacyStorage.deleteAll();
    _legacyMigrated = true;
  }

  Future<void> _migrateLegacyStorageIfNeeded() async {
    if (_legacyMigrated) {
      return;
    }

    final db = await _db;
    final existing = await db.query('auth_users', columns: ['id'], limit: 1);
    if (existing.isNotEmpty) {
      _legacyMigrated = true;
      return;
    }

    final email = await _legacyStorage.read(key: _emailKey).catchError((_) => null);
    final hash  = await _legacyStorage.read(key: _hashKey).catchError((_) => null);
    final salt  = await _legacyStorage.read(key: _saltKey).catchError((_) => null);
    if (email == null || hash == null || salt == null) {
      _legacyMigrated = true;
      return;
    }

    final now = DateTime.now().toIso8601String();
    await db.insert('auth_users', {
      'id': _uuid.v4(),
      'email': email.trim().toLowerCase(),
      'password_hash': hash,
      'password_salt': salt,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await _copyLegacyStateIfPresent(_failedAttemptsKey);
    await _copyLegacyStateIfPresent(_lockedUntilKey);
    await _copyLegacyStateIfPresent(_sessionActiveKey);
    await _copyLegacyStateIfPresent(_rememberMeKey);

    _legacyMigrated = true;
  }

  Future<void> _copyLegacyStateIfPresent(String key) async {
    final String? value;
    try {
      value = await _legacyStorage.read(key: key);
    } catch (_) {
      return; // Keychain unavailable on this platform/build
    }
    if (value == null) {
      return;
    }
    await _writeState(key, value);
  }

  Future<String?> _readState(String key) async {
    final db = await _db;
    final rows = await db.query(
      'auth_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String;
  }

  Future<void> _writeState(String key, String value) async {
    final db = await _db;
    await db.insert('auth_state', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _deleteState(String key) async {
    final db = await _db;
    await db.delete('auth_state', where: 'key = ?', whereArgs: [key]);
  }

  List<int> _generateSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }

  String _computeHash(String passcode, List<int> salt) {
    var bytes = <int>[...salt, ...utf8.encode(passcode)];
    Digest digest = sha256.convert(bytes);

    for (var index = 0; index < _hashRounds; index++) {
      digest = sha256.convert([...digest.bytes, ...salt]);
    }

    return digest.toString();
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) {
      return false;
    }

    var result = 0;
    for (var index = 0; index < left.length; index++) {
      result |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return result == 0;
  }
}

class VerificationResult {
  const VerificationResult({
    required this.success,
    required this.remainingAttempts,
    this.lockedUntil,
  });

  final bool success;
  final int remainingAttempts;
  final DateTime? lockedUntil;
}

class LockInfo {
  const LockInfo({required this.isLocked, required this.lockedUntil});

  final bool isLocked;
  final DateTime? lockedUntil;
}
