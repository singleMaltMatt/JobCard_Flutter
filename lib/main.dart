import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/pocketbase_client.dart';
import 'services/auth_service.dart';
import 'services/job_service.dart';
import 'services/client_service.dart';
import 'services/timer_notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/job_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TimerNotificationService uses native APIs not available on web.
  if (!kIsWeb) TimerNotificationService.init();

  // Initialize services
  final pocketBaseClient = PocketBaseClient();
  final authService = AuthService(pocketBaseClient);
  final jobService = JobService(pocketBaseClient);
  final clientService = ClientService(pocketBaseClient);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService),
        ),
        ChangeNotifierProvider(
          create: (_) => JobProvider(jobService, clientService),
        ),
      ],
      child: const JobCardTrackerApp(),
    ),
  );
}