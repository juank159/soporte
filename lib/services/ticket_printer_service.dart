import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_lib;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/service_order.dart';
import '../models/tenant.dart';
import '../config/api_config.dart';
import '../config/date_utils.dart';
import 'esc_pos_generator.dart';

class PrinterDevice {
  final String name;
  final String address;
  final PrinterConnectionType type;

  PrinterDevice({
    required this.name,
    required this.address,
    required this.type,
  });
}

enum PrinterConnectionType { tcp, system }

/// Servicio unificado de impresión. Singleton.
/// Reconecta automáticamente antes de cada impresión.
class TicketPrinterService {
  static final TicketPrinterService _instance =
      TicketPrinterService._internal();
  factory TicketPrinterService() => _instance;
  TicketPrinterService._internal();

  Socket? _socket;
  printing_lib.Printer? _systemPrinter;
  PrinterDevice? _connectedDevice;

  /// Returns true if there's a saved printer config (may or may not be live connected)
  Future<bool> get hasSavedPrinter async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('printer_type');
  }

  /// Get saved printer name for UI display
  Future<String?> get savedPrinterName async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_name');
  }

  /// Get saved printer type
  Future<String?> get savedPrinterType async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_type');
  }

  bool get isLiveConnected => _socket != null || _systemPrinter != null;
  PrinterDevice? get connectedDevice => _connectedDevice;

  // ==========================================
  //  CONNECT / DISCONNECT
  // ==========================================

  Future<bool> connectTcp(String host, int port, {String? name}) async {
    await _closeSocket();
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      _systemPrinter = null;
      _connectedDevice = PrinterDevice(
        name: name ?? '$host:$port',
        address: '$host:$port',
        type: PrinterConnectionType.tcp,
      );
      await _saveConfig(
        type: 'tcp',
        host: host,
        port: port,
        name: name ?? '$host:$port',
      );
      debugPrint('PRINTER: TCP connected to $host:$port');
      return true;
    } catch (e) {
      debugPrint('PRINTER: TCP connect failed: $e');
      return false;
    }
  }

  Future<bool> connectSystem(printing_lib.Printer printer) async {
    await _closeSocket();
    _systemPrinter = printer;
    _socket = null;
    _connectedDevice = PrinterDevice(
      name: printer.name,
      address: printer.url,
      type: PrinterConnectionType.system,
    );
    await _saveConfig(
      type: 'system',
      name: printer.name,
      systemUrl: printer.url,
    );
    debugPrint('PRINTER: System printer selected: ${printer.name}');
    return true;
  }

  Future<void> disconnect() async {
    await _closeSocket();
    _systemPrinter = null;
    _connectedDevice = null;
    await _clearConfig();
  }

  Future<void> _closeSocket() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  // ==========================================
  //  ENSURE READY (reconnect before printing)
  // ==========================================

  /// Ensures the printer is actually connected and ready to print.
  /// If not connected, reads saved config and reconnects.
  Future<bool> _ensureReady() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString('printer_type');
    if (type == null) return false;

    if (type == 'tcp') {
      // Check if socket is alive
      if (_socket != null) {
        try {
          // Test socket by sending nothing - if it throws, it's dead
          _socket!.add([]);
          await _socket!.flush();
          return true;
        } catch (_) {
          _socket = null;
        }
      }
      // Reconnect TCP
      final host = prefs.getString('printer_host');
      final port = prefs.getInt('printer_port');
      final name = prefs.getString('printer_name');
      if (host == null || port == null) return false;
      debugPrint('PRINTER: Reconnecting TCP $host:$port before printing...');
      return connectTcp(host, port, name: name);
    }

    if (type == 'system') {
      // Find the system printer by name
      final savedName = prefs.getString('printer_name');
      final savedUrl = prefs.getString('printer_system_url');
      if (savedName == null) return false;

      try {
        final printers = await printing_lib.Printing.listPrinters();
        // First try by name
        _systemPrinter = printers
            .where((p) => p.name == savedName && p.isAvailable)
            .firstOrNull;
        // Fallback by URL
        _systemPrinter ??= printers
            .where((p) => p.url == savedUrl && p.isAvailable)
            .firstOrNull;

        if (_systemPrinter != null) {
          _connectedDevice = PrinterDevice(
            name: _systemPrinter!.name,
            address: _systemPrinter!.url,
            type: PrinterConnectionType.system,
          );
          debugPrint(
            'PRINTER: System printer resolved: ${_systemPrinter!.name}',
          );
          return true;
        }
      } catch (e) {
        debugPrint('PRINTER: System printer resolve failed: $e');
      }
      return false;
    }

    return false;
  }

  // ==========================================
  //  PRINT METHODS
  // ==========================================

  Future<bool> printReceptionTicket({
    required ServiceOrder order,
    required Tenant tenant,
  }) async {
    if (!await _ensureReady()) return false;

    if (_systemPrinter != null) {
      return _printPdfToSystem(await generateTicketPdf(order, tenant));
    } else if (_socket != null) {
      return _sendTcpBytes(generateTicketEscPos(order: order, tenant: tenant));
    }
    return false;
  }

  Future<bool> printTestPage() async {
    if (!await _ensureReady()) return false;

    if (_systemPrinter != null) {
      return _printPdfToSystem(await _generateTestPdf());
    } else if (_socket != null) {
      final gen = EscPosGenerator();
      gen.setAlign(1);
      gen.setBold(true);
      gen.setTextSize(width: 2, height: 2);
      gen.printLine('PRUEBA');
      gen.setTextSize();
      gen.setBold(false);
      gen.feed(1);
      gen.printLine('Impresora configurada');
      gen.printLine('correctamente.');
      gen.feed(3);
      gen.cut();
      return _sendTcpBytes(gen.getBytes());
    }
    return false;
  }

  Future<Uint8List> generateTestPdfBytes() async => _generateTestPdf();

  // ==========================================
  //  INTERNAL SEND
  // ==========================================

  Future<bool> _sendTcpBytes(Uint8List bytes) async {
    if (_socket == null) return false;
    try {
      _socket!.add(bytes);
      await _socket!.flush();
      return true;
    } catch (e) {
      debugPrint('PRINTER: TCP send error: $e');
      _socket = null;
      return false;
    }
  }

  Future<bool> _printPdfToSystem(Uint8List pdfBytes) async {
    if (_systemPrinter == null) return false;
    try {
      return await printing_lib.Printing.directPrintPdf(
        printer: _systemPrinter!,
        onLayout: (_) async => pdfBytes,
      );
    } catch (e) {
      debugPrint('PRINTER: System print error: $e');
      return false;
    }
  }

  // ==========================================
  //  PDF GENERATION
  // ==========================================

  Future<Uint8List> _generateTestPdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          72 * PdfPageFormat.mm,
          120 * PdfPageFormat.mm,
        ),
        margin: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'PRUEBA DE IMPRESION',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.SizedBox(height: 6),
            pw.Text('Impresora configurada'),
            pw.Text('correctamente.'),
            pw.SizedBox(height: 10),
            pw.Text(
              'Servicio Tecnico SaaS',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              DateTime.now().toString().substring(0, 19),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 16),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateTicketPdf(ServiceOrder order, Tenant tenant) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          72 * PdfPageFormat.mm,
          260 * PdfPageFormat.mm,
        ),
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (_hasLogo(tenant)) _buildLogo(tenant),
            pw.Text(
              tenant.name,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            if (tenant.nit != null)
              pw.Text(
                'NIT: ${tenant.nit}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            if (tenant.address != null)
              pw.Text(
                tenant.address!,
                style: const pw.TextStyle(fontSize: 7),
                textAlign: pw.TextAlign.center,
              ),
            if (tenant.phone != null)
              pw.Text(
                'Tel: ${tenant.phone}',
                style: const pw.TextStyle(fontSize: 7),
              ),
            pw.Divider(thickness: 1.5),
            pw.SizedBox(height: 6),
            pw.Text(
              order.orderNumber,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'ORDEN DE SERVICIO',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 10),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: '${ApiConfig.statusPageUrl}/status/${order.id}',
              width: 90,
              height: 90,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Consulta el estado de tu equipo',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'escaneando este codigo QR',
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(),
            _pdfRow('Fecha', AppDateUtils.format(order.createdAt)),
            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                'CLIENTE',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            _pdfRow('Nombre', order.customer?.fullName ?? '-'),
            _pdfRow('Cedula', order.customer?.idNumber ?? '-'),
            _pdfRow('Tel', order.customer?.phone ?? '-'),
            pw.Divider(),
            // Single device (legacy)
            if (order.equipments.isEmpty && order.device != null) ...[
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('EQUIPO',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              _pdfRow('Tipo', order.device?.type ?? '-'),
              _pdfRow('Marca', order.device?.brand ?? '-'),
              _pdfRow('Modelo', order.device?.model ?? '-'),
              if (order.device?.serial != null)
                _pdfRow('Serial', order.device!.serial!),
              if (order.device?.accessories != null &&
                  order.device!.accessories!.isNotEmpty) ...[
                pw.Divider(),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text('ACCESORIOS',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(order.device!.accessories!.join(', '),
                      style: const pw.TextStyle(fontSize: 7)),
                ),
              ],
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text('PROBLEMA',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(order.problemReported,
                    style: const pw.TextStyle(fontSize: 7)),
              ),
            ],
            // Multiple equipments - same clean format as single device
            if (order.equipments.isNotEmpty) ...[
              ...order.equipments.asMap().entries.expand((e) {
                final i = e.key;
                final eq = e.value;
                return [
                  pw.Divider(),
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text('EQUIPO ${i + 1}',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ),
                  _pdfRow('Tipo', eq.deviceType),
                  _pdfRow('Marca', eq.deviceBrand),
                  _pdfRow('Modelo', eq.deviceModel),
                  if (eq.deviceSerial != null)
                    _pdfRow('Serial', eq.deviceSerial!),
                  if (eq.deviceColor != null)
                    _pdfRow('Color', eq.deviceColor!),
                  if (eq.accessories != null && eq.accessories!.isNotEmpty) ...[
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text('ACCESORIOS',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(eq.accessories!.join(', '),
                          style: const pw.TextStyle(fontSize: 7)),
                    ),
                  ],
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text('PROBLEMA',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(eq.problemReported,
                        style: const pw.TextStyle(fontSize: 7)),
                  ),
                ];
              }),
            ],
            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 4),
            pw.Text(
              'Desarrollado por Baudity',
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Contacto: 3138448436',
              style: const pw.TextStyle(fontSize: 6),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('$label:', style: const pw.TextStyle(fontSize: 8)),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  // ==========================================
  //  ESC/POS (for TCP thermal printers only)
  // ==========================================

  Uint8List generateTicketEscPos({
    required ServiceOrder order,
    required Tenant tenant,
  }) {
    final gen = EscPosGenerator();
    gen.setAlign(1);
    gen.setBold(true);
    gen.setTextSize(width: 2, height: 2);
    gen.printLine(_s(tenant.name));
    gen.setTextSize();
    gen.setBold(false);
    if (tenant.nit != null) gen.printLine('NIT: ${tenant.nit}');
    if (tenant.address != null) gen.printLine(_s(tenant.address!));
    if (tenant.phone != null) gen.printLine('Tel: ${tenant.phone}');
    gen.printSeparator(char: '=');
    gen.feed(1);
    gen.setBold(true);
    gen.setTextSize(width: 2, height: 2);
    gen.printLine(order.orderNumber);
    gen.setTextSize();
    gen.setBold(false);
    gen.printLine('ORDEN DE SERVICIO');
    gen.feed(1);
    gen.printQR('${ApiConfig.statusPageUrl}/status/${order.id}', moduleSize: 8);
    gen.feed(1);
    gen.printLine('Consulta el estado de tu equipo');
    gen.printLine('escaneando este codigo QR');
    gen.feed(1);
    gen.printSeparator();
    gen.setAlign(0);
    gen.printTwoColumns('Fecha:', AppDateUtils.format(order.createdAt));
    gen.printSeparator();
    gen.setBold(true);
    gen.printLine('DATOS DEL CLIENTE');
    gen.setBold(false);
    gen.printTwoColumns('Nombre:', _s(order.customer?.fullName ?? '-'));
    gen.printTwoColumns('Cedula:', order.customer?.idNumber ?? '-');
    gen.printTwoColumns('Tel:', order.customer?.phone ?? '-');
    // Single device (legacy)
    if (order.equipments.isEmpty && order.device != null) {
      gen.printSeparator();
      gen.setBold(true);
      gen.printLine('DATOS DEL EQUIPO');
      gen.setBold(false);
      gen.printTwoColumns('Tipo:', _s(order.device?.type ?? '-'));
      gen.printTwoColumns('Marca:', _s(order.device?.brand ?? '-'));
      gen.printTwoColumns('Modelo:', _s(order.device?.model ?? '-'));
      if (order.device?.serial != null)
        gen.printTwoColumns('Serial:', order.device!.serial!);
      if (order.device?.accessories != null &&
          order.device!.accessories!.isNotEmpty) {
        gen.printSeparator();
        gen.setBold(true);
        gen.printLine('ACCESORIOS');
        gen.setBold(false);
        gen.printLine(_s(order.device!.accessories!.join(', ')));
      }
      gen.printSeparator();
      gen.setBold(true);
      gen.printLine('PROBLEMA');
      gen.setBold(false);
      for (final l in _w(_s(order.problemReported), 48)) gen.printLine(l);
    }
    // Multiple equipments - same format as single device
    if (order.equipments.isNotEmpty) {
      for (int i = 0; i < order.equipments.length; i++) {
        final eq = order.equipments[i];
        gen.printSeparator();
        gen.setBold(true);
        gen.printLine('EQUIPO ${i + 1}');
        gen.setBold(false);
        gen.printTwoColumns('Tipo:', _s(eq.deviceType));
        gen.printTwoColumns('Marca:', _s(eq.deviceBrand));
        gen.printTwoColumns('Modelo:', _s(eq.deviceModel));
        if (eq.deviceSerial != null)
          gen.printTwoColumns('Serial:', eq.deviceSerial!);
        if (eq.deviceColor != null)
          gen.printTwoColumns('Color:', eq.deviceColor!);
        if (eq.accessories != null && eq.accessories!.isNotEmpty) {
          gen.printSeparator();
          gen.setBold(true);
          gen.printLine('ACCESORIOS');
          gen.setBold(false);
          gen.printLine(_s(eq.accessories!.join(', ')));
        }
        gen.printSeparator();
        gen.setBold(true);
        gen.printLine('PROBLEMA');
        gen.setBold(false);
        for (final l in _w(_s(eq.problemReported), 48)) gen.printLine(l);
      }
    }
    gen.feed(2);
    gen.printSeparator(char: '.', length: 48);
    gen.setAlign(1);
    gen.printLine('Desarrollado por Baudity');
    gen.printLine('Contacto: 3138448436');
    gen.feed(4);
    gen.cut();
    return gen.getBytes();
  }

  bool _hasLogo(Tenant t) =>
      t.logoUrl != null && t.logoUrl!.contains('base64,');

  pw.Widget _buildLogo(Tenant t) {
    try {
      final bytes = base64Decode(t.logoUrl!.split('base64,').last);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Image(pw.MemoryImage(bytes), height: 40),
      );
    } catch (_) {
      return pw.SizedBox.shrink();
    }
  }

  String _s(String t) => t
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ñ', 'N');

  List<String> _w(String t, int m) {
    final w = t.split(' ');
    final l = <String>[];
    var c = '';
    for (final x in w) {
      if (c.isEmpty) {
        c = x;
      } else if (c.length + 1 + x.length <= m) {
        c += ' $x';
      } else {
        l.add(c);
        c = x;
      }
    }
    if (c.isNotEmpty) l.add(c);
    return l;
  }

  // ==========================================
  //  CONFIG PERSISTENCE
  // ==========================================

  Future<void> _saveConfig({
    required String type,
    String? host,
    int? port,
    String? name,
    String? systemUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_type', type);
    if (name != null) await prefs.setString('printer_name', name);
    if (host != null) await prefs.setString('printer_host', host);
    if (port != null) await prefs.setInt('printer_port', port);
    if (systemUrl != null)
      await prefs.setString('printer_system_url', systemUrl);
  }

  Future<void> _clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      'printer_type',
      'printer_host',
      'printer_port',
      'printer_name',
      'printer_system_url',
    ]) {
      await prefs.remove(k);
    }
  }
}
