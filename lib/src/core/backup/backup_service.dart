import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

/// Metadata extracted from a backup file.
class BackupMeta {
  final int formatVersion;
  final String exportedAt;
  final String deviceId;
  final String checksum;

  const BackupMeta({
    required this.formatVersion,
    required this.exportedAt,
    required this.deviceId,
    required this.checksum,
  });
}

/// Result of a validation or restore operation.
class ImportResult {
  final bool success;
  final String? error;
  final BackupMeta? meta;

  const ImportResult({required this.success, this.error, this.meta});
}

/// Per-table breakdown of what would change when importing a backup.
class TableConflict {
  final String table;
  final int localCount;
  final int backupCount;

  /// Records present in the backup but not locally — will be inserted on merge.
  final int newInBackup;

  /// Records present locally but absent from the backup — kept on merge, lost on full replace.
  final int localOnly;

  /// Records present in both devices.
  final int common;

  const TableConflict({
    required this.table,
    required this.localCount,
    required this.backupCount,
    required this.newInBackup,
    required this.localOnly,
    required this.common,
  });

  bool get hasLocalOnly => localOnly > 0;
  bool get hasNewData => newInBackup > 0;
}

/// Full analysis of a pending import operation — no data is changed.
class ConflictReport {
  final BackupMeta meta;
  final List<TableConflict> tables;

  /// Total records in backup that do not exist locally.
  final int totalNewInBackup;

  /// Total local-only records that would be lost with a full replace.
  final int totalLocalOnly;

  /// ISO-8601 timestamp of the newest local transaction record (null if empty DB).
  final String? localNewestAt;

  const ConflictReport({
    required this.meta,
    required this.tables,
    required this.totalNewInBackup,
    required this.totalLocalOnly,
    this.localNewestAt,
  });

  /// True when this device has transaction records created AFTER the backup's
  /// exported_at — importing this backup as a full replace would destroy them.
  bool get localHasNewerRecords {
    if (localNewestAt == null || meta.exportedAt.isEmpty) return false;
    return localNewestAt!.compareTo(meta.exportedAt) > 0;
  }

  bool get hasConflicts => totalLocalOnly > 0;
  bool get hasNewData => totalNewInBackup > 0;
}

/// Handles full-application data backup and restore.
///
/// Backup format v2 (current):
///   - `format_version` : 2
///   - `exported_at`    : UTC ISO-8601 timestamp
///   - `device_id`      : stable UUID (identifies source device)
///   - `checksum`       : SHA-256 hex digest of the *plaintext* data JSON,
///                        computed before encryption for tamper-detection
///   - `salt`           : base64 of 16 random bytes — per-backup PBKDF2 salt
///   - `iv`             : base64 of 16 random bytes — AES-CBC initialisation vector
///   - `encrypted_data` : base64 AES-256-CBC ciphertext of the data JSON
///
/// The plaintext `data` field is NOT present in the file; the business data
/// is always stored encrypted.  A legacy v1 backup (with plaintext `data`) can
/// still be imported for backward compatibility.
///
/// Authentication tables (`auth_users`, `auth_state`) are never exported.
class BackupService {
  /// Increment to 3 if the on-disk format changes incompatibly.
  static const int _formatVersion = 2;
  static const String _deviceIdKey = 'jarin_backup_device_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // ── Encryption constants ───────────────────────────────────────────────────

  /// App-level passphrase used as the PBKDF2 password.
  /// Combined with a per-backup random salt so each backup file has a
  /// unique AES key, even if exported at the same second.
  static const String _appSecret =
      r'JarinPharmacy$2026!bK@sh*Rx#d4ta_AES256_pr0tect';

  /// PBKDF2 iteration count — high enough to slow offline brute-force,
  /// low enough to keep export/import under ~50 ms on a mid-range phone.
  static const int _pbkdf2Iterations = 10000;

  /// Tables exported in FK-safe insert order (parents before children).
  static const List<String> _exportOrder = [
    'products',
    'customers',
    'bkash_accounts',
    'invoices',
    'invoice_items',
    'invoice_payments',
    'sales',
    'purchases',
    'inventory_adjustments',
    'bkash_transactions',
  ];

  /// Deletion order: children before parents to satisfy FK constraints.
  static const List<String> _deleteOrder = [
    'bkash_transactions',
    'inventory_adjustments',
    'purchases',
    'sales',
    'invoice_payments',
    'invoice_items',
    'invoices',
    'bkash_accounts',
    'customers',
    'products',
  ];

