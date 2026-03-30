class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? tenantId;
  final bool isActive;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.tenantId,
    this.isActive = true,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? '',
      role: json['role'] ?? '',
      tenantId: json['tenantId'],
      isActive: json['isActive'] ?? true,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isSupervisor => role == 'supervisor';
  bool get isTechnician => role == 'technician';
  bool get isReception => role == 'reception';
}
