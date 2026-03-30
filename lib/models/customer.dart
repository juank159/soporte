class Customer {
  final String id;
  final String fullName;
  final String idNumber;
  final String phone;
  final String? email;
  final String? notes;

  Customer({
    required this.id,
    required this.fullName,
    required this.idNumber,
    required this.phone,
    this.email,
    this.notes,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'],
      fullName: json['fullName'],
      idNumber: json['idNumber'],
      phone: json['phone'],
      email: json['email'],
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'idNumber': idNumber,
        'phone': phone,
        'email': email,
        'notes': notes,
      };
}
