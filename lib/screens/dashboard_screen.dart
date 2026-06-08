import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../providers/auth_provider.dart';
import '../providers/job_provider.dart';
import '../widgets/header_banner.dart';
import '../widgets/jobs_tab.dart';
import '../widgets/active_jobs_tab.dart';
import '../widgets/completed_jobs_tab.dart';
import 'login_screen.dart';
import 'create_job_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    final jobProvider = context.read<JobProvider>();
    _pageController = PageController(initialPage: jobProvider.selectedTabIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JobProvider>(
      builder: (context, jobProvider, _) {
        // Sync page controller with provider
        if (_pageController.hasClients &&
            _pageController.page?.round() != jobProvider.selectedTabIndex) {
          _pageController.animateToPage(
            jobProvider.selectedTabIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }

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
          body: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              jobProvider.selectedTabIndex = index;
            },
            children: const [
              JobsTab(),
              ActiveJobsTab(),
              CompletedJobsTab(),
            ],
          ),
          floatingActionButton: jobProvider.selectedTabIndex == 0
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
            currentIndex: jobProvider.selectedTabIndex,
            onTap: (index) {
              jobProvider.selectedTabIndex = index;
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