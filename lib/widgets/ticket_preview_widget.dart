import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/service_order.dart';
import '../models/tenant.dart';
import '../config/api_config.dart';
import '../config/date_utils.dart';

/// Widget que muestra una vista previa del ticket de recepción 80mm en pantalla.
/// Simula el look de un ticket térmico impreso (fondo blanco, texto negro).
class TicketPreviewWidget extends StatelessWidget {
  final ServiceOrder order;
  final Tenant tenant;
  final String? technicianName;

  const TicketPreviewWidget({
    super.key,
    required this.order,
    required this.tenant,
    this.technicianName,
  });

  static const _black = Color(0xFF1A1A1A);
  static const _grey = Color(0xFF555555);
  static const _lightGrey = Color(0xFF888888);

  @override
  Widget build(BuildContext context) {
    final qrUrl = '${ApiConfig.statusPageUrl}/status/${order.id}';

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo
          if (tenant.logoUrl != null &&
              tenant.logoUrl!.startsWith('data:') &&
              tenant.logoUrl!.contains(','))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Image.memory(
                base64Decode(tenant.logoUrl!.split(',').last),
                height: 50,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            )
          else if (tenant.logoUrl != null && tenant.logoUrl!.startsWith('http'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Image.network(tenant.logoUrl!, height: 50,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),

          // Header - Tenant info
          Text(
            tenant.name,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: _black),
            textAlign: TextAlign.center,
          ),
          if (tenant.nit != null && tenant.nit!.isNotEmpty)
            Text('NIT: ${tenant.nit}',
                style: const TextStyle(fontSize: 11, color: _grey)),
          if (tenant.address != null && tenant.address!.isNotEmpty)
            Text(tenant.address!,
                style: const TextStyle(fontSize: 10, color: _grey),
                textAlign: TextAlign.center),
          if (tenant.phone != null && tenant.phone!.isNotEmpty)
            Text('Tel: ${tenant.phone}',
                style: const TextStyle(fontSize: 10, color: _grey)),

          const Divider(thickness: 2, color: _black, height: 16),

          // Order number
          Text(
            order.orderNumber,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _black,
                letterSpacing: 1),
          ),
          const Text('ORDEN DE SERVICIO',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: _grey)),
          const SizedBox(height: 10),

          // QR Code
          QrImageView(
            data: qrUrl,
            version: QrVersions.auto,
            size: 130,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: _black),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square, color: _black),
          ),
          const SizedBox(height: 6),
          const Text('Consulta el estado de tu equipo',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _black)),
          const Text('escaneando este codigo QR',
              style: TextStyle(fontSize: 8, color: _grey)),
          const SizedBox(height: 8),

          const Divider(color: _grey, height: 8),

          // Date
          _row('Fecha:', AppDateUtils.format(order.createdAt)),

          _sectionTitle('DATOS DEL CLIENTE'),
          _row('Nombre:', order.customer?.fullName ?? '-'),
          _row('Cedula:', order.customer?.idNumber ?? '-'),
          _row('Tel:', order.customer?.phone ?? '-'),

          _sectionTitle('DATOS DEL EQUIPO'),
          _row('Tipo:', order.device?.type ?? '-'),
          _row('Marca:', order.device?.brand ?? '-'),
          _row('Modelo:', order.device?.model ?? '-'),
          if (order.device?.serial != null) _row('Serial:', order.device!.serial!),
          if (order.device?.color != null) _row('Color:', order.device!.color!),
          if (order.device?.accessories != null &&
              order.device!.accessories!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Accesorios: ${order.device!.accessories!.join(', ')}',
                style: const TextStyle(fontSize: 10, color: _black),
              ),
            ),

          if (technicianName != null && technicianName!.isNotEmpty)
            _row('Tecnico:', technicianName!),

          _sectionTitle('PROBLEMA'),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(order.problemReported,
                style: const TextStyle(fontSize: 10, color: _black)),
          ),

          if (tenant.legalNotice != null && tenant.legalNotice!.isNotEmpty) ...[
            const Divider(color: _grey, height: 16),
            Text(tenant.legalNotice!,
                style: const TextStyle(fontSize: 8, color: _lightGrey),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 10),
          const Divider(color: _lightGrey),
          const SizedBox(height: 4),
          const Text('Desarrollado por Baudity',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: _grey)),
          const Text('Contacto: 3138448436',
              style: TextStyle(fontSize: 7, color: _lightGrey)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _black)),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: _grey)),
          Flexible(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 10, color: _black, fontWeight: FontWeight.w500),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

}
