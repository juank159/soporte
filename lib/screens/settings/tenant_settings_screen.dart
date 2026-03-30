import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/glass_card.dart';

class TenantSettingsScreen extends StatefulWidget {
  const TenantSettingsScreen({super.key});

  @override
  State<TenantSettingsScreen> createState() => _TenantSettingsScreenState();
}

class _TenantSettingsScreenState extends State<TenantSettingsScreen> {
  final ApiService _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _nitCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _warrantyDaysCtrl = TextEditingController();
  final _warrantyConditionsCtrl = TextEditingController();
  final _legalNoticeCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    _loadTenant();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nitCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _warrantyDaysCtrl.dispose();
    _warrantyConditionsCtrl.dispose();
    _legalNoticeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTenant() async {
    try {
      final res = await _api.dio.get('/tenants/me');
      final data = res.data as Map<String, dynamic>;
      _nameCtrl.text = data['name'] ?? '';
      _nitCtrl.text = data['nit'] ?? '';
      _addressCtrl.text = data['address'] ?? '';
      _phoneCtrl.text = data['phone'] ?? '';
      _emailCtrl.text = data['email'] ?? '';
      _warrantyDaysCtrl.text = '${data['warrantyDays'] ?? 30}';
      _warrantyConditionsCtrl.text = data['warrantyConditions'] ?? '';
      _legalNoticeCtrl.text = data['legalNotice'] ?? '';
      _logoUrl = data['logoUrl'];
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.dio.put('/tenants/me', data: {
        'logoUrl': _logoUrl,
        'name': _nameCtrl.text.trim(),
        'nit': _nitCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'warrantyDays': int.tryParse(_warrantyDaysCtrl.text.trim()) ?? 30,
        'warrantyConditions': _warrantyConditionsCtrl.text.trim(),
        'legalNotice': _legalNoticeCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Configuracion guardada'),
          ]),
          backgroundColor: AppTheme.accentGreen,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuracion del negocio'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accentCyan))
                : const Icon(Icons.save_rounded),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.gradientPrimary,
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.accentCyan))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Logo
                    GlassCard(
                      borderColor: AppTheme.accentOrange.withValues(alpha: 0.3),
                      child: Column(
                        children: [
                          const Row(children: [
                            Icon(Icons.image_rounded,
                                color: AppTheme.accentOrange, size: 20),
                            SizedBox(width: 8),
                            Text('Logo del negocio',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentOrange,
                                    fontSize: 15)),
                          ]),
                          const SizedBox(height: 12),
                          const Text(
                            'Este logo aparecera en el acta de entrega.',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          if (_logoUrl != null && _logoUrl!.startsWith('data:'))
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                base64Decode(_logoUrl!.split(',').last),
                                height: 80,
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picker = ImagePicker();
                                  final img = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      maxWidth: 600,
                                      imageQuality: 80);
                                  if (img == null) return;
                                  final bytes = await File(img.path).readAsBytes();
                                  setState(() {
                                    _logoUrl =
                                        'data:image/png;base64,${base64Encode(bytes)}';
                                  });
                                },
                                icon: const Icon(Icons.upload_rounded, size: 18),
                                label: const Text('Subir logo'),
                              ),
                              if (_logoUrl != null) ...[
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _logoUrl = null),
                                  child: const Text('Quitar',
                                      style:
                                          TextStyle(color: AppTheme.accentRed)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Datos principales
                    GlassCard(
                      borderColor: AppTheme.accentCyan.withValues(alpha: 0.3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.business_rounded,
                                color: AppTheme.accentCyan, size: 20),
                            SizedBox(width: 8),
                            Text('Datos del negocio',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentCyan,
                                    fontSize: 15)),
                          ]),
                          const SizedBox(height: 16),
                          _field(_nameCtrl, 'Nombre del negocio',
                              Icons.store_rounded),
                          _field(_nitCtrl, 'NIT', Icons.badge_rounded),
                          _field(_addressCtrl, 'Direccion',
                              Icons.location_on_rounded),
                          _field(_phoneCtrl, 'Telefono',
                              Icons.phone_rounded,
                              keyboard: TextInputType.phone),
                          _field(_emailCtrl, 'Email',
                              Icons.email_rounded,
                              keyboard: TextInputType.emailAddress),
                        ],
                      ),
                    ),

                    // Garantia
                    GlassCard(
                      borderColor: AppTheme.accentGreen.withValues(alpha: 0.3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.verified_rounded,
                                color: AppTheme.accentGreen, size: 20),
                            SizedBox(width: 8),
                            Text('Garantia',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentGreen,
                                    fontSize: 15)),
                          ]),
                          const SizedBox(height: 16),
                          _field(_warrantyDaysCtrl,
                              'Dias de garantia por defecto',
                              Icons.calendar_today_rounded,
                              keyboard: TextInputType.number),
                          _fieldMultiline(_warrantyConditionsCtrl,
                              'Condiciones de garantia',
                              'Ej: La garantia no cubre dano por liquidos...'),
                        ],
                      ),
                    ),

                    // Aviso legal
                    GlassCard(
                      borderColor: AppTheme.accentPurple.withValues(alpha: 0.3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.gavel_rounded,
                                color: AppTheme.accentPurple, size: 20),
                            SizedBox(width: 8),
                            Text('Aviso legal',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentPurple,
                                    fontSize: 15)),
                          ]),
                          const SizedBox(height: 16),
                          _fieldMultiline(_legalNoticeCtrl,
                              'Texto legal para el ticket',
                              'Ej: No nos hacemos responsables por equipos no reclamados despues de 30 dias...'),
                          const Text(
                            'Este texto aparecera al final del ticket de recepcion.',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),

                    // Save button (mobile)
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Guardar cambios',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: AppTheme.textPrimary),
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
      ),
    );
  }

  Widget _fieldMultiline(
      TextEditingController ctrl, String label, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: AppTheme.textPrimary),
        maxLines: 3,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}
