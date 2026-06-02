class AppConstants {
  static const String appName = 'JobCard Tracker';

  // Job statuses
  static const List<String> jobStatuses = [
    'pending',
    'accepted',
    'on_route',
    'on_site',
    'completed',
  ];

  static const String statusPending = 'pending';
  static const String statusAccepted = 'accepted';
  static const String statusOnRoute = 'on_route';
  static const String statusOnSite = 'on_site';
  static const String statusCompleted = 'completed';

  // Tab titles
  static const String tabJobs = 'Jobs';
  static const String tabActive = 'Active';
  static const String tabCompleted = 'Completed';

  // Display labels for statuses
  static String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'on_route':
        return 'On Route';
      case 'on_site':
        return 'On Site';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }
}