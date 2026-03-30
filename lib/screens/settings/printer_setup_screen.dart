import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ticket_printer_service.dart';
import '../../config/theme.dart';
import '../../widgets/glass_card.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen>
    with SingleTickerProviderStateMixin {
  final TicketPrinterService _printer = TicketPrinterService();
  late final TabController _tabController;
  final _hostCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '9100');
  final _nameCtrl = TextEditingController(text: 'Impresora Termica');
  bool _loading = false;
  bool _hasPrinter = false;
  String _printerName = '';
  String _printerType = '';
  int _connectionType = 0;

  List<Printer> _systemPrinters = [];
  bool _loadingPrinters = false;

  // A4 printer for actas
  String _a4PrinterName = '';
  bool _hasA4Printer = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedState();
    _loadA4Printer();
    _tabController.addListener(() {
      setState(() => _connectionType = _tabController.index);
      if (_tabController.index == 1) _detectSystemPrinters();
    });
  }

  Future<void> _loadA4Printer() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _a4PrinterName = prefs.getString('a4_printer_name') ?? '';
      _hasA4Printer = _a4PrinterName.isNotEmpty;
    });
  }

  Future<void> _selectA4Printer(Printer p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('a4_printer_name', p.name);
    await prefs.setString('a4_printer_url', p.url);
    setState(() {
      _a4PrinterName = p.name;
      _hasA4Printer = true;
    });
    _showResult(true, 'Impresora A4: ${p.name}');
  }

  Future<void> _clearA4Printer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('a4_printer_name');
    await prefs.remove('a4_printer_url');
    setState(() {
      _a4PrinterName = '';
      _hasA4Printer = false;
    });
  }

  Future<void> _loadSavedState() async {
    final has = await _printer.hasSavedPrinter;
    final name = await _printer.savedPrinterName;
    final type = await _printer.savedPrinterType;
    setState(() {
      _hasPrinter = has;
      _printerName = name ?? '';
      _printerType = type ?? '';
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _detectSystemPrinters() async {
    setState(() => _loadingPrinters = true);
    try {
      final printers = await Printing.listPrinters();
      setState(() {
        _systemPrinters = printers;
        _loadingPrinters = false;
      });
    } catch (e) {
      debugPrint('Error detecting printers: $e');
      setState(() => _loadingPrinters = false);
    }
  }

  Future<void> _connectTcp() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9100;
    if (host.isEmpty) return;

    setState(() => _loading = true);
    final ok =
        await _printer.connectTcp(host, port, name: _nameCtrl.text.trim());
    setState(() => _loading = false);
    if (ok) await _loadSavedState();
    _showResult(ok, 'TCP $host:$port');
  }

  Future<void> _disconnect() async {
    await _printer.disconnect();
    await _loadSavedState();
  }

  Future<void> _testPrint() async {
    setState(() => _loading = true);
    final ok = await _printer.printTestPage();
    setState(() {
      _loading = false;
      if (!ok) {} // Don't clear - just show error
    });
    _showResult(ok, 'prueba');
  }

  Future<void> _selectSystemPrinter(Printer sysPrinter) async {
    final ok = await _printer.connectSystem(sysPrinter);
    if (ok) await _loadSavedState();
    _showResult(ok, ok ? 'Configurada: ${sysPrinter.name}' : sysPrinter.name);
  }

  Future<void> _testSystemPrinter(Printer sysPrinter) async {
    try {
      final ticketBytes = await _printer.generateTestPdfBytes();
      await Printing.directPrintPdf(
        printer: sysPrinter,
        onLayout: (_) async => ticketBytes,
        name: 'Test Ticket',
      );
      if (mounted) _showResult(true, sysPrinter.name);
    } catch (e) {
      if (mounted) _showResult(false, '${sysPrinter.name}: $e');
    }
  }

  void _showResult(bool ok, String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: Colors.white),
        const SizedBox(width: 8),
        Expanded(child: Text(ok ? 'OK: $action' : 'Error: $action')),
      ]),
      backgroundColor: ok ? AppTheme.accentGreen : AppTheme.accentRed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar Impresora')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.gradientPrimary,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status card
              GlassCard(
                borderColor: _hasPrinter
                    ? AppTheme.accentGreen.withValues(alpha: 0.4)
                    : AppTheme.accentOrange.withValues(alpha: 0.4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_hasPrinter
                                ? AppTheme.accentGreen
                                : AppTheme.accentOrange)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _hasPrinter
                            ? Icons.print_rounded
                            : Icons.print_disabled_rounded,
                        color: _hasPrinter
                            ? AppTheme.accentGreen
                            : AppTheme.accentOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hasPrinter
                                ? _printerName
                                : 'No configurada',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary),
                          ),
                          Text(
                            _hasPrinter
                                ? 'Tipo: ${_printerType == 'tcp' ? 'Red TCP/IP' : 'Sistema USB'}'
                                : 'Configure una impresora',
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (_hasPrinter)
                      TextButton(
                          onPressed: _disconnect,
                          child: const Text('Desconectar')),
                  ],
                ),
              ),

              if (_hasPrinter)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _testPrint,
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Imprimir pagina de prueba'),
                    ),
                  ),
                ),

              // Connection type tabs
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      indicatorColor: AppTheme.accentCyan,
                      labelColor: AppTheme.accentCyan,
                      unselectedLabelColor: AppTheme.textSecondary,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.wifi_rounded, size: 18),
                          text: 'Red (TCP/IP)',
                        ),
                        Tab(
                          icon: Icon(Icons.usb_rounded, size: 18),
                          text: 'USB / Instaladas',
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _connectionType == 0
                            ? _tcpForm()
                            : _usbDetectedList(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // A4 PRINTER SECTION
              GlassCard(
                borderColor: AppTheme.accentBlue.withValues(alpha: 0.3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.description_rounded,
                            color: AppTheme.accentBlue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Impresora normal (A4)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                    fontSize: 14)),
                            Text(
                              _hasA4Printer
                                  ? _a4PrinterName
                                  : 'Para actas de entrega',
                              style: TextStyle(
                                  color: _hasA4Printer
                                      ? AppTheme.accentGreen
                                      : AppTheme.textSecondary,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (_hasA4Printer)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: AppTheme.accentRed, size: 18),
                          onPressed: _clearA4Printer,
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final isDesktop =
                            Theme.of(context).platform == TargetPlatform.macOS ||
                            Theme.of(context).platform == TargetPlatform.windows ||
                            Theme.of(context).platform == TargetPlatform.linux;

                        if (!isDesktop) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'En dispositivos moviles se usa el dialogo de impresion del sistema (AirPrint / Android Print).',
                                style: TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final testPdf = await _printer.generateTestPdfBytes();
                                    await Printing.layoutPdf(
                                      onLayout: (_) async => testPdf,
                                      name: 'Prueba_A4',
                                    );
                                  },
                                  icon: const Icon(Icons.print_rounded, size: 18),
                                  label: const Text('Probar impresion A4'),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Seleccione la impresora para actas de entrega en formato A4/Carta.',
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  if (_systemPrinters.isEmpty) {
                                    await _detectSystemPrinters();
                                  }
                                  if (!mounted || _systemPrinters.isEmpty) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('No se encontraron impresoras'),
                                          backgroundColor: AppTheme.accentOrange,
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  final selected = await showDialog<Printer>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Seleccionar impresora A4',
                                          style: TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 16)),
                                      content: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: _systemPrinters
                                              .map((p) => ListTile(
                                                    leading: Icon(
                                                        Icons.print_rounded,
                                                        color: p.isAvailable
                                                            ? AppTheme.accentBlue
                                                            : AppTheme.textSecondary),
                                                    title: Text(p.name,
                                                        style: const TextStyle(
                                                            color: AppTheme.textPrimary)),
                                                    subtitle: Row(
                                                      children: [
                                                        if (p.isDefault)
                                                          const Text('Predeterminada  ',
                                                              style: TextStyle(
                                                                  color: AppTheme.accentCyan,
                                                                  fontSize: 11)),
                                                        Text(
                                                            p.isAvailable
                                                                ? 'Disponible'
                                                                : 'No disponible',
                                                            style: TextStyle(
                                                                color: p.isAvailable
                                                                    ? AppTheme.accentGreen
                                                                    : AppTheme.accentRed,
                                                                fontSize: 11)),
                                                      ],
                                                    ),
                                                    enabled: p.isAvailable,
                                                    onTap: () => Navigator.pop(ctx, p),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                    ),
                                  );
                                  if (selected != null) _selectA4Printer(selected);
                                },
                                icon: const Icon(Icons.print_rounded, size: 18),
                                label: Text(_hasA4Printer
                                    ? 'Cambiar impresora A4'
                                    : 'Seleccionar impresora A4'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Help
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.help_outline_rounded,
                          color: AppTheme.accentCyan.withValues(alpha: 0.7),
                          size: 20),
                      const SizedBox(width: 8),
                      const Text('Ayuda',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                    ]),
                    const SizedBox(height: 12),
                    _helpItem('Red',
                        'Conecte la impresora a la misma red WiFi o Ethernet. El puerto estandar es 9100.'),
                    _helpItem('USB',
                        'Las impresoras conectadas por USB o instaladas en el sistema aparecen automaticamente.'),
                    _helpItem('Ticket',
                        'Al crear una orden se muestra la opcion de imprimir el ticket de recepcion.'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tcpForm() {
    return Column(
      key: const ValueKey('tcp'),
      children: [
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Nombre',
            prefixIcon: Icon(Icons.label_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _hostCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Direccion IP',
                hintText: '192.168.1.100',
                prefixIcon: Icon(Icons.lan_rounded),
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _portCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Puerto'),
              keyboardType: TextInputType.number,
            ),
          ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _connectTcp,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primaryColor))
                : const Icon(Icons.link_rounded),
            label: const Text('Conectar por red'),
          ),
        ),
      ],
    );
  }

  Widget _usbDetectedList() {
    return Column(
      key: const ValueKey('usb'),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Impresoras detectadas',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
            IconButton(
              onPressed: _detectSystemPrinters,
              icon: const Icon(Icons.refresh_rounded,
                  color: AppTheme.accentCyan),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_loadingPrinters)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child:
                    CircularProgressIndicator(color: AppTheme.accentCyan)),
          )
        else if (_systemPrinters.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded,
                    size: 40,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                const Text('No se detectaron impresoras',
                    style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                const Text(
                  'Conecte una impresora por USB e intente de nuevo',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _detectSystemPrinters,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Buscar de nuevo'),
                ),
              ],
            ),
          )
        else
          ...(_systemPrinters.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  borderColor: p.isDefault
                      ? AppTheme.accentCyan.withValues(alpha: 0.4)
                      : null,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          p.isAvailable
                              ? Icons.print_rounded
                              : Icons.print_disabled_rounded,
                          color: p.isAvailable
                              ? AppTheme.accentCyan
                              : AppTheme.textSecondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                    fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                            if (p.model != null)
                              Text(p.model!,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11)),
                            Row(
                              children: [
                                if (p.isDefault)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentCyan
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: const Text('Predeterminada',
                                        style: TextStyle(
                                            color: AppTheme.accentCyan,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                Text(
                                  p.isAvailable
                                      ? 'Disponible'
                                      : 'No disponible',
                                  style: TextStyle(
                                    color: p.isAvailable
                                        ? AppTheme.accentGreen
                                        : AppTheme.accentRed,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (p.isAvailable)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () => _selectSystemPrinter(p),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              child: const Text('Usar'),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: () => _testSystemPrinter(p),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                textStyle: const TextStyle(fontSize: 10),
                              ),
                              child: const Text('Probar'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ))),
      ],
    );
  }

  Widget _helpItem(String title, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(title,
                style: const TextStyle(
                    color: AppTheme.accentCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
