import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../config/theme.dart';
import '../../widgets/glass_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tenantController = TextEditingController();
  bool _obscurePassword = true;

  // Saved accounts
  List<Map<String, String>> _savedAccounts = [];
  String _lastTenant = '';

  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _slideController.forward();
    });
  }

  Future<void> _loadSavedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('saved_login_accounts');
    final tenant = prefs.getString('last_tenant') ?? '';
    if (data != null) {
      final list = jsonDecode(data) as List;
      setState(() {
        _savedAccounts = list.map((e) => Map<String, String>.from(e)).toList();
        _lastTenant = tenant;
        if (_lastTenant.isNotEmpty) {
          _tenantController.text = _lastTenant;
        }
      });
    }
  }

  Future<void> _saveAccount(String email, String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    // Remove if already exists
    _savedAccounts.removeWhere((a) => a['email'] == email && a['tenant'] == tenant);
    // Add to top
    _savedAccounts.insert(0, {'email': email, 'tenant': tenant});
    // Keep max 5
    if (_savedAccounts.length > 5) _savedAccounts = _savedAccounts.sublist(0, 5);
    await prefs.setString('saved_login_accounts', jsonEncode(_savedAccounts));
    await prefs.setString('last_tenant', tenant);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _tenantController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _login() {
    if (_formKey.currentState!.validate()) {
      final email = _emailController.text.trim();
      final tenant = _tenantController.text.trim().toLowerCase();
      _saveAccount(email, tenant);
      context.read<AuthBloc>().add(AuthLoginRequested(
            email: email,
            password: _passwordController.text,
            tenantSlug: tenant,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(state.message)),
                  ],
                ),
                backgroundColor: AppTheme.accentRed,
              ),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.gradientPrimary,
            ),
          ),
          child: Stack(
            children: [
              // Animated background circles
              ..._buildBackgroundOrbs(size),

              // Content
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 48 : 24,
                    vertical: 24,
                  ),
                  child: isWide
                      ? _buildWideLayout(size)
                      : _buildNarrowLayout(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBackgroundOrbs(Size size) {
    return [
      Positioned(
        top: -100,
        right: -100,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            width: 350,
            height: 350,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.accentCyan.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: -80,
        left: -80,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.accentPurple.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildWideLayout(Size size) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Row(
        children: [
          // Left - Branding
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _buildBranding(large: true),
            ),
          ),
          const SizedBox(width: 48),
          // Right - Form
          SizedBox(
            width: min(420, size.width * 0.4),
            child: SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _buildLoginForm(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: _buildBranding(large: false),
          ),
          const SizedBox(height: 32),
          SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _buildLoginForm(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranding({required bool large}) {
    return Column(
      crossAxisAlignment:
          large ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: AppTheme.gradientAccent),
          ),
          child: Icon(
            Icons.construction_rounded,
            size: large ? 48 : 40,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 20),
        GradientText(
          'Servicio Tecnico',
          style: TextStyle(
            fontSize: large ? 36 : 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sistema de gestion inteligente',
          style: TextStyle(
            fontSize: large ? 18 : 15,
            color: AppTheme.textSecondary,
            letterSpacing: 0.5,
          ),
          textAlign: large ? TextAlign.start : TextAlign.center,
        ),
        if (large) ...[
          const SizedBox(height: 32),
          _featureItem(Icons.speed_rounded, 'Control total de ordenes'),
          _featureItem(Icons.devices_rounded, 'Multiplataforma'),
          _featureItem(Icons.cloud_sync_rounded, 'Sincronizacion en la nube'),
          _featureItem(Icons.shield_rounded, 'Datos seguros por empresa'),
        ],
      ],
    );
  }

  Widget _featureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.accentCyan),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return GlassCard(
      padding: const EdgeInsets.all(28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Iniciar sesion',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ingresa tus credenciales para continuar',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 28),

            // Saved accounts quick select
            if (_savedAccounts.isNotEmpty) ...[
              const Text('Cuentas recientes',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _savedAccounts.length,
                  itemBuilder: (context, i) {
                    final acc = _savedAccounts[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: CircleAvatar(
                          radius: 12,
                          backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.15),
                          child: Text(
                            (acc['email'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(
                                color: AppTheme.accentCyan, fontSize: 10),
                          ),
                        ),
                        label: Text(
                          acc['email'] ?? '',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          setState(() {
                            _emailController.text = acc['email'] ?? '';
                            _tenantController.text = acc['tenant'] ?? '';
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Tenant
            TextFormField(
              controller: _tenantController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Empresa',
                hintText: 'slug de la empresa',
                prefixIcon: Icon(Icons.business_rounded),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Ingrese la empresa' : null,
            ),
            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Correo electronico',
                prefixIcon: Icon(Icons.email_rounded),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Ingrese su correo' : null,
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Contrasena',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Ingrese su contrasena' : null,
              onFieldSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 28),

            // Login button
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final isLoading = state is AuthLoading;
                return SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: isLoading
                            ? [AppTheme.cardColor, AppTheme.cardColor]
                            : AppTheme.gradientAccent,
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: AppTheme.accentCyan,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Ingresar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
