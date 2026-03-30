import 'package:flutter/foundation.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<User> login(String email, String password, String tenantSlug) async {
    debugPrint('AUTH: Attempting login - email=$email, tenant=$tenantSlug');
    final response = await _api.dio.post('/auth/login', data: {
      'email': email,
      'password': password,
      'tenantSlug': tenantSlug,
    });
    debugPrint('AUTH: Response status=${response.statusCode}');

    await _api.saveTokens(
      response.data['accessToken'],
      response.data['refreshToken'],
    );
    await _api.saveTenantSlug(tenantSlug);

    return User.fromJson(response.data['user']);
  }

  Future<void> logout() async {
    await _api.clearTokens();
  }

  Future<bool> isLoggedIn() async {
    final token = await _api.getToken();
    return token != null;
  }
}
