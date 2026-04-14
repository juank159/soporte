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

/// Holds all data for one device being added to the order
class _DeviceEntry {
  String typeName;
  String? typeIcon;
  String brandName;
  String model;
  String serial;
  String? color;
  List<String> accessories;
  String problem;
  List<File> photos;
  String? technicianId;

  _DeviceEntry({
    required this.typeName,
    this.typeIcon,
    required this.brandName,
    required this.model,
    required this.serial,
    this.color,
    required this.accessories,
    required this.problem,
    required this.photos,
    this.technicianId,
  });

  String get summary => '$typeName $brandName $model';
}

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
  bool _loadingCatalog = true;

  // Current device being edited
  DeviceTypeModel? _selectedType;
  DeviceBrandModel? _selectedBrand;
  final _deviceModelCtrl = TextEditingController();
  final _deviceSerialCtrl = TextEditingController();
  final _deviceColorCtrl = TextEditingController();
  final _accessoriesCtrl = TextEditingController();
  final _problemCtrl = TextEditingController();
  final List<File> _photos = [];
  String? _selectedTechnicianId;

  // List of devices added
  final List<_DeviceEntry> _devices = [];

  // Technician assignment
  List<Map<String, dynamic>> _technicians = [];

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Maximo 4 fotos por equipo'),
        backgroundColor: AppTheme.accentOrange,
      ));
      return;
    }
    final isDesktop = Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;

    ImageSource? source;
    if (isDesktop) {
      source = ImageSource.gallery;
    } else {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppTheme.surfaceColor,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt_rounded,
                    color: AppTheme.accentCyan),
                title: Text('Tomar foto',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded,
                    color: AppTheme.accentPurple),
                title: Text('Galeria',
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
          else if (_newPhoneCtrl.text.trim().isEmpty)
            error = 'Ingrese el telefono';
        }
        break;
      case 1: // Devices - must have at least one
        if (_devices.isEmpty) {
          error = 'Agregue al menos un equipo';
        }
        break;
      case 2: // Confirm - always valid
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

  /// Validates current device form and adds it to the list
  bool _addCurrentDevice() {
    if (_selectedType == null) {
      _showError('Seleccione el tipo de equipo');
      return false;
    }
    if (_selectedBrand == null) {
      _showError('Seleccione la marca');
      return false;
    }
    if (_deviceModelCtrl.text.trim().isEmpty) {
      _showError('Ingrese el modelo');
      return false;
    }
    if (_deviceSerialCtrl.text.trim().isEmpty) {
      _showError('Ingrese el serial / IMEI');
      return false;
    }
    if (_accessoriesCtrl.text.trim().isEmpty) {
      _showError('Ingrese los accesorios');
      return false;
    }
    if (_problemCtrl.text.trim().isEmpty) {
      _showError('Describa el problema del equipo');
      return false;
    }

    final accessories = _accessoriesCtrl.text.trim().isNotEmpty
        ? _accessoriesCtrl.text.split(',').map((e) => e.trim()).toList()
        : <String>[];

    setState(() {
      _devices.add(_DeviceEntry(
        typeName: _selectedType!.name,
        typeIcon: _selectedType!.icon,
        brandName: _selectedBrand!.name,
        model: _deviceModelCtrl.text.trim(),
        serial: _deviceSerialCtrl.text.trim(),
        color: _deviceColorCtrl.text.trim().isNotEmpty
            ? _deviceColorCtrl.text.trim()
            : null,
        accessories: accessories,
        problem: _problemCtrl.text.trim(),
        photos: List<File>.from(_photos),
        technicianId: _selectedTechnicianId,
      ));
      _clearDeviceForm();
    });
    return true;
  }

  void _clearDeviceForm() {
    _selectedType = null;
    _selectedBrand = null;
    _deviceModelCtrl.clear();
    _deviceSerialCtrl.clear();
    _deviceColorCtrl.clear();
    _accessoriesCtrl.clear();
    _problemCtrl.clear();
    _photos.clear();
    _selectedTechnicianId = null;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.accentOrange,
    ));
  }

  Future<void> _createOrders() async {
    String customerId;

    if (_customerMode == 2) {
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
        if (mounted) _showError('Error con cliente express');
        return;
      }
    } else if (_customerMode == 1) {
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
        if (mounted) _showError('Error al crear cliente');
        return;
      }
    } else {
      if (_selectedCustomer == null) {
        _showError('Seleccione un cliente');
        return;
      }
      customerId = _selectedCustomer!.id;
    }

    if (!mounted) return;

    if (_devices.length == 1) {
      // Single device - use simple create
      final d = _devices[0];
      context.read<OrdersBloc>().add(
        OrderCreateRequested(
          customerId: customerId,
          deviceType: d.typeName,
          deviceBrand: d.brandName,
          deviceModel: d.model,
          problemReported: d.problem,
          deviceSerial: d.serial,
          deviceColor: d.color,
          accessories: d.accessories.isNotEmpty ? d.accessories : null,
          technicianId: d.technicianId,
          photos: d.photos.isNotEmpty ? d.photos : null,
        ),
      );
    } else {
      // Multiple devices - use grouped create
      final deviceDataList = _devices.map((d) => DeviceData(
        deviceType: d.typeName,
        deviceBrand: d.brandName,
        deviceModel: d.model,
        problemReported: d.problem,
        deviceSerial: d.serial,
        deviceColor: d.color,
        accessories: d.accessories.isNotEmpty ? d.accessories : null,
        photos: d.photos.isNotEmpty ? d.photos : null,
        technicianId: d.technicianId,
      )).toList();

      context.read<OrdersBloc>().add(
        OrderCreateMultipleRequested(
          customerId: customerId,
          devices: deviceDataList,
        ),
      );
    }
  }

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
            Icon(Icons.check_circle_rounded,
                color: AppTheme.accentGreen, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Orden creada',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 18)),
                  Text(order.orderNumber,
                      style: TextStyle(
                          color: AppTheme.accentCyan, fontSize: 14)),
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
                Center(
                    child: TicketPreviewWidget(
                        order: order, tenant: tenant)),
                const SizedBox(height: 16),
                if (!printerConnected)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              AppTheme.accentOrange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.print_disabled_rounded,
                            color: AppTheme.accentOrange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Impresora no conectada. Configure una en el menu.',
                              style: TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                    context.read<OrdersBloc>().add(OrdersLoadRequested());
                  },
                  child: const Text('Cerrar'),
                ),
              ),
              if (printerConnected)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final success =
                          await _printerService.printReceptionTicket(
                        order: order,
                        tenant: tenant,
                      );
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? 'Ticket impreso'
                                : 'Error al imprimir'),
                            backgroundColor: success
                                ? AppTheme.accentGreen
                                : AppTheme.accentRed,
                          ),
                        );
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        context
                            .read<OrdersBloc>()
                            .add(OrdersLoadRequested());
                      }
                    },
                    icon: Icon(Icons.print_rounded, size: 18),
                    label: Text('Imprimir'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showMultipleTicketDialog(
      List<ServiceOrder> orders, String groupId) async {
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
            Icon(Icons.check_circle_rounded,
                color: AppTheme.accentGreen, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${orders.length} ordenes creadas',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 18)),
                  Text(
                      orders.map((o) => o.orderNumber).join(', '),
                      style: TextStyle(
                          color: AppTheme.accentCyan, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show summary of all devices
                ...orders.map((order) => GlassCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      borderColor:
                          AppTheme.accentCyan.withValues(alpha: 0.3),
                      child: Row(
                        children: [
                          Icon(_getTypeIcon(null),
                              color: AppTheme.accentCyan, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.orderNumber,
                                  style: TextStyle(
                                    color: AppTheme.accentCyan,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${order.device?.type ?? ''} ${order.device?.brand ?? ''} ${order.device?.model ?? ''}',
                                  style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 12),
                                ),
                                Text(
                                  order.problemReported,
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                if (!printerConnected)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              AppTheme.accentOrange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.print_disabled_rounded,
                            color: AppTheme.accentOrange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Impresora no conectada.',
                              style: TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                    context.read<OrdersBloc>().add(OrdersLoadRequested());
                  },
                  child: const Text('Cerrar'),
                ),
              ),
              if (printerConnected)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      int printed = 0;
                      for (final order in orders) {
                        final ok =
                            await _printerService.printReceptionTicket(
                          order: order,
                          tenant: tenant,
                        );
                        if (ok) printed++;
                      }
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                                '$printed/${orders.length} tickets impresos'),
                            backgroundColor: printed > 0
                                ? AppTheme.accentGreen
                                : AppTheme.accentRed,
                          ),
                        );
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        context
                            .read<OrdersBloc>()
                            .add(OrdersLoadRequested());
                      }
                    },
                    icon: Icon(Icons.print_rounded, size: 18),
                    label: Text('Imprimir todos'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nueva Orden'),
        actions: [
          if (_devices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: Icon(Icons.devices_rounded,
                    size: 16, color: AppTheme.accentCyan),
                label: Text('${_devices.length} equipo(s)',
                    style: TextStyle(fontSize: 12)),
              ),
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
        child: BlocListener<OrdersBloc, OrdersState>(
          listener: (context, state) {
            if (state is OrderCreated) {
              _showTicketDialog(state.order);
            }
            if (state is OrdersMultipleCreated) {
              _showMultipleTicketDialog(state.orders, state.groupId);
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
              data: Theme.of(context)
                  .copyWith(canvasColor: AppTheme.surfaceColor),
              child: Stepper(
                currentStep: _currentStep,
                onStepContinue: () {
                  if (_currentStep == 1) {
                    // On device step, must have at least one device
                    if (_devices.isEmpty) {
                      _showError(
                          'Agregue al menos un equipo antes de continuar');
                      return;
                    }
                    setState(() => _currentStep++);
                  } else if (_currentStep < 2) {
                    if (!_validateStep(_currentStep)) return;
                    setState(() => _currentStep++);
                  } else {
                    _createOrders();
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
                              _currentStep == 2
                                  ? 'Crear ${_devices.length > 1 ? '${_devices.length} Ordenes' : 'Orden'}'
                                  : 'Siguiente',
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
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
                    title: Text('Cliente',
                        style: TextStyle(color: AppTheme.textPrimary)),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0
                        ? StepState.complete
                        : StepState.indexed,
                    content: _clientStep(),
                  ),
                  Step(
                    title: Text(
                        'Equipos${_devices.isNotEmpty ? ' (${_devices.length})' : ''}',
                        style: TextStyle(color: AppTheme.textPrimary)),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1
                        ? StepState.complete
                        : StepState.indexed,
                    content: _devicesStep(),
                  ),
                  Step(
                    title: Text('Confirmar',
                        style: TextStyle(color: AppTheme.textPrimary)),
                    isActive: _currentStep >= 2,
                    content: _confirmStep(),
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
              avatar: Icon(Icons.person_add_rounded, size: 16),
              label: Text('Nuevo cliente'),
              selected: _customerMode == 1,
              onSelected: (_) => setState(() => _customerMode = 1),
            ),
            ChoiceChip(
              avatar: Icon(Icons.flash_on_rounded, size: 16),
              label: Text('Express'),
              selected: _customerMode == 2,
              onSelected: (_) => setState(() => _customerMode = 2),
            ),
          ],
        ),
        SizedBox(height: 16),

        if (_customerMode == 0) ...[
          TextField(
            controller: _customerSearchCtrl,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Buscar por nombre, cedula o telefono',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: _searchCustomers,
          ),
          if (_searchingCustomers)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(color: AppTheme.accentCyan),
            ),
          ..._customerResults.map(
            (c) => ListTile(
              title: Text(c.fullName,
                  style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text('${c.idNumber} - ${c.phone}',
                  style: TextStyle(color: AppTheme.textSecondary)),
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
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppTheme.accentGreen),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_selectedCustomer!.fullName} | ${_selectedCustomer!.phone}',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],

        if (_customerMode == 1) ...[
          _field(_newNameCtrl, 'Nombre completo *', required: true),
          _field(_newIdCtrl, 'Cedula / NIT *', required: true),
          _field(_newPhoneCtrl, 'Telefono *',
              required: true, keyboard: TextInputType.phone),
          _field(_newEmailCtrl, 'Email (opcional)',
              keyboard: TextInputType.emailAddress),
        ],

        if (_customerMode == 2)
          GlassCard(
            borderColor: AppTheme.accentOrange.withValues(alpha: 0.4),
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.flash_on_rounded, color: AppTheme.accentOrange),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Servicio Express',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      Text(
                          'Se creara un registro anonimo con trazabilidad.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- STEP 2: DEVICES ----
  Widget _devicesStep() {
    if (_loadingCatalog) {
      return Center(
          child: CircularProgressIndicator(color: AppTheme.accentCyan));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show already added devices
        if (_devices.isNotEmpty) ...[
          Text('Equipos agregados',
              style: TextStyle(
                  color: AppTheme.accentGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._devices.asMap().entries.map((e) => _deviceCard(e.key, e.value)),
          const SizedBox(height: 16),
          Divider(color: AppTheme.dividerColor),
          const SizedBox(height: 16),
        ],

        // Form for adding new device
        Text(
          _devices.isEmpty
              ? 'Datos del equipo'
              : 'Agregar otro equipo',
          style: TextStyle(
              color: AppTheme.accentCyan,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),

        // Device type
        Text('Tipo de equipo',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _deviceTypes.map((t) {
            final selected = _selectedType?.id == t.id;
            return ChoiceChip(
              avatar: Icon(_getTypeIcon(t.icon),
                  size: 16,
                  color: selected
                      ? AppTheme.accentCyan
                      : AppTheme.textSecondary),
              label: Text(t.name),
              selected: selected,
              onSelected: (_) => setState(() {
                _selectedType = t;
                _selectedBrand = null;
              }),
            );
          }).toList(),
        ),
        SizedBox(height: 20),

        // Brand
        if (_selectedType != null) ...[
          Text('Marca',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
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
        _field(_accessoriesCtrl, 'Accesorios *',
            required: true, hint: 'Cargador, Funda, Audifonos'),

        // Problem for THIS device
        const SizedBox(height: 8),
        TextFormField(
          controller: _problemCtrl,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: 'Problema de este equipo *',
            hintText: 'Describa el problema reportado...',
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 12),

        // Photos for this device
        Text('Fotos del equipo (opcional)',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ..._photos.asMap().entries.map(
              (e) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(e.value,
                        width: 70, height: 70, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _photos.removeAt(e.key)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: AppTheme.accentRed,
                            shape: BoxShape.circle),
                        child: Icon(Icons.close,
                            color: Colors.white, size: 14),
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
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.add_a_photo_rounded,
                      color: AppTheme.textSecondary, size: 20),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Technician (optional)
        if (_technicians.isNotEmpty) ...[
          Text('Tecnico (opcional)',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('Sin asignar'),
                selected: _selectedTechnicianId == null,
                onSelected: (_) =>
                    setState(() => _selectedTechnicianId = null),
              ),
              ..._technicians.map((t) {
                final selected = _selectedTechnicianId == t['id'];
                return ChoiceChip(
                  label: Text(t['fullName'] as String),
                  selected: selected,
                  onSelected: (_) => setState(
                      () => _selectedTechnicianId = t['id'] as String),
                );
              }),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Add device button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              if (_addCurrentDevice()) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      'Equipo #${_devices.length} agregado. Puede agregar mas o continuar.'),
                  backgroundColor: AppTheme.accentGreen,
                  duration: Duration(seconds: 2),
                ));
              }
            },
            icon: Icon(Icons.add_rounded),
            label: Text(_devices.isEmpty
                ? 'Agregar equipo'
                : 'Agregar otro equipo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPurple,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceCard(int index, _DeviceEntry device) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      borderColor: AppTheme.accentCyan.withValues(alpha: 0.4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.accentCyan.withValues(alpha: 0.2),
            child: Text('${index + 1}',
                style: TextStyle(
                    color: AppTheme.accentCyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.summary,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text('S/N: ${device.serial}',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
                Text(device.problem,
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (device.photos.isNotEmpty)
                  Text('${device.photos.length} foto(s)',
                      style: TextStyle(
                          color: AppTheme.accentOrange, fontSize: 10)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _devices.removeAt(index)),
            icon: Icon(Icons.delete_rounded,
                color: AppTheme.accentRed, size: 20),
            tooltip: 'Eliminar equipo',
          ),
        ],
      ),
    );
  }

  // ---- STEP 3: CONFIRM ----
  Widget _confirmStep() {
    final clientName = _customerMode == 2
        ? 'Cliente Express'
        : _customerMode == 1
            ? _newNameCtrl.text.trim()
            : _selectedCustomer?.fullName ?? '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.person_rounded,
                  color: AppTheme.accentBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cliente',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                    Text(clientName,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Text(
            '${_devices.length} equipo(s) a registrar:',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),

        ..._devices.asMap().entries.map((e) {
          final d = e.value;
          return GlassCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            borderColor: AppTheme.accentCyan.withValues(alpha: 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          AppTheme.accentCyan.withValues(alpha: 0.2),
                      child: Text('${e.key + 1}',
                          style: TextStyle(
                              color: AppTheme.accentCyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(d.summary,
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _confirmRow('Serial', d.serial),
                if (d.color != null) _confirmRow('Color', d.color!),
                _confirmRow('Accesorios', d.accessories.join(', ')),
                _confirmRow('Problema', d.problem),
                if (d.photos.isNotEmpty)
                  _confirmRow('Fotos', '${d.photos.length}'),
              ],
            ),
          );
        }),

        if (_devices.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GlassCard(
              borderColor: AppTheme.accentPurple.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.accentPurple, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se crearan ${_devices.length} ordenes individuales agrupadas. Cada equipo tendra su propio diagnostico y flujo de reparacion.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 38, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontSize: 11)),
          ),
        ],
      ),
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
      padding: EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        style: TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(labelText: label, hintText: hint),
        keyboardType: keyboard,
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
