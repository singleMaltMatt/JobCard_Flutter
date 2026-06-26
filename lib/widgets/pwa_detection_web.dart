import 'package:web/web.dart' as web;

bool isRunningAsPwa() {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}

bool isIOSSafari() {
  try {
    final ua = web.window.navigator.userAgent;
    return ua.contains('iPhone') ||
        ua.contains('iPad') ||
        ua.contains('iPod');
  } catch (_) {
    return false;
  }
}
