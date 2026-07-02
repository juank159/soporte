import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/service_order.dart';
import '../blocs/orders/orders_bloc.dart';
import 'api_service.dart';

class OrdersPage {
  final List<ServiceOrder> orders;
  final int total;
  final int page;
  final int totalPages;
  OrdersPage({required this.orders, required this.total, required this.page, required this.totalPages});
}

class OrderService {
  final ApiService _api = ApiService();

  Future<OrdersPage> getOrders({
    String? status,
    String? search,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (status != null) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;

    final response = await _api.dio.get('/orders', queryParameters: params);
    final json = response.data as Map<String, dynamic>;
    return OrdersPage(
      orders: (json['data'] as List).map((e) => ServiceOrder.fromJson(e)).toList(),
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      totalPages: json['totalPages'] ?? 1,
    );
  }

  Future<ServiceOrder> getOrder(String id) async {
    final response = await _api.dio.get('/orders/$id');
    return ServiceOrder.fromJson(response.data);
  }

  Future<ServiceOrder> createOrder({
    required String customerId,
    required List<EquipmentData> equipments,
    List<File>? photos,
    bool requiresClientSignature = true,
  }) async {
    final eq = equipments[0];
    final data = <String, dynamic>{
      'customerId': customerId,
      'deviceType': eq.deviceType,
      'deviceBrand': eq.deviceBrand,
      'deviceModel': eq.deviceModel,
      'problemReported': eq.problemReported,
      'requiresClientSignature': requiresClientSignature,
    };
    if (eq.deviceSerial != null) data['deviceSerial'] = eq.deviceSerial;
    if (eq.deviceColor != null) data['deviceColor'] = eq.deviceColor;
    if (eq.accessories != null) data['accessories'] = eq.accessories;
    if (eq.technicianId != null) data['technicianId'] = eq.technicianId;
    if (eq.unlockPassword != null) data['unlockPassword'] = eq.unlockPassword;
    if (eq.unlockPin != null) data['unlockPin'] = eq.unlockPin;
    if (eq.unlockPattern != null) data['unlockPattern'] = eq.unlockPattern;

    // If multiple equipments, send the full array for the new backend
    if (equipments.length > 1) {
      data['equipments'] = equipments.map((e) {
        final m = <String, dynamic>{
          'deviceType': e.deviceType,
          'deviceBrand': e.deviceBrand,
          'deviceModel': e.deviceModel,
          'problemReported': e.problemReported,
        };
        if (e.deviceSerial != null) m['deviceSerial'] = e.deviceSerial;
        if (e.deviceColor != null) m['deviceColor'] = e.deviceColor;
        if (e.accessories != null) m['accessories'] = e.accessories;
        if (e.technicianId != null) m['technicianId'] = e.technicianId;
        if (e.unlockPassword != null) m['unlockPassword'] = e.unlockPassword;
        if (e.unlockPin != null) m['unlockPin'] = e.unlockPin;
        if (e.unlockPattern != null) m['unlockPattern'] = e.unlockPattern;
        return m;
      }).toList();
    }

    // Try creating - if backend rejects 'equipments', retry without it
    dynamic response;
    try {
      response = await _api.dio.post('/orders', data: data);
    } catch (e) {
      if (data.containsKey('equipments')) {
        debugPrint('Backend rejected equipments field, retrying without...');
        data.remove('equipments');
        response = await _api.dio.post('/orders', data: data);
      } else {
        rethrow;
      }
    }

    final order = ServiceOrder.fromJson(response.data);

    // Upload photos
    for (int i = 0; i < equipments.length; i++) {
      final device = equipments[i];
      final devicePhotos = (i == 0 && photos != null) ? photos : device.photos;
      if (devicePhotos != null && devicePhotos.isNotEmpty) {
        for (final photo in devicePhotos) {
          try {
            final bytes = await photo.readAsBytes();
            final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
            await _api.dio.post('/orders/${order.id}/photos', data: {
              'photoUrl': b64,
              'description': equipments.length > 1
                  ? '${device.deviceType} ${device.deviceBrand} ${device.deviceModel}'
                  : null,
              'stage': 'reception',
            });
          } catch (_) {}
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

  Future<void> deleteOrder(String orderId) async {
    await _api.dio.delete('/orders/$orderId');
  }
}
