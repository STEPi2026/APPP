import 'answer_input.dart';
import 'math_display.dart';

class PracticeQuestion {
  static const multipleChoice = 'MULTIPLE_CHOICE';
  static const shortAnswer = 'SHORT_ANSWER';

  final int? problemId;
  final String? problemCode;
  final bool? tutorReady;
  final String title;
  final String question;
  final String questionType;
  final List<String> choices;
  final List<String> choiceValues;
  final List<String> skillCodes;
  final int correctIndex;
  final String explanation;

  // 주관식의 표시용 정답과 모의 채점 방식
  final String? answerText;
  final String? gradingMode;
  final String? answerForm;
  final String? inputGuidance;

  final int? difficulty;
  final String? purpose;

  const PracticeQuestion({
    this.problemId,
    this.problemCode,
    this.tutorReady,
    required this.title,
    required this.question,
    this.questionType = multipleChoice,
    this.choices = const [],
    this.choiceValues = const [],
    this.skillCodes = const [],
    this.correctIndex = -1,
    required this.explanation,
    this.answerText,
    this.gradingMode,
    this.answerForm,
    this.inputGuidance,
    this.difficulty,
    this.purpose,
  });

  bool get isShortAnswer =>
      questionType == shortAnswer && answerForm != 'EXPRESSION';
  AnswerInput get input => AnswerInput(
    type: questionType,
    form: answerForm,
    choices: [
      for (int i = 0; i < choices.length; i++)
        AnswerChoice(choices[i], choiceAnswer(i)),
    ],
  );
  bool get isServerProblem => problemId != null && problemId! > 0;
  String get displayQuestion => displayMath(question);
  String displayChoice(int index) => displayMath(choices[index]);
  String choiceAnswer(int index) => choiceValues.length == choices.length
      ? choiceValues[index]
      : choices[index];

  String get correctAnswer {
    if (isShortAnswer) {
      return answerText ?? '';
    }

    return correctIndex >= 0 && correctIndex < choices.length
        ? choices[correctIndex]
        : '';
  }

  void validate() {
    if (question.trim().isEmpty) {
      throw const FormatException('문제 내용이 비어 있어요.');
    }
    if (isServerProblem) {
      if (input.missingChoices) {
        throw const FormatException('이 문제의 객관식 보기를 준비 중이에요.');
      }
      return;
    }

    if (isShortAnswer) {
      // 이번 단계에서는 숫자 하나인 답만 채점합니다.
      final expected = double.tryParse(answerText ?? '');

      if (gradingMode != 'NUMERIC' || expected == null || !expected.isFinite) {
        throw const FormatException('지원하지 않는 주관식 채점 방식이에요.');
      }

      return;
    }

    if (questionType != multipleChoice ||
        choices.isEmpty ||
        correctIndex < 0 ||
        correctIndex >= choices.length) {
      throw const FormatException('문제의 선택지 또는 정답이 잘못됐어요.');
    }
  }

  factory PracticeQuestion.fromServerJson(
    Map<String, dynamic> json, {
    required String title,
  }) {
    final id = json['id'],
        question = json['question'],
        type = json['problem_type'];
    if (id is! int ||
        id <= 0 ||
        question is! String ||
        question.trim().isEmpty ||
        type is! String) {
      throw const FormatException('서버 문제 정보를 확인하지 못했어요.');
    }
    final raw = json['choices'] ?? json['options'];
    if (json['tutor_ready'] != null && json['tutor_ready'] is! bool) {
      throw const FormatException('문제의 학습 경로 정보를 확인하지 못했어요.');
    }
    final labels = <String>[], values = <String>[];
    if (raw is List) {
      for (final option in raw) {
        if (option is Map &&
            option['label'] is String &&
            option['value'] != null) {
          labels.add(option['label']);
          values.add('${option['value']}');
        } else if (option is String) {
          labels.add(option);
          values.add(option);
        } else {
          throw const FormatException('문제의 보기 정보를 확인하지 못했어요.');
        }
      }
    }
    return PracticeQuestion(
      problemId: id,
      problemCode: json['problem_code'] as String?,
      tutorReady: json['tutor_ready'] as bool?,
      title: title,
      question: question,
      questionType: type,
      inputGuidance: json['input_guidance'] is String
          ? json['input_guidance']
          : null,
      answerForm: json['answer_form'] is String
          ? (json['answer_form'] as String).toUpperCase()
          : null,
      choices: List.unmodifiable(labels),
      skillCodes: json['skill_codes'] is List
          ? List<String>.unmodifiable(
              (json['skill_codes'] as List).whereType<String>(),
            )
          : const [],
      choiceValues: List.unmodifiable(values),
      explanation: '',
      difficulty: json['difficulty'] as int?,
      purpose: json['usage'] as String?,
    );
  }

  bool matchesNumericAnswer(String input) {
    if (!isShortAnswer || gradingMode != 'NUMERIC') {
      return false;
    }

    final normalized = input.trim().replaceAll('−', '-').replaceAll('－', '-');

    final actual = double.tryParse(normalized);
    final expected = double.tryParse(answerText ?? '');

    if (actual == null ||
        expected == null ||
        !actual.isFinite ||
        !expected.isFinite) {
      return false;
    }

    return actual == expected;
  }

  // 백엔드 응답 형식이 확정되기 전의 앱 내부 규격입니다.
  factory PracticeQuestion.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    final question = json['question'];
    final explanation = json['explanation'];
    final type = json['questionType'] ?? multipleChoice;
    final rawChoices = json['choices'] ?? const <String>[];
    final rawCorrectIndex = json['correctIndex'] ?? -1;

    if (title is! String ||
        question is! String ||
        explanation is! String ||
        type is! String ||
        rawChoices is! List ||
        rawChoices.any((item) => item is! String) ||
        rawCorrectIndex is! int ||
        (json['correctAnswer'] != null && json['correctAnswer'] is! String) ||
        (json['gradingMode'] != null && json['gradingMode'] is! String)) {
      throw const FormatException('문제 데이터 형식이 올바르지 않습니다.');
    }

    final result = PracticeQuestion(
      problemId: json['problemId'] is int ? json['problemId'] as int : null,
      problemCode: json['problemCode']?.toString(),
      tutorReady: json['tutor_ready'] is bool ? json['tutor_ready'] : null,
      title: title,
      question: question,
      questionType: type,
      choices: List<String>.unmodifiable(rawChoices.cast<String>()),
      correctIndex: rawCorrectIndex,
      explanation: explanation,
      inputGuidance: json['input_guidance'] is String
          ? json['input_guidance']
          : null,
      answerText: json['correctAnswer'] as String?,
      gradingMode: json['gradingMode'] as String?,
      difficulty: json['difficulty'] is int ? json['difficulty'] as int : null,
      purpose: json['purpose']?.toString(),
    );

    result.validate();
    return result;
  }

  Map<String, dynamic> toJson() {
    return {
      'problemId': problemId,
      'problemCode': problemCode,
      'tutor_ready': tutorReady,
      'title': title,
      'question': question,
      'questionType': questionType,
      'choices': choices,
      'correctIndex': correctIndex,
      'correctAnswer': correctAnswer,
      'gradingMode': gradingMode,
      'difficulty': difficulty,
      'purpose': purpose,
      'explanation': explanation,
      'input_guidance': inputGuidance,
    };
  }
}
