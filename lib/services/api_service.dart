import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio dio;
  SharedPreferences? _prefs;

  ApiService._internal() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _read('access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _read('access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final response = await dio.fetch(error.requestOptions);
            return handler.resolve(response);
          }
        }
        return handler.next(error);
      },
    ));
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<String?> _read(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  Future<void> _write(String key, String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, value);
  }

  Future<void> _delete(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _read('refresh_token');
      if (refreshToken == null) return false;

      final response = await Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
      )).post('/auth/refresh', data: {'refreshToken': refreshToken});

      await _write('access_token', response.data['accessToken']);
      await _write('refresh_token', response.data['refreshToken']);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _write('access_token', accessToken);
    await _write('refresh_token', refreshToken);
  }

  Future<void> clearTokens() async {
    await _delete('access_token');
    await _delete('refresh_token');
    await _delete('tenant_slug');
  }

  Future<String?> getToken() => _read('access_token');

  Future<void> saveTenantSlug(String slug) async {
    await _write('tenant_slug', slug);
  }

  Future<String?> getTenantSlug() => _read('tenant_slug');
}
