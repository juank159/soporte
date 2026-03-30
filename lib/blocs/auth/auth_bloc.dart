import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
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
      // Load tenant timezone
      try {
        final api = ApiService();
        final res = await api.dio.get('/tenants/me');
        final tz = res.data['timezone'] ?? 'America/Bogota';
        AppDateUtils.configure(tz);
        debugPrint('TIMEZONE: Configured to $tz');
      } catch (_) {}

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
    emit(AuthUnauthenticated());
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (isLoggedIn) {
      // For now, emit unauthenticated to force login
      // In production, decode the JWT to get user info
      emit(AuthUnauthenticated());
    } else {
      emit(AuthUnauthenticated());
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
