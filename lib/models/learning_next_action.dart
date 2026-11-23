/// Server-selected learning action, independent of answer correctness.
enum LearningNextAction {
  hint('HINT', '힌트 보기', '문제를 풀 단서를 확인해 봐요.'),
  checkAnswer('CHECK_ANSWER', '답 입력하기', '생각한 답을 입력해 주세요.'),
  showSolution('SHOW_SOLUTION', '해설 보기', '문제의 풀이와 정답을 확인해 봐요.'),
  relearn('RELEARN', '한 문제 더 연습하기', '같은 개념의 문제를 더 풀며 실력을 다져 봐요.'),
  confirmInput('CONFIRM_INPUT', '사진 내용 확인·수정', '사진에서 읽은 문제와 풀이를 확인해 주세요.'),
  nextSkill('NEXT_SKILL', '다음 개념 학습', '다음 개념으로 학습을 이어가요.'),
  complete('LEARNING_COMPLETE', '학습 완료', '이번 개념 학습을 마쳤어요.');

  final String code, title, message;
  const LearningNextAction(this.code, this.title, this.message);

  static LearningNextAction? fromCode(Object? code) {
    for (final action in values) {
      if (action.code == code) return action;
    }
    return null;
  }

  static LearningNextAction? fromResponse(Map<dynamic, dynamic> response) {
    final direct =
        fromCode(response['next_action']) ?? fromCode(response['next_step']);
    if (direct != null) return direct;
    final feedback = response['feedback'];
    return feedback is Map
        ? fromCode(feedback['next_action']) ?? fromCode(feedback['next_step'])
        : null;
  }

  static Map<dynamic, dynamic> payload(Map<dynamic, dynamic> response) {
    if (fromCode(response['next_action']) != null ||
        fromCode(response['next_step']) != null) {
      return response;
    }
    return response['feedback'] is Map ? response['feedback'] as Map : response;
  }
}
