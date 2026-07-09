import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// 'en_US' pattern purely for its thousands-grouping behaviour (#,##0) --
// nothing US-specific about it, and it's always available without extra
// intl locale-data initialization, unlike 'en_NG'.
final _fmt = NumberFormat('#,##0', 'en_US');
final _fmt2 = NumberFormat('#,##0.00', 'en_US');

/// "150000" -> "150,000". No currency symbol, no decimals -- matches how
/// amounts are shown everywhere in this app.
String formatAmount(num n) => _fmt.format(n);

/// "150000" -> "₦150,000".
String formatNaira(num n) => '₦${_fmt.format(n)}';

/// "150000.5" -> "₦150,000.50". For the handful of spots (company wallet
/// balance) that show cents.
String formatNairaDecimal(num n) => '₦${_fmt2.format(n)}';

/// Strips thousand-separator commas back out so the formatted display text
/// in an amount field can be parsed as a plain number again.
double? parseFormattedAmount(String text) => double.tryParse(text.replaceAll(',', ''));

/// Live-formats a TextField's digits with thousand separators as the user
/// types (e.g. entering "150000" shows "150,000"). Use alongside
/// FilteringTextInputFormatter.digitsOnly and parse submitted values with
/// [parseFormattedAmount], not double.tryParse directly.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(',', '');
    if (digitsOnly.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(digitsOnly);
    if (n == null) return oldValue;
    final formatted = _fmt.format(n);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
