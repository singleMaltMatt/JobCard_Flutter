import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/sales_auth_provider.dart';
import 'providers/sales_provider.dart';
import 'screens/sales/sales_home_screen.dart';
import 'screens/sales/sales_login_screen.dart';
import 'services/pocketbase_client.dart';
import 'services/sales_order_service.dart';

// Sales portal entrypoint. Build with:
//   flutter build web --release --base-href /sales/ -t lib/main_sales.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SalesPortalApp());
}

class SalesPortalApp extends StatelessWidget {
  const SalesPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final client = PocketBaseClient();
    final salesOrderService = SalesOrderService(client);
    return MultiProvider(
      providers: [
        Provider<PocketBaseClient>.value(value: client),
        ChangeNotifierProvider(create: (_) => SalesAuthProvider(client)),
        ChangeNotifierProvider(
          create: (_) => SalesProvider(salesOrderService),
        ),
      ],
      child: MaterialApp(
        title: 'GlobalSense Sales',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const _SalesGate(),
      ),
    );
  }
}

/// Decides between login and home on startup by attempting to restore
/// a saved session.
class _SalesGate extends StatefulWidget {
  const _SalesGate();

  @override
  State<_SalesGate> createState() => _SalesGateState();
}

class _SalesGateState extends State<_SalesGate> {
  bool _checking = true;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final restored = await context.read<SalesAuthProvider>().tryRestore();
    if (mounted) {
      setState(() {
        _restored = restored;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _restored ? const SalesHomeScreen() : const SalesLoginScreen();
  }
}
