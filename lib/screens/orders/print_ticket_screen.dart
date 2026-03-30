import 'package:flutter/material.dart';
import '../../models/service_order.dart';
import '../../models/tenant.dart';
import '../../services/ticket_printer_service.dart';
import '../../widgets/ticket_preview_widget.dart';
import '../../config/theme.dart';

class PrintTicketScreen extends StatefulWidget {
  final ServiceOrder order;
  final Tenant tenant;

  const PrintTicketScreen({
    super.key,
    required this.order,
    required this.tenant,
  });

  @override
  State<PrintTicketScreen> createState() => _PrintTicketScreenState();
}

class _PrintTicketScreenState extends State<PrintTicketScreen> {
  final TicketPrinterService _printerService = TicketPrinterService();
  bool _printing = false;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final has = await _printerService.hasSavedPrinter;
    setState(() => _connected = has);
  }

  Future<void> _printTicket() async {
    setState(() => _printing = true);

    try {
      final success = await _printerService.printReceptionTicket(
        order: widget.order,
        tenant: widget.tenant,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Ticket impreso correctamente'
                  : 'Error al imprimir. Verifique la conexion.',
            ),
            backgroundColor:
                success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al imprimir'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }

    setState(() => _printing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ticket ${widget.order.orderNumber}'),
        actions: [
          IconButton(
            onPressed: _checkConnection,
            icon: Icon(
              _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _connected ? Colors.greenAccent : Colors.orange,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Connection warning
            if (!_connected)
              Card(
                color: Colors.orange.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Impresora no conectada. Vaya a Configuracion > Impresora para conectar.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Ticket preview
            Center(
              child: TicketPreviewWidget(
                order: widget.order,
                tenant: widget.tenant,
              ),
            ),

            const SizedBox(height: 24),

            // Print button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _connected && !_printing ? _printTicket : null,
                icon: _printing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.print),
                label: Text(
                  _printing ? 'Imprimiendo...' : 'Imprimir Ticket 80mm',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Reprint note
            Text(
              'Puede reimprimir este ticket desde el detalle de la orden.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
