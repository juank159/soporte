import 'package:flutter/services.dart';

/// Formats a number with thousand separators (dots for COP)
/// Example: 178500 -> "178.500"
String formatMoney(dynamic amount) {
  final num = double.tryParse('$amount') ?? 0;
  final str = num.toStringAsFixed(0);
  final chars = str.replaceAll('-', '').split('').reversed.toList();
  final formatted = <String>[];
  for (int i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) formatted.add('.');
    formatted.add(chars[i]);
  }
  final result = formatted.reversed.join('');
  return num < 0 ? '-$result' : result;
}

/// TextInputFormatter that adds thousand separators as you type
class ThousandSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    // Remove all non-digits
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');

    final formatted = formatMoney(int.tryParse(digits) ?? 0);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Extract raw number from formatted string
double parseFormattedMoney(String text) {
  final clean = text.replaceAll('.', '').replaceAll(',', '');
  return double.tryParse(clean) ?? 0;
}
