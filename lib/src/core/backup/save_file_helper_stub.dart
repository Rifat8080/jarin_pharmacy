import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Native (desktop/mobile) implementation — opens a save dialog.
Future<void> saveBackupFile(String filename, Uint8List bytes) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'Save Backup',
    fileName: filename,
    bytes: bytes,
  );
}
