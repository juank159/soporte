import '../models/customer.dart';
import 'api_service.dart';

class CustomerService {
  final ApiService _api = ApiService();

  Future<List<Customer>> getCustomers({String? search}) async {
    final params = <String, dynamic>{};
    if (search != null && search.isNotEmpty) params['search'] = search;

    final response = await _api.dio.get('/customers', queryParameters: params);
    return (response.data as List)
        .map((e) => Customer.fromJson(e))
        .toList();
  }

  Future<Customer> getCustomer(String id) async {
    final response = await _api.dio.get('/customers/$id');
    return Customer.fromJson(response.data);
  }

  Future<Customer> createCustomer({
    required String fullName,
    required String idNumber,
    required String phone,
    String? email,
    String? notes,
  }) async {
    final response = await _api.dio.post('/customers', data: {
      'fullName': fullName,
      'idNumber': idNumber,
      'phone': phone,
      'email': email,
      'notes': notes,
    });
    return Customer.fromJson(response.data);
  }

  Future<Customer> updateCustomer(String id, Map<String, dynamic> data) async {
    final response = await _api.dio.put('/customers/$id', data: data);
    return Customer.fromJson(response.data);
  }
}
