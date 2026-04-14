import 'dart:convert';
import 'dart:io';
import '../models/service_order.dart';
import '../blocs/orders/orders_bloc.dart';
import 'api_service.dart';

class OrderService {
  final ApiService _api = ApiService();

  Future<List<ServiceOrder>> getOrders({
    String? status,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;

    final response = await _api.dio.get('/orders', queryParameters: params);
    return (response.data as List)
        .map((e) => ServiceOrder.fromJson(e))
        .toList();
  }

  Future<ServiceOrder> getOrder(String id) async {
    final response = await _api.dio.get('/orders/$id');
    return ServiceOrder.fromJson(response.data);
  }

  Future<ServiceOrder> createOrder({
    required String customerId,
    required List<EquipmentData> equipments,
    List<File>? photos,
  }) async {
    // Send first device as flat fields (always works with any backend version)
    final eq = equipments[0];
    final data = <String, dynamic>{
      'customerId': customerId,
      'deviceType': eq.deviceType,
      'deviceBrand': eq.deviceBrand,
      'deviceModel': eq.deviceModel,
      'problemReported': eq.problemReported,
    };
    if (eq.deviceSerial != null) data['deviceSerial'] = eq.deviceSerial;
    if (eq.deviceColor != null) data['deviceColor'] = eq.deviceColor;
    if (eq.accessories != null) data['accessories'] = eq.accessories;
    if (eq.technicianId != null) data['technicianId'] = eq.technicianId;

    // Create order
    final response = await _api.dio.post('/orders', data: data);
    final order = ServiceOrder.fromJson(response.data);

    // Upload photos for first device
    final firstPhotos = photos ?? (eq.photos != null && eq.photos!.isNotEmpty ? eq.photos! : null);
    if (firstPhotos != null) {
      for (final photo in firstPhotos) {
        try {
          final bytes = await photo.readAsBytes();
          final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          await _api.dio.post('/orders/${order.id}/photos', data: {
            'photoUrl': b64,
            'stage': 'reception',
          });
        } catch (_) {}
      }
    }

    // If multi-device, upload remaining device photos too
    if (equipments.length > 1) {
      for (int i = 1; i < equipments.length; i++) {
        final extra = equipments[i];
        if (extra.photos != null && extra.photos!.isNotEmpty) {
          for (final photo in extra.photos!) {
            try {
              final bytes = await photo.readAsBytes();
              final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
              await _api.dio.post('/orders/${order.id}/photos', data: {
                'photoUrl': b64,
                'description': '${extra.deviceType} ${extra.deviceBrand} ${extra.deviceModel}',
                'stage': 'reception',
              });
            } catch (_) {}
          }
        }
      }
    }

    return order;
  }

  Future<ServiceOrder> updateStatus(String orderId, String status,
      {String? notes}) async {
    final response = await _api.dio.patch('/orders/$orderId/status', data: {
      'status': status,
      'notes': notes,
    });
    return ServiceOrder.fromJson(response.data);
  }

  Future<ServiceOrder> updateEquipmentStatus(
      String orderId, String equipmentId, String status,
      {String? notes}) async {
    final response = await _api.dio
        .patch('/orders/$orderId/equipments/$equipmentId/status', data: {
      'status': status,
      'notes': notes,
    });
    return ServiceOrder.fromJson(response.data);
  }

  Future<ServiceOrder> addDiagnosis(
    String orderId, {
    required String diagnosis,
    double? laborCost,
    List<Map<String, dynamic>>? items,
  }) async {
    final response = await _api.dio.post('/orders/$orderId/diagnosis', data: {
      'diagnosis': diagnosis,
      'laborCost': laborCost,
      'items': items,
    });
    return ServiceOrder.fromJson(response.data);
  }

  Future<ServiceOrder> addEquipmentDiagnosis(
    String orderId,
    String equipmentId, {
    required String diagnosis,
    double? laborCost,
  }) async {
    final response = await _api.dio
        .patch('/orders/$orderId/equipments/$equipmentId/diagnosis', data: {
      'diagnosis': diagnosis,
      'laborCost': laborCost,
    });
    return ServiceOrder.fromJson(response.data);
  }

  Future<void> addPhoto(String orderId, File photo,
      {String? description, String stage = 'reception'}) async {
    final bytes = await photo.readAsBytes();
    final base64Photo = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    await _api.dio.post('/orders/$orderId/photos', data: {
      'photoUrl': base64Photo,
      'description': description,
      'stage': stage,
    });
  }

  Future<List<OrderPhoto>> getPhotos(String orderId) async {
    final response = await _api.dio.get('/orders/$orderId/photos');
    return (response.data as List)
        .map((e) => OrderPhoto.fromJson(e))
        .toList();
  }
}
