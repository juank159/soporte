import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/glass_card.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.dio.get('/users');
      setState(() {
        _users = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Administrador';
      case 'supervisor':
        return 'Supervisor';
      case 'technician':
        return 'Tecnico';
      case 'reception':
        return 'Recepcion';
      default:
        return role;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return AppTheme.accentCyan;
      case 'supervisor':
        return AppTheme.accentBlue;
      case 'technician':
        return AppTheme.accentPurple;
      case 'reception':
        return AppTheme.accentGreen;
      default:
        return AppTheme.textSecondary;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'supervisor':
        return Icons.supervisor_account_rounded;
      case 'technician':
        return Icons.engineering_rounded;
      case 'reception':
        return Icons.support_agent_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'technician';
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: AppTheme.accentCyan),
              SizedBox(width: 10),
              Text('Nuevo usuario',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 18)),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration:
                        const InputDecoration(labelText: 'Nombre completo *'),
                    validator: (v) =>
                        v?.isEmpty == true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(labelText: 'Email *'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        v?.isEmpty == true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration:
                        const InputDecoration(labelText: 'Contrasena *'),
                    obscureText: true,
                    validator: (v) => v != null && v.length < 4
                        ? 'Minimo 4 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Rol',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['supervisor', 'technician', 'reception']
                        .map((role) => ChoiceChip(
                              avatar: Icon(_roleIcon(role),
                                  size: 16, color: _roleColor(role)),
                              label: Text(_roleLabel(role)),
                              selected: selectedRole == role,
                              onSelected: (_) =>
                                  setDialogState(() => selectedRole = role),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await _api.dio.post('/users', data: {
                    'fullName': nameCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'password': passCtrl.text,
                    'role': selectedRole,
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppTheme.accentRed,
                    ));
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final isActive = user['isActive'] as bool;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isActive ? 'Suspender usuario' : 'Activar usuario',
            style: const TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          isActive
              ? '${user['fullName']} no podra iniciar sesion.'
              : '${user['fullName']} podra iniciar sesion nuevamente.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isActive ? AppTheme.accentRed : AppTheme.accentGreen,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isActive ? 'Suspender' : 'Activar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _api.dio.put('/users/${user['id']}', data: {
        'isActive': !isActive,
      });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isActive ? 'Usuario suspendido' : 'Usuario activado'),
          backgroundColor:
              isActive ? AppTheme.accentOrange : AppTheme.accentGreen,
        ));
      }
    } catch (_) {}
  }

  Future<void> _changeRole(Map<String, dynamic> user) async {
    String currentRole = user['role'] as String;

    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selected = currentRole;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Cambiar rol de ${user['fullName']}',
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: ['supervisor', 'technician', 'reception']
                  .map((role) => RadioListTile<String>(
                        title: Row(
                          children: [
                            Icon(_roleIcon(role),
                                color: _roleColor(role), size: 20),
                            const SizedBox(width: 8),
                            Text(_roleLabel(role),
                                style: const TextStyle(
                                    color: AppTheme.textPrimary)),
                          ],
                        ),
                        value: role,
                        groupValue: selected,
                        activeColor: AppTheme.accentCyan,
                        onChanged: (v) =>
                            setDialogState(() => selected = v!),
                      ))
                  .toList(),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );

    if (newRole == null || newRole == currentRole) return;

    try {
      await _api.dio.put('/users/${user['id']}', data: {'role': newRole});
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Rol actualizado a ${_roleLabel(newRole)}'),
          backgroundColor: AppTheme.accentGreen,
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion de usuarios')),
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
                child:
                    CircularProgressIndicator(color: AppTheme.accentCyan))
            : RefreshIndicator(
                color: AppTheme.accentCyan,
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  itemBuilder: (context, i) {
                    final user = _users[i];
                    final role = user['role'] as String;
                    final isActive = user['isActive'] as bool;
                    final color = _roleColor(role);

                    return GlassCard(
                      borderColor: isActive
                          ? color.withValues(alpha: 0.25)
                          : AppTheme.accentRed.withValues(alpha: 0.2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Icon(_roleIcon(role),
                                color: color, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        user['fullName'] as String,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isActive
                                              ? AppTheme.textPrimary
                                              : AppTheme.textSecondary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accentRed
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text('Suspendido',
                                            style: TextStyle(
                                                color: AppTheme.accentRed,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(user['email'] as String,
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12),
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                StatusBadge(
                                    label: _roleLabel(role), color: color),
                              ],
                            ),
                          ),
                          // Actions menu (not for admins editing themselves)
                          if (role != 'admin')
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded,
                                  color: AppTheme.textSecondary),
                              onSelected: (action) {
                                switch (action) {
                                  case 'role':
                                    _changeRole(user);
                                    break;
                                  case 'toggle':
                                    _toggleActive(user);
                                    break;
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'role',
                                  child: Row(
                                    children: [
                                      Icon(Icons.swap_horiz_rounded,
                                          size: 18),
                                      SizedBox(width: 8),
                                      Text('Cambiar rol'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Row(
                                    children: [
                                      Icon(
                                        isActive
                                            ? Icons.block_rounded
                                            : Icons.check_circle_rounded,
                                        size: 18,
                                        color: isActive
                                            ? AppTheme.accentRed
                                            : AppTheme.accentGreen,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(isActive
                                          ? 'Suspender'
                                          : 'Activar'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.person_add_rounded),
      ),
    );
  }
}
