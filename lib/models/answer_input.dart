/// Display/input metadata only. Correctness and rewards remain server-owned.
class AnswerChoice {
  final String label, value;
  const AnswerChoice(this.label, this.value);
}

class AnswerInput {
  final String type;
  final String? form;
  final List<AnswerChoice> choices;
  const AnswerInput({required this.type, this.form, this.choices = const []});

  factory AnswerInput.fromJson(Map<dynamic, dynamic> json) {
    final raw = json['choices'] ?? json['options'];
    final choices = <AnswerChoice>[];
    if (raw is List) {
      for (final option in raw) {
        if (option is Map &&
            option['label'] is String &&
            option['value'] != null) {
          choices.add(AnswerChoice(option['label'], '${option['value']}'));
        } else if (option is String) {
          choices.add(AnswerChoice(option, option));
        }
      }
    }
    final form = json['answer_form'];
    return AnswerInput(
      type: '${json['problem_type'] ?? json['question_type'] ?? 'SHORT_ANSWER'}'
          .toUpperCase(),
      form: form is String ? form.toUpperCase() : null,
      choices:
          raw is List &&
              raw.length == choices.length &&
              choices.length >= 2 &&
              choices.map((c) => c.value).toSet().length == choices.length
          ? List.unmodifiable(choices)
          : const [],
    );
  }

  bool get isChoice =>
      ['MULTIPLE_CHOICE', 'OX', 'TRUE_FALSE'].contains(type) ||
      form == 'EXPRESSION';
  bool get missingChoices =>
      isChoice &&
      (choices.length < 2 ||
          choices.map((c) => c.value).toSet().length != choices.length ||
          choices.any((c) => c.label.trim().isEmpty || c.value.trim().isEmpty));
  bool get isNumeric => !isChoice && form == 'NUMERIC';
  bool accepts(String value) {
    final text = value.trim();
    if (isChoice) return choices.any((c) => c.value == value);
    if (text.isEmpty) return false;
    if (!isNumeric) return true;
    if (RegExp(r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$').hasMatch(text)) return true;
    if (!RegExp(r'^[+-]?\d+/[+-]?\d+$').hasMatch(text)) return false;
    return BigInt.parse(text.split('/').last) != BigInt.zero;
  }
}
