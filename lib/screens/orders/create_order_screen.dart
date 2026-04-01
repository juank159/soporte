//lib/screens/orders/create_order_screen.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../blocs/orders/orders_bloc.dart';
import '../../models/service_order.dart';
import '../../config/theme.dart';
import '../../models/customer.dart';
import '../../services/customer_service.dart';
import '../../services/device_catalog_service.dart';
import '../../services/api_service.dart';
import '../../services/ticket_printer_service.dart';
import '../../models/tenant.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/ticket_preview_widget.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  // Customer mode: 0=search, 1=new, 2=express
  int _customerMode = 0;
  Customer? _selectedCustomer;
  final _customerSearchCtrl = TextEditingController();
  List<Customer> _customerResults = [];
  bool _searchingCustomers = false;
  final _newNameCtrl = TextEditingController();
  final _newIdCtrl = TextEditingController();
  final _newPhoneCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();

  // Device catalog
  List<DeviceTypeModel> _deviceTypes = [];
  List<DeviceBrandModel> _allBrands = [];
  DeviceTypeModel? _selectedType;
  DeviceBrandModel? _selectedBrand;
  final _deviceModelCtrl = TextEditingController();
  final _deviceSerialCtrl = TextEditingController();
  final _deviceColorCtrl = TextEditingController();
  final _accessoriesCtrl = TextEditingController();
  bool _loadingCatalog = true;

  // Technician assignment
  List<Map<String, dynamic>> _technicians = [];
  String? _selectedTechnicianId;

  // Problem & photos
  final _problemCtrl = TextEditingController();
  final List<File> _photos = [];
  final _imagePicker = ImagePicker();

  final _customerService = CustomerService();
  final _catalogService = DeviceCatalogService();
  final _api = ApiService();
  final _printerService = TicketPrinterService();
  Tenant? _tenant;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadTechnicians();
    _loadTenant();
  }

  Future<void> _loadTenant() async {
    try {
      final res = await _api.dio.get('/tenants/me');
      _tenant = Tenant.fromJson(res.data);
    } catch (_) {}
  }

  Future<void> _loadCatalog() async {
    try {
      _deviceTypes = await _catalogService.getTypes();
      _allBrands = await _catalogService.getBrands();
      if (_deviceTypes.isEmpty) {
        await _catalogService.seedDefaults();
        _deviceTypes = await _catalogService.getTypes();
        _allBrands = await _catalogService.getBrands();
      }
    } catch (_) {}
    setState(() => _loadingCatalog = false);
  }

  Future<void> _loadTechnicians() async {
    try {
      final res = await _api.dio.get('/users');
      final users = res.data as List;
      setState(() {
        _technicians = users
            .where(
              (u) => u['role'] == 'technician' || u['role'] == 'supervisor',
            )
            .cast<Map<String, dynamic>>()
            .toList();
      });
    } catch (_) {}
  }

  List<DeviceBrandModel> get _filteredBrands {
    if (_selectedType == null) return _allBrands;
    return _allBrands
        .where((b) => b.deviceTypeId == _selectedType!.id)
        .toList();
  }

  @override
  void dispose() {
    _customerSearchCtrl.dispose();
    _newNameCtrl.dispose();
    _newIdCtrl.dispose();
    _newPhoneCtrl.dispose();
    _newEmailCtrl.dispose();
    _deviceModelCtrl.dispose();
    _deviceSerialCtrl.dispose();
    _deviceColorCtrl.dispose();
    _accessoriesCtrl.dispose();
    _problemCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchCustomers(String q) async {
    if (q.length < 2) return;
    setState(() => _searchingCustomers = true);
    try {
      _customerResults = await _customerService.getCustomers(search: q);
    } catch (_) {}
    setState(() => _searchingCustomers = false);
  }

  static const _maxPhotos = 4;

  Future<void> _takePhoto() async {
    if (_photos.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Maximo 4 fotos por orden'),
        backgroundColor: AppTheme.accentOrange,
      ));
      return;
    }
    final isDesktop = Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;

    ImageSource? source;
    if (isDesktop) {
      // Desktop: only gallery (no camera via image_picker)
      source = ImageSource.gallery;
    } else {
      // Mobile: show camera/gallery picker
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppTheme.surfaceColor,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: AppTheme.accentCyan),
                title: const Text('Tomar foto',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: AppTheme.accentPurple),
                title: const Text('Galeria',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    }
    if (source == null) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (picked != null) setState(() => _photos.add(File(picked.path)));
    } catch (e) {
      debugPrint('Photo pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al seleccionar imagen: $e'),
          backgroundColor: AppTheme.accentRed,
        ));
      }
    }
  }

  bool _validateStep(int step) {
    String? error;
    switch (step) {
      case 0: // Client
        if (_customerMode == 0 && _selectedCustomer == null) {
          error = 'Seleccione un cliente';
        } else if (_customerMode == 1) {
          if (_newNameCtrl.text.trim().isEmpty) error = 'Ingrese el nombre';
          else if (_newIdCtrl.text.trim().isEmpty) error = 'Ingrese la cedula';
          else if (_newPhoneCtrl.text.trim().isEmpty) error = 'Ingrese el telefono';
        }
        break;
      case 1: // Device
        if (_selectedType == null) error = 'Seleccione el tipo de equipo';
        else if (_selectedBrand == null) error = 'Seleccione la marca';
        else if (_deviceModelCtrl.text.trim().isEmpty) error = 'Ingrese el modelo';
        else if (_deviceSerialCtrl.text.trim().isEmpty) error = 'Ingrese el serial / IMEI';
        else if (_accessoriesCtrl.text.trim().isEmpty) error = 'Ingrese los accesorios entregados';
        break;
      case 2: // Photos - optional, always valid
        break;
      case 3: // Problem
        if (_problemCtrl.text.trim().isEmpty) error = 'Describa el problema';
        break;
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppTheme.accentOrange,
      ));
      return false;
    }
    return true;
  }

  Future<void> _createOrder() async {
    if (_formKey.currentState?.validate() != true) return;

    String customerId;

    if (_customerMode == 2) {
      // Express: use existing "Cliente Express" (created with tenant)
      try {
        final customers =
            await _customerService.getCustomers(search: 'EXPRESS');
        final express =
            customers.where((c) => c.idNumber == 'EXPRESS').firstOrNull;
        if (express != null) {
          customerId = express.id;
        } else {
          final c = await _customerService.createCustomer(
            fullName: 'Cliente Express',
            idNumber: 'EXPRESS',
            phone: '0000000000',
          );
          customerId = c.id;
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error con cliente express'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        return;
      }
    } else if (_customerMode == 1) {
      // New customer
      try {
        final c = await _customerService.createCustomer(
          fullName: _newNameCtrl.text.trim(),
          idNumber: _newIdCtrl.text.trim(),
          phone: _newPhoneCtrl.text.trim(),
          email: _newEmailCtrl.text.trim().isNotEmpty
              ? _newEmailCtrl.text.trim()
              : null,
        );
        customerId = c.id;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al crear cliente'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        return;
      }
    } else {
      if (_selectedCustomer == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Seleccione un cliente')));
        return;
      }
      customerId = _selectedCustomer!.id;
    }

    final accessories = _accessoriesCtrl.text.trim().isNotEmpty
        ? _accessoriesCtrl.text.split(',').map((e) => e.trim()).toList()
        : <String>[];

    if (!mounted) return;
    context.read<OrdersBloc>().add(
      OrderCreateRequested(
        customerId: customerId,
        deviceType: _selectedType?.name ?? '',
        deviceBrand: _selectedBrand?.name ?? '',
        deviceModel: _deviceModelCtrl.text.trim(),
        problemReported: _problemCtrl.text.trim(),
        deviceSerial: _deviceSerialCtrl.text.trim(),
        deviceColor: _deviceColorCtrl.text.trim().isNotEmpty
            ? _deviceColorCtrl.text.trim()
            : null,
        accessories: accessories.isNotEmpty ? accessories : null,
        technicianId: _selectedTechnicianId,
        photos: _photos.isNotEmpty ? _photos : null,
      ),
    );
  }

  @override
  Future<void> _showTicketDialog(ServiceOrder order) async {
    final tenant =
        _tenant ?? Tenant(id: '', name: 'Servicio Tecnico', slug: 'default');
    final printerConnected = await _printerService.hasSavedPrinter;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.accentGreen,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Orden creada',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
                  ),
                  Text(
                    order.orderNumber,
                    style: const TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ticket preview
                Center(
                  child: TicketPreviewWidget(order: order, tenant: tenant),
                ),
                const SizedBox(height: 16),
                if (!printerConnected)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.accentOrange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.print_disabled_rounded,
                          color: AppTheme.accentOrange,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Impresora no conectada. Configure una en el menu.',
                            style: TextStyle(
                              color: AppTheme.accentOrange,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              context.read<OrdersBloc>().add(OrdersLoadRequested());
            },
            child: const Text('Omitir'),
          ),
          if (printerConnected)
            ElevatedButton.icon(
              onPressed: () async {
                final success = await _printerService.printReceptionTicket(
                  order: order,
                  tenant: tenant,
                );
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        success ? 'Ticket impreso' : 'Error al imprimir',
                      ),
                      backgroundColor: success
                          ? AppTheme.accentGreen
                          : AppTheme.accentRed,
                    ),
                  );
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  context.read<OrdersBloc>().add(OrdersLoadRequested());
                }
              },
              icon: const Icon(Icons.print_rounded),
              label: const Text('Imprimir ticket'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva Orden')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.gradientPrimary,
          ),
        ),
        child: BlocListener<OrdersBloc, OrdersState>(
          listener: (context, state) {
            if (state is OrderCreated) {
              _showTicketDialog(state.order);
            }
            if (state is OrdersError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppTheme.accentRed,
                ),
              );
            }
          },
          child: Form(
            key: _formKey,
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(canvasColor: AppTheme.surfaceColor),
              child: Stepper(
                currentStep: _currentStep,
                onStepContinue: () {
                  if (!_validateStep(_currentStep)) return;
                  if (_currentStep < 3) {
                    setState(() => _currentStep++);
                  } else {
                    _createOrder();
                  }
                },
                onStepCancel: () {
                  if (_currentStep > 0) {
                    setState(() => _currentStep--);
                  } else {
                    Navigator.pop(context);
                  }
                },
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Row(
                      children: [
                        BlocBuilder<OrdersBloc, OrdersState>(
                          builder: (context, state) => ElevatedButton(
                            onPressed: state is OrdersLoading
                                ? null
                                : details.onStepContinue,
                            child: Text(
                              _currentStep == 3 ? 'Crear Orden' : 'Siguiente',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: Text(
                            _currentStep == 0 ? 'Cancelar' : 'Anterior',
                          ),
                        ),
                      ],
                    ),
                  );
                },
                steps: [
                  Step(
                    title: const Text(
                      'Cliente',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0
                        ? StepState.complete
                        : StepState.indexed,
                    content: _clientStep(),
                  ),
                  Step(
                    title: const Text(
                      'Equipo',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1
                        ? StepState.complete
                        : StepState.indexed,
                    content: _deviceStep(),
                  ),
                  Step(
                    title: const Text(
                      'Fotos',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    isActive: _currentStep >= 2,
                    state: _currentStep > 2
                        ? StepState.complete
                        : StepState.indexed,
                    content: _photosStep(),
                  ),
                  Step(
                    title: const Text(
                      'Problema',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    isActive: _currentStep >= 3,
                    content: _problemStep(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- STEP 1: CLIENT ----
  Widget _clientStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.search_rounded, size: 16),
              label: const Text('Buscar cliente'),
              selected: _customerMode == 0,
              onSelected: (_) => setState(() => _customerMode = 0),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.person_add_rounded, size: 16),
              label: const Text('Nuevo cliente'),
              selected: _customerMode == 1,
              onSelected: (_) => setState(() => _customerMode = 1),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.flash_on_rounded, size: 16),
              label: const Text('Express'),
              selected: _customerMode == 2,
              onSelected: (_) => setState(() => _customerMode = 2),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Mode 0: Search existing
        if (_customerMode == 0) ...[
          TextField(
            controller: _customerSearchCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre, cedula o telefono',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: _searchCustomers,
          ),
          if (_searchingCustomers)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(color: AppTheme.accentCyan),
            ),
          ..._customerResults.map(
            (c) => ListTile(
              title: Text(
                c.fullName,
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              subtitle: Text(
                '${c.idNumber} - ${c.phone}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              selected: _selectedCustomer?.id == c.id,
              onTap: () => setState(() {
                _selectedCustomer = c;
                _customerResults = [];
                _customerSearchCtrl.text = c.fullName;
              }),
            ),
          ),
          if (_selectedCustomer != null)
            GlassCard(
              borderColor: AppTheme.accentGreen.withValues(alpha: 0.4),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.accentGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_selectedCustomer!.fullName} | ${_selectedCustomer!.phone}',
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],

        // Mode 1: New customer
        if (_customerMode == 1) ...[
          _field(_newNameCtrl, 'Nombre completo *', required: true),
          _field(_newIdCtrl, 'Cedula / NIT *', required: true),
          _field(
            _newPhoneCtrl,
            'Telefono *',
            required: true,
            keyboard: TextInputType.phone,
          ),
          _field(
            _newEmailCtrl,
            'Email (opcional)',
            keyboard: TextInputType.emailAddress,
          ),
        ],

        // Mode 2: Express
        if (_customerMode == 2)
          GlassCard(
            borderColor: AppTheme.accentOrange.withValues(alpha: 0.4),
            padding: const EdgeInsets.all(14),
            child: const Row(
              children: [
                Icon(Icons.flash_on_rounded, color: AppTheme.accentOrange),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Servicio Express',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Se creara un registro anonimo con trazabilidad. El cliente no necesita dar sus datos.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- STEP 2: DEVICE ----
  Widget _deviceStep() {
    if (_loadingCatalog) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentCyan),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Device type selector
        const Text(
          'Tipo de equipo',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _deviceTypes.map((t) {
            final selected = _selectedType?.id == t.id;
            return ChoiceChip(
              avatar: Icon(
                _getTypeIcon(t.icon),
                size: 16,
                color: selected ? AppTheme.accentCyan : AppTheme.textSecondary,
              ),
              label: Text(t.name),
              selected: selected,
              onSelected: (_) => setState(() {
                _selectedType = t;
                _selectedBrand = null;
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Brand selector
        if (_selectedType != null) ...[
          const Text(
            'Marca',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filteredBrands.map((b) {
              final selected = _selectedBrand?.id == b.id;
              return ChoiceChip(
                label: Text(b.name),
                selected: selected,
                onSelected: (_) => setState(() => _selectedBrand = b),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],

        _field(_deviceModelCtrl, 'Modelo *', required: true),
        _field(_deviceSerialCtrl, 'Serial / IMEI *', required: true),
        _field(_deviceColorCtrl, 'Color (opcional)'),
        _field(
          _accessoriesCtrl,
          'Accesorios entregados *',
          required: true,
          hint: 'Cargador, Funda, Audifonos',
        ),
      ],
    );
  }

  // ---- STEP 3: PHOTOS ----
  Widget _photosStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Toma fotos del estado actual del equipo',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ..._photos.asMap().entries.map(
              (e) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      e.value,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _photos.removeAt(e.key)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppTheme.accentRed,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_photos.length < _maxPhotos)
            InkWell(
              onTap: _takePhoto,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_rounded,
                      color: AppTheme.textSecondary,
                      size: 24,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Agregar',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_photos.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Opcional pero recomendado',
              style: TextStyle(fontSize: 11, color: AppTheme.accentOrange),
            ),
          ),
      ],
    );
  }

  // ---- STEP 4: PROBLEM + TECHNICIAN ----
  Widget _problemStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _problemCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Descripcion del problema *',
            hintText: 'Describa el problema reportado...',
            alignLabelWithHint: true,
          ),
          maxLines: 4,
          validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
        ),
        const SizedBox(height: 20),

        // Technician assignment (optional)
        const Text(
          'Asignar tecnico (opcional)',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_technicians.isEmpty)
          const Text(
            'No hay tecnicos registrados',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Sin asignar'),
                selected: _selectedTechnicianId == null,
                onSelected: (_) => setState(() => _selectedTechnicianId = null),
              ),
              ..._technicians.map((t) {
                final selected = _selectedTechnicianId == t['id'];
                return ChoiceChip(
                  avatar: CircleAvatar(
                    radius: 12,
                    backgroundColor: selected
                        ? AppTheme.accentPurple
                        : AppTheme.surfaceColor,
                    child: Text(
                      (t['fullName'] as String)[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: selected ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  label: Text(t['fullName'] as String),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _selectedTechnicianId = t['id'] as String),
                );
              }),
            ],
          ),
      ],
    );
  }

  // ---- HELPERS ----
  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    TextInputType? keyboard,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(labelText: label, hintText: hint),
        keyboardType: keyboard,
        validator: required
            ? (v) => v?.isEmpty == true ? 'Requerido' : null
            : null,
      ),
    );
  }

  IconData _getTypeIcon(String? icon) {
    switch (icon) {
      case 'phone_android':
        return Icons.phone_android_rounded;
      case 'laptop':
        return Icons.laptop_rounded;
      case 'desktop_windows':
        return Icons.desktop_windows_rounded;
      case 'tablet':
        return Icons.tablet_rounded;
      case 'print':
        return Icons.print_rounded;
      case 'kitchen':
        return Icons.kitchen_rounded;
      case 'sports_esports':
        return Icons.sports_esports_rounded;
      default:
        return Icons.devices_rounded;
    }
  }
}
