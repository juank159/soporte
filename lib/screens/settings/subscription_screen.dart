import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/date_utils.dart';
import '../../services/api_service.dart';
import '../../widgets/glass_card.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _sub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.dio.get('/subscription');
      setState(() { _sub = res.data; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _deactivateDevice(String sessionId) async {
    try {
      await _api.dio.delete('/subscription/devices/$sessionId');
      _load();
    } catch (_) {}
  }

  Color _planColor(String p) {
    switch (p) { case 'pro': return AppTheme.accentPurple; case 'enterprise': return AppTheme.accentCyan; default: return AppTheme.accentBlue; }
  }
  String _planLabel(String p) {
    switch (p) { case 'pro': return 'Profesional'; case 'enterprise': return 'Empresarial'; default: return 'Basico'; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suscripcion')),
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppTheme.gradientPrimary)),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
            : _sub == null
                ? const Center(child: Text('Error al cargar', style: TextStyle(color: AppTheme.textSecondary)))
                : RefreshIndicator(color: AppTheme.accentCyan, onRefresh: _load, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: _buildContent())),
      ),
    );
  }

  Widget _buildContent() {
    final plan = _sub!['plan'] as String? ?? 'basic';
    final color = _planColor(plan);
    final maxDevices = _sub!['maxDevices'] ?? 3;
    final activeDevices = _sub!['activeDevices'] ?? 0;
    final maxUsers = _sub!['maxUsers'] ?? 5;
    final activeUsers = _sub!['activeUsers'] ?? 0;
    final daysRemaining = _sub!['daysRemaining'] ?? 0;
    final totalDays = _sub!['totalDays'] ?? 30;
    final isExpired = _sub!['isExpired'] ?? false;
    final devices = (_sub!['devices'] as List?) ?? [];
    final expiresAt = _sub!['expiresAt'] != null ? DateTime.tryParse(_sub!['expiresAt']) : null;

    return Column(
      children: [
        // Plan header
        GlassCard(
          borderColor: isExpired ? AppTheme.accentRed.withValues(alpha: 0.5) : color.withValues(alpha: 0.4),
          child: Column(
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.workspace_premium_rounded, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Plan ${_planLabel(plan)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                    if (isExpired) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.accentRed.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: const Text('EXPIRADO', style: TextStyle(color: AppTheme.accentRed, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text('Ordenes ilimitadas', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ])),
              ]),
              const SizedBox(height: 20),

              // Progress bars
              _progressItem(
                'Dispositivos',
                activeDevices, maxDevices,
                '$activeDevices de $maxDevices conectados',
                activeDevices >= maxDevices ? AppTheme.accentRed : AppTheme.accentCyan,
                Icons.devices_rounded,
              ),
              const SizedBox(height: 14),
              _progressItem(
                'Usuarios',
                activeUsers, maxUsers,
                '$activeUsers de $maxUsers registrados',
                activeUsers >= maxUsers ? AppTheme.accentOrange : AppTheme.accentGreen,
                Icons.group_rounded,
              ),
              const SizedBox(height: 14),
              _progressItem(
                'Vigencia del plan',
                daysRemaining, totalDays,
                isExpired
                    ? 'EXPIRADO - No puede crear ordenes. Renueve su plan.'
                    : daysRemaining == totalDays
                        ? 'Plan activo - Inicia hoy, vence en $totalDays dias'
                        : daysRemaining <= 5
                            ? 'ATENCION: Solo quedan $daysRemaining dias!'
                            : '$daysRemaining dias restantes de $totalDays',
                isExpired
                    ? AppTheme.accentRed
                    : daysRemaining <= 5
                        ? AppTheme.accentRed
                        : daysRemaining <= 10
                            ? AppTheme.accentOrange
                            : AppTheme.accentGreen,
                Icons.calendar_today_rounded,
                inverted: true,
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Vence: ${AppDateUtils.format(expiresAt, includeTime: false)}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ],
          ),
        ),

        // Devices
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.devices_rounded, color: AppTheme.accentCyan, size: 20),
              const SizedBox(width: 8),
              const Text('Dispositivos conectados', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary, fontSize: 15)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (activeDevices >= maxDevices ? AppTheme.accentRed : AppTheme.accentCyan).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$activeDevices/$maxDevices', style: TextStyle(
                  color: activeDevices >= maxDevices ? AppTheme.accentRed : AppTheme.accentCyan,
                  fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                child: const Center(child: Column(children: [
                  Icon(Icons.devices_other_rounded, size: 36, color: AppTheme.textSecondary),
                  SizedBox(height: 8),
                  Text('No hay dispositivos activos', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  Text('Al iniciar sesion desde un dispositivo aparecera aqui', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ])),
              )
            else
              ...devices.map((d) {
                final lastActive = d['lastActive'] != null ? DateTime.tryParse(d['lastActive']) : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_platformIcon(d['platform'] ?? ''), color: AppTheme.accentCyan, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d['deviceName'] ?? 'Dispositivo', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('${d['platform'] ?? ''} | ${lastActive != null ? AppDateUtils.format(lastActive) : '-'}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.accentRed, size: 18),
                      onPressed: () => _deactivateDevice(d['id']),
                      tooltip: 'Desconectar',
                    ),
                  ]),
                );
              }),
          ]),
        ),

        // Plans
        const SizedBox(height: 4),
        const Align(alignment: Alignment.centerLeft,
          child: Text('Planes disponibles', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15))),
        const SizedBox(height: 8),
        _planCard('basic', 3, 5, plan == 'basic'),
        _planCard('pro', 5, 20, plan == 'pro'),
        _planCard('enterprise', 50, 100, plan == 'enterprise'),
      ],
    );
  }

  Widget _progressItem(String label, int current, int max, String subtitle, Color color, IconData icon, {bool inverted = false}) {
    final progress = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    final rightText = inverted ? '$current dias' : '$current/$max';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
        const Spacer(),
        Text(rightText, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: AppTheme.dividerColor,
          color: color,
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(color: color, fontSize: 11)),
    ]);
  }

  Widget _planCard(String plan, int devices, int users, bool isCurrent) {
    final color = _planColor(plan);
    return GlassCard(
      borderColor: isCurrent ? color.withValues(alpha: 0.5) : AppTheme.dividerColor,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(Icons.workspace_premium_rounded, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_planLabel(plan), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
          Text('$devices dispositivos | $users usuarios | Ordenes ilimitadas',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ])),
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Text('Actual', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }

  IconData _platformIcon(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('android')) return Icons.phone_android_rounded;
    if (p.contains('ios') || p.contains('iphone')) return Icons.phone_iphone_rounded;
    if (p.contains('macos') || p.contains('mac')) return Icons.laptop_mac_rounded;
    if (p.contains('windows')) return Icons.desktop_windows_rounded;
    if (p.contains('web')) return Icons.language_rounded;
    return Icons.devices_rounded;
  }
}
