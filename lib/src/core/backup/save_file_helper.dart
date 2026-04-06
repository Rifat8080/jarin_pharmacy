// Conditional export: dart:html path for web, file_picker path for native.
// dart.library.js_interop is true on web (Dart 3+ standard).
// dart.library.html is true on web too but is deprecated since Dart 3.
export 'save_file_helper_stub.dart'
    if (dart.library.js_interop) 'save_file_helper_web.dart';
