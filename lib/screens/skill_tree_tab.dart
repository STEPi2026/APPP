import 'package:flutter/material.dart';

import '../services/learning_repository.dart';
import '../services/concept_check.dart';
import '../services/student_knowledge.dart';
import 'knowledge_widgets.dart';
import 'student_report_panel.dart';
import 'concept_level_test_dialog.dart';
import 'expanded_galaxy_dialog.dart';
import 'space_cartoon_painters.dart';

class _SubUnitDetail {
  final String code;
  final String title;
  final String prerequisitePath;
  final List<String> coreConcepts;
  final List<String> problemTypes;

  const _SubUnitDetail({
    required this.code,
    required this.title,
    required this.prerequisitePath,
    required this.coreConcepts,
    required this.problemTypes,
  });
}

class _MiddleUnitData {
  final String title;
  final List<_SubUnitDetail> subUnits;

  const _MiddleUnitData({required this.title, required this.subUnits});
}

class _SatelliteUnitData {
  final String id;
  final String gradeLabel; // '초등', '중1', '중2', '중3', '고1', '고2·고3'
  final String name;
  final String majorUnitTitle;
  final double orbitPosition;
  final List<_MiddleUnitData> middleUnits;

  const _SatelliteUnitData({
    required this.id,
    required this.gradeLabel,
    required this.name,
    required this.majorUnitTitle,
    required this.orbitPosition,
    required this.middleUnits,
  });
}

class _CurriculumPlanetData {
  final String id;
  final String name;
  final String subtitle;
  final Color primaryColor;
  final Color secondaryColor;
  final List<_SatelliteUnitData> satellites;

  const _CurriculumPlanetData({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.primaryColor,
    required this.secondaryColor,
    required this.satellites,
  });
}

