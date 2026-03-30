import 'customer.dart';
import 'device.dart';

class ServiceOrder {
  final String id;
  final String orderNumber;
  final String customerId;
  final Customer? customer;
  final String deviceId;
  final Device? device;
  final String? technicianId;
  final String status;
  final String problemReported;
  final String? diagnosis;
  final String? notes;
  final double laborCost;
  final double subtotal;
  final double tax;
  final double total;
  final int warrantyDays;
  final String? pdfUrl;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? closedAt;
  final List<OrderItem> items;
  final List<OrderPhoto> photos;

  ServiceOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    this.customer,
    required this.deviceId,
    this.device,
    this.technicianId,
    required this.status,
    required this.problemReported,
    this.diagnosis,
    this.notes,
    this.laborCost = 0,
    this.subtotal = 0,
    this.tax = 0,
    this.total = 0,
    this.warrantyDays = 30,
    this.pdfUrl,
    required this.createdAt,
    this.deliveredAt,
    this.closedAt,
    this.items = const [],
    this.photos = const [],
  });

  factory ServiceOrder.fromJson(Map<String, dynamic> json) {
    return ServiceOrder(
      id: json['id'],
      orderNumber: json['orderNumber'],
      customerId: json['customerId'],
      customer:
          json['customer'] != null ? Customer.fromJson(json['customer']) : null,
      deviceId: json['deviceId'],
      device: json['device'] != null ? Device.fromJson(json['device']) : null,
      technicianId: json['technicianId'],
      status: json['status'],
      problemReported: json['problemReported'],
      diagnosis: json['diagnosis'],
      notes: json['notes'],
      laborCost: double.tryParse('${json['laborCost']}') ?? 0,
      subtotal: double.tryParse('${json['subtotal']}') ?? 0,
      tax: double.tryParse('${json['tax']}') ?? 0,
      total: double.tryParse('${json['total']}') ?? 0,
      warrantyDays: json['warrantyDays'] ?? 30,
      pdfUrl: json['pdfUrl'],
      createdAt: DateTime.parse(json['createdAt']),
      deliveredAt: json['deliveredAt'] != null
          ? DateTime.parse(json['deliveredAt'])
          : null,
      closedAt:
          json['closedAt'] != null ? DateTime.parse(json['closedAt']) : null,
      items: json['items'] != null
          ? (json['items'] as List).map((e) => OrderItem.fromJson(e)).toList()
          : [],
      photos: json['photos'] != null
          ? (json['photos'] as List).map((e) => OrderPhoto.fromJson(e)).toList()
          : [],
    );
  }

  String get statusLabel {
    switch (status) {
      case 'received':
        return 'Recibido';
      case 'diagnosing':
        return 'En Diagnóstico';
      case 'repairing':
        return 'En Reparación';
      case 'quality_check':
        return 'Control de Calidad';
      case 'ready':
        return 'Listo para Entrega';
      case 'delivered':
        return 'Entregado';
      case 'closed':
        return 'Cerrado';
      default:
        return status;
    }
  }
}

class OrderItem {
  final String id;
  final String description;
  final int qty;
  final double unitPrice;
  final double total;

  OrderItem({
    required this.id,
    required this.description,
    required this.qty,
    required this.unitPrice,
    required this.total,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'],
      description: json['description'],
      qty: json['qty'],
      unitPrice: double.tryParse('${json['unitPrice']}') ?? 0,
      total: double.tryParse('${json['total']}') ?? 0,
    );
  }
}

class OrderPhoto {
  final String id;
  final String photoUrl;
  final String? description;
  final String takenAtStage;
  final DateTime createdAt;

  OrderPhoto({
    required this.id,
    required this.photoUrl,
    this.description,
    this.takenAtStage = 'reception',
    required this.createdAt,
  });

  factory OrderPhoto.fromJson(Map<String, dynamic> json) {
    return OrderPhoto(
      id: json['id'],
      photoUrl: json['photoUrl'],
      description: json['description'],
      takenAtStage: json['takenAtStage'] ?? 'reception',
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
