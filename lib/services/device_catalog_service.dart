import 'api_service.dart';

class DeviceTypeModel {
  final String id;
  final String name;
  final String? icon;
  final int sortOrder;

  DeviceTypeModel({
    required this.id,
    required this.name,
    this.icon,
    this.sortOrder = 0,
  });

  factory DeviceTypeModel.fromJson(Map<String, dynamic> json) {
    return DeviceTypeModel(
      id: json['id'],
      name: json['name'],
      icon: json['icon'],
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
}

class DeviceBrandModel {
  final String id;
  final String name;
  final String? deviceTypeId;
  final int sortOrder;

  DeviceBrandModel({
    required this.id,
    required this.name,
    this.deviceTypeId,
    this.sortOrder = 0,
  });

  factory DeviceBrandModel.fromJson(Map<String, dynamic> json) {
    return DeviceBrandModel(
      id: json['id'],
      name: json['name'],
      deviceTypeId: json['deviceTypeId'],
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
}

class DeviceCatalogService {
  final ApiService _api = ApiService();

  Future<List<DeviceTypeModel>> getTypes() async {
    final res = await _api.dio.get('/device-catalog/types');
    return (res.data as List).map((e) => DeviceTypeModel.fromJson(e)).toList();
  }

  Future<List<DeviceBrandModel>> getBrands({String? deviceTypeId}) async {
    final params = <String, dynamic>{};
    if (deviceTypeId != null) params['deviceTypeId'] = deviceTypeId;
    final res =
        await _api.dio.get('/device-catalog/brands', queryParameters: params);
    return (res.data as List)
        .map((e) => DeviceBrandModel.fromJson(e))
        .toList();
  }

  Future<DeviceTypeModel> createType(String name, {String? icon}) async {
    final res = await _api.dio
        .post('/device-catalog/types', data: {'name': name, 'icon': icon});
    return DeviceTypeModel.fromJson(res.data);
  }

  Future<DeviceBrandModel> createBrand(String name,
      {String? deviceTypeId}) async {
    final res = await _api.dio.post('/device-catalog/brands',
        data: {'name': name, 'deviceTypeId': deviceTypeId});
    return DeviceBrandModel.fromJson(res.data);
  }

  Future<void> deleteType(String id) async {
    await _api.dio.delete('/device-catalog/types/$id');
  }

  Future<void> deleteBrand(String id) async {
    await _api.dio.delete('/device-catalog/brands/$id');
  }

  Future<void> seedDefaults() async {
    await _api.dio.post('/device-catalog/seed');
  }
}