  /// Transaction tables that carry a `created_at` column, used to detect
  /// whether local data is newer than the backup.
  static const List<String> _timestampedTables = [
    'sales',
    'invoices',
    'purchases',
    'bkash_transactions',
    'inventory_adjustments',
  ];

  Future<String> _getOrCreateDeviceId() async {
    var id = await _storage.read(key: _deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: id);
    }
    return id;
  }

  // ── Crypto helpers ─────────────────────────────────────────────────────────

  Uint8List _randomBytes(int count) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => rng.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256: derives a 32-byte AES key from [_appSecret] + [salt].
  Uint8List _deriveKey(Uint8List salt) {
    const keyLen = 32;
    final hmac = Hmac(sha256, utf8.encode(_appSecret));
    final block = ByteData(4)..setUint32(0, 1, Endian.big);
    var u = Uint8List.fromList(
      hmac.convert([...salt, ...block.buffer.asUint8List()]).bytes,
    );
    final result = Uint8List.fromList(u);
    for (int i = 1; i < _pbkdf2Iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int j = 0; j < keyLen; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  String _encrypt(String plaintext, Uint8List salt, Uint8List ivBytes) {
    final key = enc.Key(_deriveKey(salt));
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.encrypt(plaintext, iv: iv).base64;
  }

  String _decrypt(String cipherBase64, Uint8List salt, Uint8List ivBytes) {
    final key = enc.Key(_deriveKey(salt));
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(cipherBase64, iv: iv);
  }

  /// Parses the backup bytes and, if the payload is encrypted (v2+), decrypts
  /// the data section.  Returns the envelope map with a plain `data` key ready
  /// for all downstream processing.
  ///
  /// Throws a [FormatException] if decryption or JSON parsing fails.
  Map<String, dynamic> _decryptPayload(Uint8List bytes) {
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    if (payload.containsKey('encrypted_data')) {
      // v2 encrypted backup
      final saltB64 = payload['salt'] as String;
      final ivB64 = payload['iv'] as String;
      final cipherB64 = payload['encrypted_data'] as String;

      final salt = base64.decode(saltB64);
      final ivBytes = base64.decode(ivB64);
      final plaintext = _decrypt(cipherB64, salt, ivBytes);
      payload['data'] = jsonDecode(plaintext) as Map<String, dynamic>;
    }

    return payload;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Serialises and **encrypts** the entire database to a signed backup.
  ///
  /// The returned [Uint8List] is ready to be written to a `.json` file.
  /// The file contains no plaintext business data.
  Future<Uint8List> createBackup() async {
    final db = await AppDatabase.instance.database;
    final Map<String, dynamic> data = {};

    for (final table in _exportOrder) {
      data[table] = await db.query(table);
    }

    final dataJson = jsonEncode(data);

    // Integrity checksum is computed on the plaintext BEFORE encryption.
    final checksum = sha256.convert(utf8.encode(dataJson)).toString();

    final salt = _randomBytes(16);
    final ivBytes = _randomBytes(16);
    final cipherB64 = _encrypt(dataJson, salt, ivBytes);
    final deviceId = await _getOrCreateDeviceId();

    final payload = {
      'format_version': _formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': deviceId,
      'checksum': checksum,
      'salt': base64.encode(salt),
      'iv': base64.encode(ivBytes),
      'encrypted_data': cipherB64,
      // `data` is intentionally omitted — stored only as ciphertext above.
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  /// Parses and validates a backup file without making any DB changes.
  ///
  /// Returns [ImportResult.success] with [BackupMeta] when the file is valid.
  Future<ImportResult> validateBackup(Uint8List bytes) async {
    try {
      final payload = _decryptPayload(bytes);

      final version = payload['format_version'] as int?;
      if (version == null || version > _formatVersion) {
        return ImportResult(
          success: false,
          error:
              'Incompatible backup version ($version). '
              'This app supports up to version $_formatVersion.',
        );
      }

      final data = payload['data'];
      if (data == null || data is! Map) {
        return ImportResult(
          success: false,
          error: 'Backup file is missing the data section.',
        );
      }

      final storedChecksum = payload['checksum'] as String?;
      if (storedChecksum != null) {
        final computed = sha256
            .convert(utf8.encode(jsonEncode(data)))
            .toString();
        if (computed != storedChecksum) {
          return ImportResult(
            success: false,
            error:
                'Integrity check failed — the backup file may be corrupted or tampered with.',
          );
        }
      }

      return ImportResult(
        success: true,
        meta: BackupMeta(
          formatVersion: version,
          exportedAt: payload['exported_at'] as String? ?? 'unknown',
          deviceId: payload['device_id'] as String? ?? 'unknown',
          checksum: storedChecksum ?? '',
        ),
      );
    } catch (e) {
      return ImportResult(
        success: false,
        error: 'Failed to open backup file: $e',
      );
    }
  }

  /// Validates and fully restores a backup, replacing all existing business data.
  Future<ImportResult> restoreBackup(Uint8List bytes) async {
    final validation = await validateBackup(bytes);
    if (!validation.success) return validation;

    try {
      final payload = _decryptPayload(bytes);
      final data = payload['data'] as Map<String, dynamic>;
      final db = await AppDatabase.instance.database;

      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction((txn) async {
          for (final table in _deleteOrder) {
            await txn.delete(table);
          }
          for (final table in _exportOrder) {
            final rows = (data[table] as List<dynamic>?) ?? [];
            for (final row in rows) {
              await txn.insert(
                table,
                Map<String, dynamic>.from(row as Map),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      return validation;
    } catch (e) {
      return ImportResult(success: false, error: 'Restore failed: $e');
    }
  }

  /// Compares a backup against the live database and returns a [ConflictReport]
  /// without touching any data.
  Future<ConflictReport> analyzeConflicts(Uint8List bytes) async {
    final validation = await validateBackup(bytes);
    if (!validation.success) {
      return const ConflictReport(
        meta: BackupMeta(
          formatVersion: 0,
          exportedAt: '',
          deviceId: 'unknown',
          checksum: '',
        ),
        tables: [],
        totalNewInBackup: 0,
        totalLocalOnly: 0,
      );
    }

    final db = await AppDatabase.instance.database;
    final payload = _decryptPayload(bytes);
    final data = payload['data'] as Map<String, dynamic>;

    final tableConflicts = <TableConflict>[];
    String? localNewestAt;

    for (final table in _exportOrder) {
      final backupRows = (data[table] as List<dynamic>?) ?? [];
      final backupIds = backupRows
          .map((r) => (r as Map)['id'] as String)
          .toSet();

      final localIdRows = await db.query(table, columns: ['id']);
      final localIds = localIdRows.map((r) => r['id'] as String).toSet();

      tableConflicts.add(
        TableConflict(
          table: table,
          localCount: localIds.length,
          backupCount: backupIds.length,
          newInBackup: backupIds.difference(localIds).length,
          localOnly: localIds.difference(backupIds).length,
          common: localIds.intersection(backupIds).length,
        ),
      );

      if (_timestampedTables.contains(table)) {
        final result = await db.rawQuery(
          'SELECT MAX(created_at) AS newest FROM $table',
        );
        final newest = result.firstOrNull?['newest'] as String?;
        if (newest != null &&
            (localNewestAt == null || newest.compareTo(localNewestAt) > 0)) {
          localNewestAt = newest;
        }
      }
    }

    return ConflictReport(
      meta: validation.meta!,
      tables: tableConflicts,
      totalNewInBackup: tableConflicts.fold(0, (s, t) => s + t.newInBackup),
      totalLocalOnly: tableConflicts.fold(0, (s, t) => s + t.localOnly),
      localNewestAt: localNewestAt,
    );
  }

  /// Merges backup data into the local database using INSERT-OR-IGNORE.
  Future<ImportResult> mergeBackup(Uint8List bytes) async {
    final validation = await validateBackup(bytes);
    if (!validation.success) return validation;

    try {
      final payload = _decryptPayload(bytes);
      final data = payload['data'] as Map<String, dynamic>;
      final db = await AppDatabase.instance.database;

      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction((txn) async {
          for (final table in _exportOrder) {
            final rows = (data[table] as List<dynamic>?) ?? [];
            for (final row in rows) {
              await txn.insert(
                table,
                Map<String, dynamic>.from(row as Map),
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }

      return validation;
    } catch (e) {
      return ImportResult(success: false, error: 'Merge failed: $e');
    }
  }
}
