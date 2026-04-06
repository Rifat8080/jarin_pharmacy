import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native implementation.
/// - Android / iOS : writes to temp dir then opens the system share sheet,
///   allowing the user to save to Files, Google Drive, WhatsApp, etc.
/// - Desktop (macOS / Windows / Linux): opens a native save-file dialog.
Future<void> saveBackupFile(String filename, Uint8List bytes) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'application/json', name: filename),
    ], subject: filename);
  } else {
    // Desktop: native save-file dialog.
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Backup',
      fileName: filename,
    );
    if (path == null) return; // user cancelled
    await File(path).writeAsBytes(bytes, flush: true);
  }
}
