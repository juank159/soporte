class Tenant {
  final String id;
  final String name;
  final String slug;
  final String plan;
  final String? logoUrl;
  final String? nit;
  final String? address;
  final String? phone;
  final String? email;
  final String timezone;
  final int warrantyDays;
  final String? warrantyConditions;
  final String? legalNotice;

  Tenant({
    required this.id,
    required this.name,
    required this.slug,
    this.plan = 'basic',
    this.logoUrl,
    this.nit,
    this.address,
    this.phone,
    this.email,
    this.timezone = 'America/Bogota',
    this.warrantyDays = 30,
    this.warrantyConditions,
    this.legalNotice,
  });

  factory Tenant.fromJson(Map<String, dynamic> json) {
    return Tenant(
      id: json['id'],
      name: json['name'],
      slug: json['slug'],
      plan: json['plan'] ?? 'basic',
      logoUrl: json['logoUrl'],
      nit: json['nit'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      timezone: json['timezone'] ?? 'America/Bogota',
      warrantyDays: json['warrantyDays'] ?? 30,
      warrantyConditions: json['warrantyConditions'],
      legalNotice: json['legalNotice'],
    );
  }
}
