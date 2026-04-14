import 'dart:convert';
import 'dart:io';
import '../models/service_order.dart';
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

  Future<List<ServiceOrder>> getGroupedOrders(String groupId) async {
    final response = await _api.dio.get('/orders/group/$groupId');
    return (response.data as List)
        .map((e) => ServiceOrder.fromJson(e))
        .toList();
  }

  Future<ServiceOrder> createOrder({
    required String customerId,
    required String deviceType,
    required String deviceBrand,
    required String deviceModel,
    required String problemReported,
    String? deviceSerial,
    String? deviceImei,
    String? deviceColor,
    List<String>? accessories,
    String? technicianId,
    List<File>? photos,
    String? groupId,
  }) async {
    final data = {
      'customerId': customerId,
      'deviceType': deviceType,
      'deviceBrand': deviceBrand,
      'deviceModel': deviceModel,
      'problemReported': problemReported,
      'deviceSerial': deviceSerial,
      'deviceImei': deviceImei,
      'deviceColor': deviceColor,
      'accessories': accessories,
      'technicianId': technicianId,
      'groupId': groupId,
    };

    // Create order first WITHOUT photos
    final response = await _api.dio.post('/orders', data: data);
    final order = ServiceOrder.fromJson(response.data);

    // Upload photos separately (one by one to avoid payload too large)
    if (photos != null && photos.isNotEmpty) {
      for (final photo in photos) {
        try {
          final bytes = await photo.readAsBytes();
          final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          await _api.dio.post('/orders/${order.id}/photos', data: {
            'photoUrl': b64,
            'stage': 'reception',
          });
        } catch (_) {
          // Continue even if one photo fails
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
