class Device {
  final String id;
  final String type;
  final String brand;
  final String model;
  final String? serial;
  final String? imei;
  final String? color;
  final String? photoUrl;
  final List<String>? accessories;

  Device({
    required this.id,
    required this.type,
    required this.brand,
    required this.model,
    this.serial,
    this.imei,
    this.color,
    this.photoUrl,
    this.accessories,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'],
      type: json['type'],
      brand: json['brand'],
      model: json['model'],
      serial: json['serial'],
      imei: json['imei'],
      color: json['color'],
      photoUrl: json['photoUrl'],
      accessories: json['accessories'] != null
          ? List<String>.from(json['accessories'])
          : null,
    );
  }
}
