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
    final data = <String, dynamic>{
      'customerId': customerId,
    };

    if (equipments.length == 1) {
      // Single device - send flat fields for backward compatibility
      final eq = equipments[0];
      data['deviceType'] = eq.deviceType;
      data['deviceBrand'] = eq.deviceBrand;
      data['deviceModel'] = eq.deviceModel;
      data['problemReported'] = eq.problemReported;
      data['deviceSerial'] = eq.deviceSerial;
      data['deviceColor'] = eq.deviceColor;
      data['accessories'] = eq.accessories;
      data['technicianId'] = eq.technicianId;
    } else {
      // Multiple devices - send equipments array
      data['equipments'] = equipments.map((eq) => {
        'deviceType': eq.deviceType,
        'deviceBrand': eq.deviceBrand,
        'deviceModel': eq.deviceModel,
        'problemReported': eq.problemReported,
        'deviceSerial': eq.deviceSerial,
        'deviceColor': eq.deviceColor,
        'accessories': eq.accessories,
        'technicianId': eq.technicianId,
      }).toList();
    }

    // Create order
    final response = await _api.dio.post('/orders', data: data);
    final order = ServiceOrder.fromJson(response.data);

    // Upload photos separately for single device
    if (equipments.length == 1 && photos != null && photos.isNotEmpty) {
      for (final photo in photos) {
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

    // Upload photos for each equipment in multi-device
    if (equipments.length > 1) {
      for (final eq in equipments) {
        if (eq.photos != null && eq.photos!.isNotEmpty) {
          for (final photo in eq.photos!) {
            try {
              final bytes = await photo.readAsBytes();
              final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
              await _api.dio.post('/orders/${order.id}/photos', data: {
                'photoUrl': b64,
                'description': '${eq.deviceType} ${eq.deviceBrand} ${eq.deviceModel}',
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
