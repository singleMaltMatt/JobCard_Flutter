import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/job_provider.dart';
import '../widgets/header_banner.dart';
import '../widgets/jobs_tab.dart';
import '../widgets/active_jobs_tab.dart';
import '../widgets/completed_jobs_tab.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/pwa_install_dialog.dart';
import 'login_screen.dart';
import 'create_job_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTabIndex = 1;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        context.read<JobProvider>().initializeWebSync();
        // Slight delay so the screen is fully rendered before the dialog
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        await PwaInstallDialog.show(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JobProvider>(
      builder: (context, jobProvider, _) {
        return Scaffold(
          appBar: HeaderBanner(
            onAvatarTap: () {
              final auth = context.read<AuthProvider>();
              if (auth.isAuthenticated) {
                _showLogoutDialog();
              } else {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
          body: Column(
            children: [
              const SyncStatusBanner(),
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: const [
                    JobsTab(),
                    ActiveJobsTab(),
                    CompletedJobsTab(),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _selectedTabIndex == 0
              ? FloatingActionButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateJobScreen()),
                    );
                  },
                  child: const Icon(Icons.add),
                )
              : null,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedTabIndex,
            onTap: (index) {
              setState(() => _selectedTabIndex = index);
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.list_alt),
                label: AppConstants.tabJobs,
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.work),
                label: AppConstants.tabActive,
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.check_circle),
                label: AppConstants.tabCompleted,
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: Text('Logged in as ${context.read<AuthProvider>().user?.username ?? "User"}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}