const mathInputGuide = '식은 x^2처럼 입력해요. 거듭제곱은 ^, 곱셈은 *를 사용하세요.';

/// Display only. Never use this text as a grading/submission value or raw OCR.
String displayMath(String text) {
  const superscripts = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '-': '⁻',
    '+': '⁺',
  };
  final powers = text.replaceAllMapped(
    RegExp(r'\^(?:\{([+-]?\d+)\}|\(([+-]?\d+)\)|([+-]?\d+))'),
    (m) =>
        (m[1] ?? m[2] ?? m[3]!).split('').map((c) => superscripts[c]!).join(),
  );
  return powers.replaceAllMapped(
    RegExp(r'([A-Za-z0-9⁰¹²³⁴⁵⁶⁷⁸⁹)\]])\s*\*\s*(?=[A-Za-z0-9(])'),
    (m) => '${m[1]}×',
  );
}
