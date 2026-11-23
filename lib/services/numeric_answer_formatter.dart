import 'package:flutter/services.dart';

/// Reject the whole edit rather than silently turning x^2 into 2.
class NumericAnswerFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => RegExp(r'^[0-9+\-./\s]*$').hasMatch(newValue.text) ? newValue : oldValue;
}
