import 'dart:js_interop';
import 'package:web/web.dart' as web;

bool get webIsOnline => web.window.navigator.onLine;

void listenToConnectivity(void Function(bool online) callback) {
  web.window.addEventListener(
      'online', ((web.Event _) => callback(true)).toJS);
  web.window.addEventListener(
      'offline', ((web.Event _) => callback(false)).toJS);
}
