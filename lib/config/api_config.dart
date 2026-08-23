class ApiConfig {
  // Change this to your PocketBase server URL
  // For local dev: http://10.0.2.2:8090 (Android emulator)
  // For real device: http://YOUR_IP:8090 or your Cloudflare tunnel URL
  static const String baseUrl = 'https://jobtracking.globalsense.co.za';

  // API endpoints
  static const String loginEndpoint = '/api/collections/users/auth-with-password';
  static const String registerEndpoint = '/api/collections/users/records';
  static const String jobsEndpoint = '/api/collections/jobs/records';
  static const String clientsEndpoint = '/api/collections/clients/records';
  static const String usersEndpoint = '/api/collections/users/records';

  static String jobEndpoint(String id) => '/api/collections/jobs/records/$id';
  static String clientEndpoint(String id) => '/api/collections/clients/records/$id';
  static String userEndpoint(String id) => '/api/collections/users/records/$id';

  // Sales portal
  static const String superuserLoginEndpoint = '/api/collections/_superusers/auth-with-password';
  static const String suppliersEndpoint = '/api/collections/suppliers/records';
  static const String salesOrdersEndpoint = '/api/collections/sales_orders/records';

  static String supplierEndpoint(String id) => '/api/collections/suppliers/records/$id';
  static String salesOrderEndpoint(String id) => '/api/collections/sales_orders/records/$id';
}