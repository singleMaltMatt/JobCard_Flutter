import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/auth_provider.dart';

class HeaderBanner extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onAvatarTap;

  const HeaderBanner({super.key, required this.onAvatarTap});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.primaryBlue,
      elevation: 2,
      title: const Text(
        AppConstants.appName,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      actions: [
        Consumer<AuthProvider>(
          builder: (context, auth, _) {
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: onAvatarTap,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: auth.isAuthenticated
                      ? Text(
                          (auth.user?.username.isNotEmpty == true
                                  ? auth.user!.username[0]
                                  : 'U')
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          color: AppTheme.primaryBlue,
                          size: 22,
                        ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}