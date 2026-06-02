class AppUser {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final bool verified;
  final DateTime created;

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    this.verified = false,
    required this.created,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      username: json['username'] ?? json['email'] ?? '',
      email: json['email'] ?? '',
      avatarUrl: json['avatar'],
      verified: json['verified'] ?? false,
      created: DateTime.tryParse(json['created'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'email': email,
    };
  }
}