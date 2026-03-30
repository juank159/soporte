import 'package:flutter/material.dart';
import '../services/sync_service.dart';

/// Widget que muestra el estado de sincronización en la barra de la app.
class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: SyncService().syncStatus,
      initialData: SyncStatus.synced,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.synced;

        IconData icon;
        Color color;
        String tooltip;

        switch (status) {
          case SyncStatus.synced:
            icon = Icons.cloud_done;
            color = Colors.greenAccent;
            tooltip = 'Sincronizado';
            break;
          case SyncStatus.syncing:
            icon = Icons.cloud_sync;
            color = Colors.yellowAccent;
            tooltip = 'Sincronizando...';
            break;
          case SyncStatus.offline:
            icon = Icons.cloud_off;
            color = Colors.orangeAccent;
            tooltip = 'Sin conexion - modo offline';
            break;
          case SyncStatus.error:
            icon = Icons.cloud_off;
            color = Colors.redAccent;
            tooltip = 'Error de sincronizacion';
            break;
        }

        return IconButton(
          icon: Icon(icon, color: color),
          tooltip: tooltip,
          onPressed: () {
            if (status != SyncStatus.syncing) {
              SyncService().syncAll();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tooltip),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );
      },
    );
  }
}
