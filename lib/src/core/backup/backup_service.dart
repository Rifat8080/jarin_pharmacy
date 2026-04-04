import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

/// Handles full-application data backup and restore.
///
/// The backup file is a UTF-8 encoded JSON document containing:
///   - `format_version` – schema version for forward-compatibility checks.
///   - `exported_at` – UTC ISO-8601 timestamp of when the backup was created.
///   - `device_id` – stable UUID stored in secure storage, identifies the
///     source device/browser so users can tell which backup is newer.
///   - `checksum` – SHA-256 hex digest of the `data` section; verifies
///     integrity before any restore is attempted.
///   - `data` – one key per exported table, value is a list of row maps.
///
/// Authentication tables (`auth_users`, `auth_state`) are intentionally
/// excluded so that credentials are never exported and each device/user
/// maintains its own login independently of the imported business data.
class BackupService {
  static const int _formatVersion = 1;
  static const String _deviceIdKey = 'jarin_backup_device_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

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

  Future<String> _getOrCreateDeviceId() async {
    var id = await _storage.read(key: _deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: id);
    }
    return id;
  }

  /// Serialises the entire database to a signed JSON backup.
  ///
  /// The returned [Uint8List] is ready to be written to a `.json` file.
  Future<Uint8List> createBackup() async {
    final db = await AppDatabase.instance.database;
    final Map<String, dynamic> data = {};

    for (final table in _exportOrder) {
      data[table] = await db.query(table);
    }

    final dataJson = jsonEncode(data);
    final checksum = sha256.convert(utf8.encode(dataJson)).toString();
    final deviceId = await _getOrCreateDeviceId();

    final payload = {
      'format_version': _formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': deviceId,
      'checksum': checksum,
      'data': data,
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  /// Parses and validates a backup file without making any DB changes.
  ///
  /// Returns [ImportResult.success] with [BackupMeta] when the file is valid.
  Future<ImportResult> validateBackup(Uint8List bytes) async {
    try {
      final jsonStr = utf8.decode(bytes);
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;

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
        error: 'Failed to parse backup file: $e',
      );
    }
  }

  /// Validates and fully restores a backup, replacing all existing business data.
  ///
  /// - Auth credentials (`auth_users`, `auth_state`) are NOT touched.
  /// - Foreign-key constraints are disabled for the duration of the bulk
  ///   replace and re-enabled unconditionally afterwards.
  /// - The entire operation runs inside a single SQLite transaction so a
  ///   failure leaves the database unchanged.
  Future<ImportResult> restoreBackup(Uint8List bytes) async {
    final validation = await validateBackup(bytes);
    if (!validation.success) return validation;

    try {
      final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>;
      final db = await AppDatabase.instance.database;

      // Disable FK constraints to allow unrestricted bulk replace.
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
}
