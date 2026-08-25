import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'screens/login_screen.dart';
import 'services/pocketbase_client.dart';
import 'services/auth_service.dart';
import 'services/job_service.dart';
import 'services/client_service.dart';
import 'services/sales_order_service.dart';
import 'services/timer_notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/job_provider.dart';
import 'providers/tech_sales_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TimerNotificationService uses native APIs not available on web.
  if (!kIsWeb) TimerNotificationService.init();

  // Initialize services
  final pocketBaseClient = PocketBaseClient();
  final authService = AuthService(pocketBaseClient);
  final jobService = JobService(pocketBaseClient);
  final clientService = ClientService(pocketBaseClient);
  final salesOrderService = SalesOrderService(pocketBaseClient);
  final authProvider = AuthProvider(authService);

  // If any API call comes back 401 (expired/invalid session), force a
  // logout and drop the technician back on the login screen — from
  // wherever they happen to be in the app.
  pocketBaseClient.onUnauthorized = () {
    if (!authProvider.isAuthenticated) return;
    authProvider.forceLogout();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        Provider<PocketBaseClient>.value(value: pocketBaseClient),
        ChangeNotifierProvider(
          create: (_) => JobProvider(jobService, clientService),
        ),
        ChangeNotifierProvider(
          create: (_) => TechSalesProvider(salesOrderService),
        ),
      ],
      child: const JobCardTrackerApp(),
    ),
  );
}