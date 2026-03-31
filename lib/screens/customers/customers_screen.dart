import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/customers/customers_bloc.dart';
import '../../config/theme.dart';
import '../../models/customer.dart';
import '../../services/customer_service.dart';
import '../../widgets/glass_card.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<CustomersBloc>().add(CustomersLoadRequested());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showEditDialog(Customer c) {
    final nameCtrl = TextEditingController(text: c.fullName);
    final idCtrl = TextEditingController(text: c.idNumber);
    final phoneCtrl = TextEditingController(text: c.phone);
    final emailCtrl = TextEditingController(text: c.email ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.edit_rounded, color: AppTheme.accentCyan),
          const SizedBox(width: 10),
          Text('Editar ${c.fullName}',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 12),
            TextField(controller: idCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Cedula / NIT')),
            const SizedBox(height: 12),
            TextField(controller: phoneCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Telefono'),
                keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              try {
                await CustomerService().updateCustomer(c.id, {
                  'fullName': nameCtrl.text.trim(),
                  'idNumber': idCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                context.read<CustomersBloc>().add(CustomersLoadRequested());
              } catch (_) {}
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add_rounded, color: AppTheme.accentCyan),
            SizedBox(width: 10),
            Text('Nuevo Cliente',
                style: TextStyle(color: AppTheme.textPrimary)),
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
                  validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: idCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'Cedula / NIT *'),
                  validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Telefono *'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration:
                      const InputDecoration(labelText: 'Email (opcional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                context.read<CustomersBloc>().add(CustomerCreateRequested(
                      fullName: nameCtrl.text.trim(),
                      idNumber: idCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim().isNotEmpty
                          ? emailCtrl.text.trim()
                          : null,
                    ));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              context
                                  .read<CustomersBloc>()
                                  .add(CustomersLoadRequested());
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => context
                      .read<CustomersBloc>()
                      .add(CustomersLoadRequested(search: v)),
                ),
              ),
              const SizedBox(width: 10),
              FloatingActionButton.small(
                heroTag: 'add_customer',
                onPressed: _showCreateDialog,
                child: const Icon(Icons.person_add_rounded, size: 20),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: BlocConsumer<CustomersBloc, CustomersState>(
            listener: (context, state) {
              if (state is CustomerCreated) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.white),
                        const SizedBox(width: 8),
                        Text('${state.customer.fullName} creado'),
                      ],
                    ),
                    backgroundColor: AppTheme.accentGreen,
                  ),
                );
                context.read<CustomersBloc>().add(CustomersLoadRequested());
              }
            },
            builder: (context, state) {
              if (state is CustomersLoading) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.accentCyan));
              }

              if (state is CustomersLoaded) {
                if (state.customers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline_rounded,
                            size: 56,
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        const Text('Sin clientes',
                            style:
                                TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.customers.length,
                  itemBuilder: (context, index) {
                    final c = state.customers[index];
                    return GlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                AppTheme.accentCyan.withValues(alpha: 0.12),
                            child: Text(
                              c.fullName[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.accentCyan,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.fullName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary)),
                                const SizedBox(height: 2),
                                Text('CC ${c.idNumber}  |  ${c.phone}',
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          if (c.email != null)
                            Icon(Icons.email_outlined,
                                color: AppTheme.textSecondary
                                    .withValues(alpha: 0.5),
                                size: 18),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded,
                                color: AppTheme.textSecondary, size: 18),
                            onPressed: () => _showEditDialog(c),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}
