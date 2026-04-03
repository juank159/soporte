import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Selector de rango de fechas elegante como dialog.
/// Devuelve (dateFrom, dateTo, label) o null si cancela.
class DateRangePickerDialog extends StatefulWidget {
  final String? initialFrom;
  final String? initialTo;

  const DateRangePickerDialog({super.key, this.initialFrom, this.initialTo});

  @override
  State<DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<DateRangePickerDialog> {
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    if (widget.initialFrom != null) _from = DateTime.tryParse(widget.initialFrom!);
    if (widget.initialTo != null) _to = DateTime.tryParse(widget.initialTo!);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtApi(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_from ?? now) : (_to ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: AppTheme.darkTheme.copyWith(
          datePickerTheme: DatePickerThemeData(
            backgroundColor: AppTheme.surfaceColor,
            headerBackgroundColor: AppTheme.cardColor,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = picked;
          if (_to != null && _to!.isBefore(picked)) _to = picked;
        } else {
          _to = picked;
          if (_from != null && _from!.isAfter(picked)) _from = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor,
      title: Row(children: [
        Icon(Icons.date_range_rounded, color: AppTheme.accentCyan, size: 22),
        SizedBox(width: 10),
        Text('Seleccionar rango',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      ]),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // From
            InkWell(
              onTap: () => _pickDate(true),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded,
                      color: AppTheme.accentCyan, size: 18),
                  SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Desde',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    Text(
                      _from != null ? _fmt(_from!) : 'Seleccionar fecha',
                      style: TextStyle(
                        color: _from != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            SizedBox(height: 12),
            Icon(Icons.arrow_downward_rounded,
                color: AppTheme.textSecondary, size: 18),
            SizedBox(height: 12),
            // To
            InkWell(
              onTap: () => _pickDate(false),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Row(children: [
                  Icon(Icons.event_rounded,
                      color: AppTheme.accentPurple, size: 18),
                  SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hasta',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    Text(
                      _to != null ? _fmt(_to!) : 'Seleccionar fecha',
                      style: TextStyle(
                        color: _to != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _from != null && _to != null
              ? () {
                  final label = '${_fmt(_from!)} - ${_fmt(_to!)}';
                  Navigator.pop(context, {
                    'from': _fmtApi(_from!),
                    'to': _fmtApi(_to!),
                    'label': label,
                  });
                }
              : null,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

/// Helper to show the date range picker dialog
Future<Map<String, String>?> showDateRangePickerDialog(
  BuildContext context, {
  String? initialFrom,
  String? initialTo,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => DateRangePickerDialog(
      initialFrom: initialFrom,
      initialTo: initialTo,
    ),
  );
}
