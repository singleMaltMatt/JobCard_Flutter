import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kStartTimeKey = 'on_site_timer_start';

// Runs in the background isolate — must be a top-level function.
@pragma('vm:entry-point')
void startTimerCallback() {
  FlutterForegroundTask.setTaskHandler(OnSiteTimerHandler());
}

class OnSiteTimerHandler extends TaskHandler {
  DateTime? _startTime;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kStartTimeKey);
    _startTime = saved != null ? DateTime.tryParse(saved) : null;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_startTime == null) return;
    final elapsed = DateTime.now().difference(_startTime!);
    FlutterForegroundTask.updateService(
      notificationTitle: 'On Site',
      notificationText: _fmt(elapsed),
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class TimerNotificationService {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'on_site_timer',
        channelName: 'On Site Timer',
        channelDescription: 'Live timer showing time spent on site',
        onlyAlertOnce: true,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> startTimer(DateTime startTime) async {
    await FlutterForegroundTask.requestNotificationPermission();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStartTimeKey, startTime.toIso8601String());

    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'On Site',
      notificationText: '00:00:00',
      callback: startTimerCallback,
    );
  }

  static Future<void> stopTimer() async {
    await FlutterForegroundTask.stopService();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStartTimeKey);
  }
}