List<_CurriculumPlanetData> _curriculumPlanets() {
  return [
    // 1. 변화와 관계
    _CurriculumPlanetData(
      id: 'change_and_relations',
      name: '변화와 관계',
      subtitle: '문자와 식 · 방정식 · 다항식 · 함수',
      primaryColor: const Color(0xFF9B7EFA),
      secondaryColor: const Color(0xFFD6BCFA),
      satellites: [
        _SatelliteUnitData(
          id: 'sat_m1_eq',
          gradeLabel: '중1',
          name: '일차방정식·좌표',
          majorUnitTitle: '[중1 변화와 관계] 문자와 식 · 일차방정식 · 좌표평면과 그래프',

          orbitPosition: 0.15,
          middleUnits: const [
            _MiddleUnitData(
              title: '중단원 1. 문자와 식 · 일차방정식 이항 (중1)',
              subUnits: [
                _SubUnitDetail(
                  code: 'SKL-2-037',
                  title: '소단원 01. 등식의 성질과 이항 부호 법칙',

                  prerequisitePath: '초5 규칙과 대응 ➔ 중1 일차방정식 ➔ 고1 방정식과 부등식',
                  coreConcepts: [
                    '등식의 양변에 같은 수를 더하거나 빼는 원리',
                    '이항 시 부호 반전(-a ➔ +a) 규칙',
                  ],
                  problemTypes: [
                    '[유형 01] 괄호가 있는 일차방정식의 풀이',
                    '[유형 02] 계수가 소수·분수인 방정식의 이항',
                  ],
                ),
              ],
            ),
            _MiddleUnitData(
              title: '중단원 2. 좌표평면과 정비례·반비례 그래프 (중1)',
              subUnits: [
                _SubUnitDetail(
                  code: 'MID-1-04',
                  title: '소단원 01. 순서쌍과 사분면 · 정비례(y=ax)와 반비례(y=a/x)',

                  prerequisitePath: '초6 비와 비율 ➔ 중1 정비례·반비례 ➔ 중2 일차함수',
                  coreConcepts: [
                    '제1~4사분면 위의 점의 부호 (+, -)',
                    '원점을 지나는 직선 y=ax 와 쌍곡선 y=a/x',
                  ],
                  problemTypes: [
                    '[유형 01] 사분면의 조건이 주어질 때 점의 위치 찾기',
                    '[유형 02] 정비례·반비례 그래프 위의 점의 좌표 구하기',
                  ],
                ),
              ],
            ),
          ],
        ),
        const _SatelliteUnitData(
          id: 'sat_m2_func',
          gradeLabel: '중2',
          name: '부등식·일차함수',
          majorUnitTitle: '[중2 변화와 관계] 식의 계산 · 일차부등식 · 연립방정식 · 일차함수',

          orbitPosition: 0.35,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 일차부등식과 일차함수의 그래프 (중2)',
              subUnits: [
                _SubUnitDetail(
                  code: 'MID-2-02',
                  title: '소단원 01. 음수를 곱할 때 부등호 반전 & 일차함수 기울기',

                  prerequisitePath: '중1 일차방정식 ➔ 중2 부등식·일차함수 ➔ 고1 직선의 방정식',
                  coreConcepts: [
                    '양변에 음수를 곱하거나 나누면 부등호 방향이 바뀜',
                    '기울기 a = (y증가량) / (x증가량)',
                  ],
                  problemTypes: [
                    '[유형 01] 부등식의 해의 범위 구하기',
                    '[유형 02] 두 점을 지나는 일차함수의 식 구하기',
                  ],
                ),
              ],
            ),
          ],
        ),
        const _SatelliteUnitData(
          id: 'sat_m3_quad',
          gradeLabel: '중3',
          name: '인수분해·이차함수',
          majorUnitTitle: '[중3 변화와 관계] 다항식의 곱셈과 인수분해 · 이차방정식 · 이차함수',

          orbitPosition: 0.55,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 인수분해와 이차함수의 꼭짓점 (중3)',
              subUnits: [
                _SubUnitDetail(
                  code: 'STP-2-014',
                  title: '소단원 01. 완전제곱식과 이차함수 y = a(x-p)² + q',

                  prerequisitePath: '중2 식의 계산 ➔ 중3 인수분해·이차함수 ➔ 고1 다항식·이차함수',
                  coreConcepts: [
                    '완전제곱식 (a±b)² = a² ± 2ab + b²',
                    '완전제곱식 변형을 통한 꼭짓점 (p, q) 구하기',
                  ],
                  problemTypes: [
                    '[유형 01] 공통인수를 이용한 인수분해',
                    '[유형 02] 이차함수 표준형으로 최솟값 구하기',
                  ],
                ),
              ],
            ),
          ],
        ),
        const _SatelliteUnitData(
          id: 'sat_poly',
          gradeLabel: '고1',
          name: '다항식',
          majorUnitTitle: '[고1 공통수학1] I. 다항식 (곱셈공식 · 나머지정리)',

          orbitPosition: 0.75,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 다항식의 연산과 나머지정리 (고1)',
              subUnits: [
                _SubUnitDetail(
                  code: 'PRB-1-014',
                  title: '소단원 01. 곱셈 공식 변형과 항등식·나머지정리',

                  prerequisitePath: '중1 항등식 ➔ 중3 인수분해 ➔ 고1 나머지정리 (현재 취약!)',
                  coreConcepts: [
                    '나머지정리: P(x)를 (x-α)로 나눈 나머지는 R = P(α)',
                    '인수정리: P(α) = 0 ⇔ (x-α)를 인수로 가짐',
                  ],
                  problemTypes: [
                    '[유형 01] 일차식 (x-2)로 나눈 나머지 구하기',
                    '[유형 02] 인수정리를 이용한 미정계수 구하기',
                  ],
                ),
              ],
            ),
          ],
        ),
        const _SatelliteUnitData(
          id: 'sat_eq_ineq',
          gradeLabel: '고1',
          name: '방정식과 부등식',
          majorUnitTitle: '[고1 공통수학1] II. 방정식과 부등식',

          orbitPosition: 0.92,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 복소수와 이차방정식 (고1)',
              subUnits: [
                _SubUnitDetail(
                  code: 'PRB-2-004',
                  title: '소단원 01. 허수단위 i와 복소수의 상등 · 판별식 D',

                  prerequisitePath: '중1 일차방정식 이항(SKL-2-037) ➔ 중3 제곱근 ➔ 고1 복소수',
                  coreConcepts: [
                    '허수단위 i² = -1, i⁴ = 1 주기성',
                    '복소수 상등 조건과 판별식 D = b² - 4ac',
                  ],
                  problemTypes: [
                    '[유형 01] 복소수의 상등을 이용한 실수 x, y 구하기',
                    '[유형 02] 이차방정식의 판별식 D 계산하기',
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    // 2. 수와 연산
    const _CurriculumPlanetData(
      id: 'numbers_and_operations',
      name: '수와 연산',
      subtitle: '자연수 · 정수 · 유리수 · 실수 · 행렬',
      primaryColor: Color(0xFF26C6DA),
      secondaryColor: Color(0xFF80DEEA),
      satellites: [
        _SatelliteUnitData(
          id: 'sat_elem_frac',
          gradeLabel: '초등',
          name: '약수·분수 연산',
          majorUnitTitle: '[초5~초6 기초] 약수와 배수 · 분수의 사칙연산',

          orbitPosition: 0.15,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 약분과 통분 · 분수의 나눗셈',
              subUnits: [
                _SubUnitDetail(
                  code: 'ELM-5-01',
                  title: '소단원 01. 최소공배수를 이용한 통분과 분수 계산',

                  prerequisitePath: '초3 분수와 소수 ➔ 초5 약분과 통분 ➔ 중1 유리수의 계산',
                  coreConcepts: ['최대공약수와 최소공배수', '역수를 곱하는 분수 나눗셈'],
                  problemTypes: ['[유형 01] 이분모 분수의 덧셈과 뺄셈'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_m1_int',
          gradeLabel: '중1',
          name: '소인수분해·정수',
          majorUnitTitle: '[중1 수와 연산] 소인수분해 · 정수와 유리수의 사칙연산',

          orbitPosition: 0.35,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 소인수분해와 정수와 유리수의 사칙연산 (중1)',
              subUnits: [
                _SubUnitDetail(
                  code: 'MID-1-02',
                  title: '소단원 01. 거듭제곱·약수의 개수 및 음수의 부호 연산 규칙',

                  prerequisitePath: '초6 분수의 연산 ➔ 중1 소인수분해·정수와 유리수 ➔ 전학년 방정식',
                  coreConcepts: [
                    '소인수분해를 이용한 약수의 개수 공식',
                    '절댓값 정의와 음수의 거듭제곱 부호 결정',
                  ],
                  problemTypes: ['[유형 01] 거듭제곱과 사칙연산이 섞인 유리수의 혼합 계산'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_m2_dec',
          gradeLabel: '중2',
          name: '유리수와 순환소수',
          majorUnitTitle: '[중2 수와 연산] 유리수와 순환소수',

          orbitPosition: 0.55,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 유한소수와 순환소수의 분수 표현 (중2)',
              subUnits: [
                _SubUnitDetail(
                  code: 'MID-2-01',
                  title: '소단원 01. 분모의 소인수가 2나 5뿐인 유한소수 판별',

                  prerequisitePath: '중1 소인수분해 ➔ 중2 유리수와 순환소수 ➔ 중3 실수 체계',
                  coreConcepts: ['기약분수의 분모 소인수 확인', '순환소수를 분수로 고치는 원리'],
                  problemTypes: ['[유형 01] 유한소수가 되도록 하는 미지수 x의 값 구하기'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_mid_real',
          gradeLabel: '중3',
          name: '제곱근과 실수',
          majorUnitTitle: '[중3 수와 연산] 제곱근과 실수 · 근호를 포함한 식의 계산',

          orbitPosition: 0.75,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 제곱근의 성질과 무리수 (중3)',
              subUnits: [
                _SubUnitDetail(
                  code: 'MID-3-01',
                  title: '소단원 01. 절댓값 기호 |a|와 √(a²) = |a| 성질',

                  prerequisitePath: '중1 정수와 유리수 ➔ 중3 제곱근과 실수 ➔ 고1 복소수·절댓값',
                  coreConcepts: ['절댓값은 원점으로부터의 거리(항상 0 이상)', '분모의 유리화'],
                  problemTypes: ['[유형 01] 근호를 포함한 식의 사칙연산'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_matrix',
          gradeLabel: '고1',
          name: '행렬과 집합',
          majorUnitTitle: '[고1 공통수학1·2] 행렬과 그 연산 · 집합과 명제',

          orbitPosition: 0.92,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 행렬의 뜻과 연산',
              subUnits: [
                _SubUnitDetail(
                  code: 'PRB-4-001',
                  title: '소단원 01. 행렬의 (i, j) 성분과 서로 같은 행렬',

                  prerequisitePath: '중2 연립일차방정식 ➔ 고1 행렬과 그 연산 (여기를 하기! 🔥)',
                  coreConcepts: ['제i행 제j열의 성분 a_ij 표기법', '두 행렬이 서로 같을 조건'],
                  problemTypes: [
                    '[유형 01] 주어진 행렬에서 a₁₂, a₂₃ 성분 찾기',
                    '[유형 02] 행렬의 상등을 이용한 미지수 구하기',
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    // 3. 자료와 가능성
    const _CurriculumPlanetData(
      id: 'data_and_probability',
      name: '자료와 가능성',
      subtitle: '경우의 수 · 순열과 조합 · 원순열 · 확률',
      primaryColor: Color(0xFFFF6090),
      secondaryColor: Color(0xFFFFC1E3),
      satellites: [
        _SatelliteUnitData(
          id: 'sat_m1_stat',
          gradeLabel: '중1',
          name: '자료의 정리와 해석',
          majorUnitTitle: '[중1 자료와 가능성] 대푯값 · 줄기와 잎 그림 · 도수분포표 · 상대도수',

          orbitPosition: 0.15,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 도수분포표와 히스토그램·상대도수 (중1)',
              subUnits: [
                _SubUnitDetail(
                  code: 'STA-1-01',
                  title: '소단원 01. 계급의 크기와 도수 · 상대도수의 총합은 항상 1',

                  prerequisitePath: '초5~6 평균과 그래프 ➔ 중1 도수분포표·상대도수 ➔ 중3 산포도',
                  coreConcepts: [
                    '상대도수 = (계급의 도수) / (도수의 총합)',
                    '히스토그램 넓이의 합 = (계급 크기) × (총도수)',
                  ],
                  problemTypes: ['[유형 01] 일부가 찢어진 상대도수 분포표에서 도수 구하기'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_mid_prob',
          gradeLabel: '중2',
          name: '경우의 수와 확률',
          majorUnitTitle: '[중2 자료와 가능성] 사건과 경우의 수 · 확률의 뜻과 성질',

          orbitPosition: 0.38,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 사건과 경우의 수 (중2)',
              subUnits: [
                _SubUnitDetail(
                  code: 'MID-2-08',
                  title: '소단원 01. 동시에 일어나는 사건과 순서쌍',

                  prerequisitePath: '초5 가능성 ➔ 중2 경우의 수 ➔ 고1 순열과 조합',
                  coreConcepts: ['수형도 그리기', '주사위와 동전 던지기 경우의 수'],
                  problemTypes: ['[유형 01] 두 사건이 동시에 일어날 때의 경우의 수'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_m3_disp',
          gradeLabel: '중3',
          name: '산포도와 상관관계',
          majorUnitTitle: '[중3 자료와 가능성] 분산과 표준편차 · 산점도와 상관관계',

          orbitPosition: 0.60,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 편차의 합(0)과 분산·표준편차 (중3)',
              subUnits: [
                _SubUnitDetail(
                  code: 'STA-3-01',
                  title: '소단원 01. 편차 = (변량 - 평균) · 분산과 표준편차 구하기',

                  prerequisitePath: '중1 대푯값과 도수분포표 ➔ 중3 산포도 ➔ 고2 확률과 통계',
                  coreConcepts: ['편차의 총합은 항상 0', '분산 = (편차²의 총합) / (변량의 개수)'],
                  problemTypes: ['[유형 01] 편차가 주어질 때 미지수 x와 표준편차 구하기'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_perm_comb',
          gradeLabel: '고1',
          name: '순열과 조합',
          majorUnitTitle: '[고1 공통수학1] III. 경우의 수 (순열 nPr · 조합 nCr)',

          orbitPosition: 0.78,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 합의 법칙과 곱의 법칙 · 순열과 조합',
              subUnits: [
                _SubUnitDetail(
                  code: 'PRB-3-009',
                  title: '소단원 01. 순열(nPr)과 조합(nCr)의 계산과 차이',

                  prerequisitePath:
                      '중2 경우의 수 ➔ 고1 순열과 조합 (여기를 하기! 🔥) ➔ 고2 원순열',
                  coreConcepts: ['순열 nPr (순서 O)', '조합 nCr = nPr / r! (순서 X)'],
                  problemTypes: [
                    '[유형 01] 셔츠와 바지를 고르는 곱의 법칙',
                    '[유형 02] 6P2와 6C2 빠르게 계산하기',
                  ],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_circular_perm',
          gradeLabel: '고2·고3',
          name: '원순열',
          majorUnitTitle: '[고2~고3 확률과 통계] 여러 가지 순열 · 원순열',

          orbitPosition: 0.94,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 원순열과 중복순열',
              subUnits: [
                _SubUnitDetail(
                  code: 'PRB-H2-01',
                  title: '소단원 01. 원탁에 둘러앉는 원순열의 수 (n-1)!',

                  prerequisitePath:
                      '🔒 [고1 순열과 조합(nPr, nCr)]을 먼저 마스터하면 원순열 위성이 열려요!',
                  coreConcepts: ['회전하여 일치하는 배열은 같은 것으로 봄: n! / n = (n-1)!'],
                  problemTypes: ['[유형 01] 원탁에 n명이 둘러앉는 경우의 수'],
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    // 4. 도형과 측정
    const _CurriculumPlanetData(
      id: 'geometry_and_measurement',
      name: '도형과 측정',
      subtitle: '평면도형 · 피타고라스 · 원과 직선의 방정식',
      primaryColor: Color(0xFFFFB300),
      secondaryColor: Color(0xFFFFE082),
      satellites: [
        _SatelliteUnitData(
          id: 'sat_m1_geo',
          gradeLabel: '중1',
          name: '기본도형·합동·입체',
          majorUnitTitle: '[중1 도형과 측정] 기본 도형 · 작도와 합동 · 평면·입체도형의 측정',

          orbitPosition: 0.20,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 삼각형의 합동(SSS, SAS, ASA)과 부채꼴·입체도형 (중1)',
              subUnits: [
                _SubUnitDetail(
                  code: 'GEO-1-02',
                  title: '소단원 01. 평행선 동위각·엇각, 삼각형 합동, 부채꼴 호와 넓이(1/2 rl)',

                  prerequisitePath: '초6 원의 넓이 ➔ 중1 작도와 합동·부채꼴 ➔ 중2 도형의 성질·닮음',
                  coreConcepts: [
                    '삼각형의 합동 조건 (SSS, SAS, ASA)',
                    '부채꼴 넓이 S = πr² × (x/360) = 1/2 rl',
                  ],
                  problemTypes: [
                    '[유형 01] 평행선에서 각의 크기 구하기',
                    '[유형 02] 원기둥·원뿔·구의 겉넓이와 부피 구하기',
                  ],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_m2_sim',
          gradeLabel: '중2',
          name: '외심·닮음·피타고라스',
          majorUnitTitle: '[중2 도형과 측정] 삼각형·사각형의 성질 · 도형의 닮음 · 피타고라스 정리',

          orbitPosition: 0.45,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 삼각형의 외심·내심과 피타고라스 정리 (중2)',
              subUnits: [
                _SubUnitDetail(
                  code: 'GEO-2-02',
                  title: '소단원 01. 직각삼각형의 피타고라스 정리 (a² + b² = c²)',

                  prerequisitePath: '중1 삼각형의 합동 ➔ 중2 피타고라스 정리 ➔ 고1 두 점 사이의 거리',
                  coreConcepts: [
                    '외심과 내심의 성질',
                    '직각삼각형 빗변의 제곱은 나머지 두 변의 제곱의 합과 같음',
                  ],
                  problemTypes: ['[유형 01] 피타고라스 정리를 이용한 직각삼각형 변의 길이 구하기'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_pythagoras',
          gradeLabel: '중3',
          name: '삼각비·원의 성질',
          majorUnitTitle: '[중3 도형과 측정] 삼각비(sin, cos, tan) · 원과 현·접선의 성질',

          orbitPosition: 0.70,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 원의 중심과 현의 수직이등분선 (중3)',
              subUnits: [
                _SubUnitDetail(
                  code: 'GEO-3-02',
                  title: '소단원 01. 원의 현의 길이와 피타고라스 정리',

                  prerequisitePath:
                      '중2 피타고라스 정리 ➔ 중3 원과 직선 ➔ 고1 원의 방정식 (여기를 하기!)',
                  coreConcepts: [
                    '원의 중심에서 현에 내린 수선은 그 현을 이등분함',
                    'r² = d² + (l/2)²',
                  ],
                  problemTypes: ['[유형 01] 원이 직선에 의해 잘린 현의 길이 4√5 활용하기'],
                ),
              ],
            ),
          ],
        ),
        _SatelliteUnitData(
          id: 'sat_circle_eq',
          gradeLabel: '고1',
          name: '원의 방정식',
          majorUnitTitle: '[고1 공통수학2] 도형의 방정식 · 원과 직선',

          orbitPosition: 0.90,
          middleUnits: [
            _MiddleUnitData(
              title: '중단원 1. 원과 직선의 위치 관계',
              subUnits: [
                _SubUnitDetail(
                  code: 'STP-3-01',
                  title: '소단원 01. 점과 직선 사이의 거리 공식과 현의 길이',

                  prerequisitePath: '관련 선수개념: 중3 원과 현의 성질 · 중1 일차방정식 이항',
                  coreConcepts: [
                    '점과 직선 사이의 거리 d = |ax₁+by₁+c|/√(a²+b²)',
                    '절댓값 기호 누락 방지',
                  ],
                  problemTypes: [
                    '[유형 01] 원 (x-1)²+(y-1)²=25와 직선이 만드는 현의 길이로 k 구하기',
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
}

List<ConceptCheckItem> curriculumConceptChecklist() {
  final result = <ConceptCheckItem>[];
  for (final planet in _curriculumPlanets()) {
    for (final satellite in planet.satellites) {
      final label = satellite.gradeLabel;
      final grade = label == '초등'
          ? 6
          : label.startsWith('중')
          ? 6 + (int.tryParse(label.substring(1, 2)) ?? 1)
          : label == '고1'
          ? 10
          : 11;
      for (int m = 0; m < satellite.middleUnits.length; m++) {
        final middle = satellite.middleUnits[m];
        for (final unit in middle.subUnits) {
          for (int i = 0; i < unit.coreConcepts.length; i++) {
            result.add(
              ConceptCheckItem(
                id: '${planet.id}:${satellite.id}:$m:${unit.code}:$i',
                planetId: planet.id,
                area: planet.name,
                unit: unit.title,
                title: unit.coreConcepts[i],
                grade: grade,
              ),
            );
          }
        }
      }
    }
  }
  result.sort((a, b) => a.grade.compareTo(b.grade));
  return result;
}

class SkillTreeTab extends StatefulWidget {
  final VoidCallback onExperienceChanged;
  final LearningRepository? repository;

  const SkillTreeTab({
    super.key,
    required this.onExperienceChanged,
    this.repository,
  });

  @override
  State<SkillTreeTab> createState() => _SkillTreeTabState();
}

class _SkillTreeTabState extends State<SkillTreeTab>
    with SingleTickerProviderStateMixin {
  static const _purple = Color(0xFF7C5CFA);
  static const _lightPurple = Color(0xFFF3EEFF);
  static const _textColor = Color(0xFF171717);
  static const _mutedColor = Color(0xFF777777);
  static const _outlineDark = Color(0xFF1A0F2E);

  late final AnimationController _twinkleController;

  int _topModeIndex = 0;
  String _selectedGradeZone = '전학년 계통도';
  static const _gradeZones = <String>[
    '전학년 계통도',
    '중1',
    '중2',
    '중3',
    '고1',
    '고2·고3',
    '초등구역 (초1~초6)',
    '중등구역 (중1~중3)',
    '고등구역 (고1~고3)',
  ];

  int? _selectedPlanetIndex;
  int _selectedSatelliteIndex = 0;
  int _expandedMiddleUnitIndex = 0;
  int _cascadeKeySeed = 0;

  late final _repo = widget.repository ?? LearningRepository();
  ConceptCheckSnapshot _conceptChecks = const ConceptCheckSnapshot();
  StudentKnowledge? _knowledge;
  bool _knowledgeLoading = true;
  String? _knowledgeError;
  int _knowledgeRequest = 0;

  @override
  void initState() {
    super.initState();
    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    LearningRepository.progressRevision.addListener(_loadReportState);
    _loadReportState();
    _loadConceptChecks();
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_loadReportState);
    _twinkleController.dispose();
    super.dispose();
  }

  Future<void> _loadConceptChecks() async {
    try {
      final me = await _repo.get('/api/v1/users/me');
      if (me['id'] is! int) return;
      final data = await ConceptCheckStore().load(me['id']);
      if (mounted) setState(() => _conceptChecks = data);
    } catch (_) {}
  }

  Future<void> _openConceptTest() async {
    final result = await showConceptLevelTest(
      context,
      concepts: curriculumConceptChecklist(),
      repository: _repo,
    );
    if (!mounted) return;
    if (result != null) setState(() => _conceptChecks = result);
    await _loadConceptChecks();
    widget.onExperienceChanged();
  }

  Future<void> _openSatelliteTest(_SatelliteUnitData satellite) async {
    final result = await showConceptLevelTest(
      context,
      concepts: curriculumConceptChecklist(),
      repository: _repo,
      satelliteId: satellite.id,
    );
    if (!mounted) return;
    if (result != null) setState(() => _conceptChecks = result);
    widget.onExperienceChanged();
  }

  Future<void> _openExpandedGalaxy() async {
    final concepts = curriculumConceptChecklist();
    final planets = _buildPlanetsData();
    final result = await showDialog<GalaxySelection>(
      context: context,
      barrierColor: const Color(0x990E0823),
      builder: (_) => ExpandedGalaxyDialog(
        snapshot: _conceptChecks,
        planets: [
          for (final p in planets)
            GalaxyPlanetItem(
              id: p.id,
              name: p.name,
              primaryColor: p.primaryColor,
              secondaryColor: p.secondaryColor,
              concepts: concepts.where((c) => c.planetId == p.id).toList(),
            ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    if (result.startTest) {
      await _openConceptTest();
    } else if (result.planetIndex != null) {
      _enterPlanetOrbit(result.planetIndex!);
    }
  }

  int _planetReviewCount(_CurriculumPlanetData planet) => _conceptChecks
      .answers
      .entries
      .where(
        (e) =>
            e.key.startsWith('${planet.id}:') &&
            ['unsure', 'unknown'].contains(e.value),
      )
      .length;
  String _planetCheckLabel(_CurriculumPlanetData planet) {
    final checked = _conceptChecks.answers.keys
        .where((id) => id.startsWith('${planet.id}:'))
        .length;
    return checked == 0
        ? '개념 체크 전'
        : '자가 체크 $checked개 · 복습 ${_planetReviewCount(planet)}개';
  }

  Widget _buildConceptCheckCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: _openConceptTest,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _lightPurple,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const CrewmateMascotBadge(size: 46, suitColor: Color(0xFFCBB2FC)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '내 개념 레벨테스트',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _purple,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _conceptChecks.answers.isEmpty
                          ? '배웠던 개념, 얼마나 기억하고 있나요?'
                          : '${_conceptChecks.answers.length}개 개념을 체크했어요. 이어서 탐사해 볼까요?',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: _mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _purple),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _openExpandedGalaxy,
        icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
        label: const Text('우주 전체 맵 크게 보기'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _purple,
          side: const BorderSide(color: Color(0xFFDCCFF7)),
          padding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const SizedBox(height: 16),
    ],
  );

  Future<void> _loadReportState() async {
    final request = ++_knowledgeRequest;
    setState(() {
      _knowledgeLoading = true;
      _knowledgeError = null;
    });
    try {
      final knowledge = await StudentKnowledge.load(_repo);
      if (!mounted || request != _knowledgeRequest) return;
      setState(() {
        _knowledge = knowledge;
        _knowledgeLoading = false;
      });
    } catch (error) {
      if (!mounted || request != _knowledgeRequest) return;
      setState(() {
        _knowledge = null;
        _knowledgeLoading = false;
        _knowledgeError = learningError(error);
      });
    }
  }

  String _satelliteLabel(_SatelliteUnitData satellite) {
    if (_knowledgeLoading) return '확인 중';
    if (_knowledgeError != null) return '연결 확인';
    final concepts = _knowledge?.conceptsForSatellite(satellite.id) ?? [];
    if (concepts.isEmpty) return '준비 중';
    return concepts.any(
          (c) =>
              StudentKnowledge.score(_knowledge!.conceptStates[c['code']]) !=
              null,
        )
        ? '숙련도 보기'
        : '아직 평가 전';
  }

  bool _matchesSelectedGrade(String itemGrade) {
    if (_selectedGradeZone == '전학년 계통도') return true;
    if (_selectedGradeZone.startsWith('초등')) return itemGrade == '초등';
    if (_selectedGradeZone.startsWith('중등')) {
      return itemGrade == '중1' || itemGrade == '중2' || itemGrade == '중3';
    }
    if (_selectedGradeZone.startsWith('고등')) {
      return itemGrade == '고1' || itemGrade == '고2·고3';
    }
    return itemGrade == _selectedGradeZone;
  }

  List<_SatelliteUnitData> _getFilteredSatellites(
    _CurriculumPlanetData planet,
  ) {
    return planet.satellites
        .where((s) => _matchesSelectedGrade(s.gradeLabel))
        .toList();
  }

  void _enterPlanetOrbit(
    int planetIndex, {
    int satIndex = 0,
    int midIndex = 0,
  }) {
    setState(() {
      _selectedPlanetIndex = planetIndex;
      _selectedSatelliteIndex = satIndex;
      _expandedMiddleUnitIndex = midIndex;
      _cascadeKeySeed++;
    });
  }

  List<_CurriculumPlanetData> _buildPlanetsData() => _curriculumPlanets();

  @override
  Widget build(BuildContext context) {
    final planets = _buildPlanetsData();

    return ColoredBox(
      color: const Color(0xFFF9F9FB),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECEAF5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTopSegmentButton(
                          title: '🪐 우주 계통도 스킬트리',
                          active: _topModeIndex == 0,
                          onTap: () => setState(() => _topModeIndex = 0),
                        ),
                      ),
                      Expanded(
                        child: _buildTopSegmentButton(
                          title: '📊 학습 리포트·친구',
                          active: _topModeIndex == 1,
                          onTap: () => setState(() => _topModeIndex = 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _topModeIndex == 0
                    ? AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final scale = Tween<double>(
                            begin: 0.84,
                            end: 1.0,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(scale: scale, child: child),
                          );
                        },
                        child: _selectedPlanetIndex == null
                            ? _buildGalaxyOverviewList(planets)
                            : _buildPlanetOrbitDetailList(planets),
                      )
                    : StudentReportPanel(
                        repository: _repo,
                        knowledge: _knowledge,
                        loading: _knowledgeLoading,
                        error: _knowledgeError,
                        onRefresh: _loadReportState,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSegmentButton({
    required String title,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: active ? _purple : _mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _buildGalaxyOverviewList(List<_CurriculumPlanetData> planets) {
    return ListView(
      key: const ValueKey<String>('galaxy_overview'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        _buildConceptCheckCard(),
        if (_knowledgeLoading) const LinearProgressIndicator(color: _purple),
        if (_knowledgeError != null)
          KnowledgeNotice(message: _knowledgeError!, onRetry: _loadReportState),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '한국 교육과정 우주 계통도',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _textColor,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '행성을 누르면 줌인되면서 단원 위성과 개념이 촤라락 펼쳐져요!',
                    style: TextStyle(fontSize: 11.5, color: _mutedColor),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF231754),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _outlineDark, width: 2.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGradeZone,
                  isDense: true,
                  dropdownColor: const Color(0xFF231754),
                  icon: const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Color(0xFFFFD54F),
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFFD54F),
                  ),
                  items: _gradeZones
                      .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedGradeZone = v;
                        _selectedSatelliteIndex = 0;
                        _expandedMiddleUnitIndex = 0;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['전학년 계통도', '중1', '중2', '중3', '고1', '고2·고3'].map((g) {
              final active = _selectedGradeZone == g;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    g == '전학년 계통도' ? '🌌 전학년' : '🎯 $g만 보기',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: active ? Colors.white : _textColor,
                    ),
                  ),
                  selected: active,
                  selectedColor: _purple,
                  backgroundColor: Colors.white,
                  onSelected: (_) {
                    setState(() {
                      _selectedGradeZone = g;
                      _selectedSatelliteIndex = 0;
                      _expandedMiddleUnitIndex = 0;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _enterPlanetOrbit(0, satIndex: 0, midIndex: 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF39227A), Color(0xFF21134D)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _outlineDark, width: 3.0),
            ),
            child: const Row(
              children: [
                CrewmateMascotBadge(suitColor: Color(0xFFFFEE58), size: 40),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '크루원 긴급 미션: 지금 여기를 먼저 수리해요!',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFFEE58),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '[변화와 관계 행성] 중1 이항 부호 ➔ 고1 나머지정리·복소수 즉시 출동 ▶',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2x2 Grid 구조 어몽어스/카툰 성운 맵 (겹침 0% 보장)
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _outlineDark, width: 3.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x331A0F2E),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _twinkleController,
                  builder: (context, _) => CustomPaint(
                    painter: CartoonSpaceBackgroundPainter(
                      twinkleValue: _twinkleController.value,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xDD1A0F2E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFB388FF),
                            width: 1.8,
                          ),
                        ),
                        child: Text(
                          '🛸 $_selectedGradeZone · 행성을 터치해 궤도로 줌인하세요!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildCartoonPlanetTile(
                            index: 0,
                            planet: planets[0],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCartoonPlanetTile(
                            index: 1,
                            planet: planets[1],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildCartoonPlanetTile(
                            index: 2,
                            planet: planets[2],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCartoonPlanetTile(
                            index: 3,
                            planet: planets[3],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE140C29),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF7C5CFA),
                          width: 2.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          const CrewmateMascotBadge(
                            suitColor: Color(0xFF4DD0E1),
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '우주 탐사 브리핑: "현재 [$_selectedGradeZone] 단원만 표시 중! 행성을 누르면 세부 단원이 촤라락 펼쳐집니다."',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '교육과정 4대 영역별 개념 탐사 ($_selectedGradeZone)',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: _textColor,
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(planets.length, (idx) {
          final p = planets[idx];
          final filteredSats = _getFilteredSatellites(p);
          final satNames = filteredSats
              .map((s) => s.name.replaceAll('', ''))
              .join(' · ');

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                onTap: () => _enterPlanetOrbit(idx),
                leading: CircleAvatar(
                  backgroundColor: p.primaryColor.withAlpha(40),
                  child: Icon(Icons.public_rounded, color: p.primaryColor),
                ),
                title: Text(
                  '${p.name} 행성 (${satNames.isNotEmpty ? satNames : p.subtitle})',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  _planetCheckLabel(p),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _purple,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCartoonPlanetTile({
    required int index,
    required _CurriculumPlanetData planet,
  }) {
    final filteredSats = _getFilteredSatellites(planet);
    final unitSummaryText = filteredSats.isEmpty
        ? '해당 학년 단원 없음'
        : filteredSats.map((s) => s.name.replaceAll('', '')).join(' · ');

    return GestureDetector(
      onTap: () => _enterPlanetOrbit(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x88180E38),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: planet.primaryColor.withAlpha(160),
            width: 2.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _planetReviewCount(planet) > 0
                    ? const Color(0xFFFF4B4B)
                    : _purple,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _outlineDark, width: 2.0),
              ),
              child: Text(
                _planetCheckLabel(planet),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Stack(
              alignment: Alignment.center,
              children: [
                CartoonPlanetOrb(
                  planetId: planet.id,
                  primaryColor: planet.primaryColor,
                  secondaryColor: planet.secondaryColor,
                  size: 80,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _outlineDark.withAlpha(200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    planet.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xEE120A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _outlineDark, width: 2.0),
              ),
              child: Text(
                unitSummaryText,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFEDE7F6),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanetOrbitDetailList(List<_CurriculumPlanetData> planets) {
    final planet = planets[_selectedPlanetIndex!];
    final filteredSatellites = _getFilteredSatellites(planet);
    final activeSatellites = filteredSatellites.isNotEmpty
        ? filteredSatellites
        : planet.satellites;
    final safeSatIndex = _selectedSatelliteIndex.clamp(
      0,
      activeSatellites.length - 1,
    );
    final selectedSatellite = activeSatellites[safeSatIndex];

    return ListView(
      key: ValueKey<String>(
        'orbit_${planet.id}_${_selectedGradeZone}_$_cascadeKeySeed',
      ),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: _openExpandedGalaxy,
              icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
              label: const Text(
                '우주 전체 맵으로 줌아웃',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF231754),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _outlineDark, width: 2),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGradeZone,
                  isDense: true,
                  dropdownColor: const Color(0xFF231754),
                  icon: const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Color(0xFFFFD54F),
                  ),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFFD54F),
                  ),
                  items: _gradeZones
                      .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedGradeZone = v;
                        _selectedSatelliteIndex = 0;
                        _expandedMiddleUnitIndex = 0;
                        _cascadeKeySeed++;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 265,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _outlineDark, width: 3.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: CartoonSpaceBackgroundPainter(
                  twinkleValue: _twinkleController.value,
                ),
              ),
              CustomPaint(
                painter: CartoonOrbitArcPainter(
                  orbitColor: planet.primaryColor,
                  secondaryColor: planet.secondaryColor,
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🪐 ${planet.name} 궤도 ($_selectedGradeZone · ${activeSatellites.length}개 단원 위성)',
                      style: const TextStyle(
                        color: Color(0xFFFFEE58),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '위성을 터치하면 아래에 중단원·소단원·개념 영상이 촤라락 펼쳐집니다!',
                      style: TextStyle(color: Colors.white70, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              ...List.generate(activeSatellites.length, (sIdx) {
                final sat = activeSatellites[sIdx];
                final isSelected = sIdx == safeSatIndex;
                final t = activeSatellites.length == 1
                    ? 0.5
                    : sIdx / (activeSatellites.length - 1);
                final alignX = -0.74 + (t * 1.48);
                final alignY = 0.58 - (t * 0.78);

                const badgeColor = _purple;
                final statusBadge = _satelliteLabel(sat);

                return Align(
                  alignment: Alignment(alignX, alignY),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey<String>(
                      'sat_${sat.id}_${_selectedGradeZone}_$_cascadeKeySeed',
                    ),
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 350 + (sIdx * 110)),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      );
                    },
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedSatelliteIndex = sIdx;
                          _expandedMiddleUnitIndex = 0;
                          _cascadeKeySeed++;
                        });
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _outlineDark,
                                width: 2.0,
                              ),
                            ),
                            child: Text(
                              '${sat.gradeLabel} · $statusBadge',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: isSelected ? 80 : 66,
                            height: isSelected ? 80 : 66,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFFFEE58)
                                    : _outlineDark,
                                width: isSelected ? 4.0 : 3.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: badgeColor.withAlpha(150),
                                  blurRadius: isSelected ? 16 : 6,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(5),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      sat.name.replaceAll('', ''),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color: _textColor,
                                        height: 1.15,
                                      ),
                                    ),

                                    Text(
                                      '개념 체크',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        color: badgeColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCascadingRevealItem(
          index: 0,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _outlineDark, width: 2.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _lightPurple,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '대단원 위성 · ${selectedSatellite.gradeLabel} 과정',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _purple,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '서버 진단으로 확인',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: _purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  selectedSatellite.majorUnitTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _openSatelliteTest(selectedSatellite),
                  icon: const Icon(Icons.route_rounded, size: 18),
                  label: const Text('이 단원의 선수개념 체크'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_knowledge
                        ?.conceptsForSatellite(selectedSatellite.id)
                        .isNotEmpty ??
                    false)
                  for (final concept in _knowledge!.conceptsForSatellite(
                    selectedSatellite.id,
                  ))
                    KnowledgeConceptCard(
                      concept: concept,
                      knowledge: _knowledge!,
                      repository: _repo,
                    )
                else ...[
                  KnowledgeNotice(
                    message: _knowledgeError != null
                        ? '학습 상태를 확인하지 못했어요. 아래 내용은 교육과정 안내예요.'
                        : '이 단원의 문제·영상은 준비 중이에요. 아래에서 개념을 미리 살펴볼 수 있어요.',
                  ),
                  ...List.generate(selectedSatellite.middleUnits.length, (
                    mIdx,
                  ) {
                    final mid = selectedSatellite.middleUnits[mIdx];
                    final isExpanded = _expandedMiddleUnitIndex == mIdx;

                    return _buildCascadingRevealItem(
                      index: mIdx + 1,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F9FC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isExpanded
                                ? _purple
                                : const Color(0xFFE2E8F0),
                            width: isExpanded ? 2.0 : 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => setState(
                                () => _expandedMiddleUnitIndex = isExpanded
                                    ? -1
                                    : mIdx,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isExpanded
                                          ? Icons.folder_open_rounded
                                          : Icons.folder_rounded,
                                      color: _purple,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        mid.title,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: _textColor,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      color: _mutedColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: !isExpanded
                                  ? const SizedBox.shrink()
                                  : Column(
                                      children: mid.subUnits
                                          .map(_buildSubUnitCard)
                                          .toList(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCascadingRevealItem({
    required int index,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('cascade_${_cascadeKeySeed}_$index'),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 360 + (index * 90)),
      curve: Curves.easeOutCubic,
      builder: (context, val, inner) {
        return Opacity(
          opacity: val.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - val) * 28),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildSubUnitCard(_SubUnitDetail sub) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sub.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _lightPurple,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '교육과정 안내',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: _purple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _lightPurple,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '🧭 관련 개념: ${sub.prerequisitePath}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _purple,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '📘 배워야 할 필수 개념',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 6),
          ...sub.coreConcepts.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $c',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '🧩 자주 나오는 대표 유형',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sub.problemTypes
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
