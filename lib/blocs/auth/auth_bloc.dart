import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/date_utils.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;
  final String tenantSlug;

  AuthLoginRequested({
    required this.email,
    required this.password,
    required this.tenantSlug,
  });

  @override
  List<Object?> get props => [email, password, tenantSlug];
}

class AuthLogoutRequested extends AuthEvent {}

class AuthCheckRequested extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;
  AuthAuthenticated(this.user);

  @override
  List<Object?> get props => [user.id];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService = AuthService();

  AuthBloc() : super(AuthInitial()) {
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthCheckRequested>(_onCheckRequested);
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await _authService.login(
        event.email,
        event.password,
        event.tenantSlug,
      );
      // Save user for session persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode({
        'id': user.id,
        'email': user.email,
        'fullName': user.fullName,
        'role': user.role,
        'tenantId': user.tenantId,
      }));

      // Load tenant timezone + register device
      try {
        final api = ApiService();
        final res = await api.dio.get('/tenants/me');
        final tz = res.data['timezone'] ?? 'America/Bogota';
        AppDateUtils.configure(tz);
      } catch (_) {}

      await _registerDevice();

      emit(AuthAuthenticated(user));
    } catch (e) {
      debugPrint('LOGIN ERROR: $e');
      debugPrint('LOGIN ERROR TYPE: ${e.runtimeType}');
      emit(AuthError(_getErrorMessage(e)));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    emit(AuthUnauthenticated());
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (!isLoggedIn) {
      emit(AuthUnauthenticated());
      return;
    }

    // Restore saved user data
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData == null) {
      emit(AuthUnauthenticated());
      return;
    }

    try {
      final data = jsonDecode(userData) as Map<String, dynamic>;
      final user = User.fromJson(data);

      // Verify token is still valid
      try {
        final api = ApiService();
        final res = await api.dio.get('/tenants/me');
        final tz = res.data['timezone'] ?? 'America/Bogota';
        AppDateUtils.configure(tz);
      } catch (_) {
        // Token expired, clear and force login
        await _authService.logout();
        await prefs.remove('user_data');
        emit(AuthUnauthenticated());
        return;
      }

      await _registerDevice();

      emit(AuthAuthenticated(user));
    } catch (_) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _registerDevice() async {
    try {
      final api = ApiService();
      final prefs = await SharedPreferences.getInstance();

      // Generate unique device ID (persistent across restarts)
      var deviceId = prefs.getString('device_unique_id');
      if (deviceId == null) {
        deviceId = '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
        await prefs.setString('device_unique_id', deviceId);
      }

      // Detect platform
      String platform;
      String deviceName;
      if (kIsWeb) {
        platform = 'Web';
        deviceName = 'Navegador Web';
      } else if (Platform.isAndroid) {
        platform = 'Android';
        deviceName = 'Android';
      } else if (Platform.isIOS) {
        platform = 'iOS';
        deviceName = 'iPhone/iPad';
      } else if (Platform.isMacOS) {
        platform = 'macOS';
        deviceName = 'Mac';
      } else if (Platform.isWindows) {
        platform = 'Windows';
        deviceName = 'Windows PC';
      } else if (Platform.isLinux) {
        platform = 'Linux';
        deviceName = 'Linux PC';
      } else {
        platform = 'Otro';
        deviceName = 'Dispositivo';
      }

      await api.dio.post('/subscription/register-device', data: {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
      });
      debugPrint('DEVICE: Registered $deviceName ($platform) id=$deviceId');
    } catch (e) {
      debugPrint('DEVICE: Registration failed: $e');
    }
  }

  String _getErrorMessage(dynamic error) {
    if (error.toString().contains('404')) {
      return 'Empresa no encontrada';
    }
    if (error.toString().contains('401')) {
      return 'Credenciales incorrectas';
    }
    if (error.toString().contains('SocketException') ||
        error.toString().contains('Connection refused')) {
      return 'No se puede conectar al servidor';
    }
    return 'Error al iniciar sesión';
  }
}
