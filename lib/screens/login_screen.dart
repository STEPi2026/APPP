import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/stepi_logo.dart';

import '../main.dart';
import '../services/api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _primaryPurple = Color(0xFF9B7EFA);
  static const _deepPurple = Color(0xFF7652FF);
  static const _lightPurple = Color(0xFFF5F1FF);
  static const _accentOrange = Color(0xFFFF8A3D);
  static const _mutedColor = Color(0xFF777777);

  bool _isSignUpMode = false;

  // 기본값은 비워 둡니다.
  // 회원가입한 실제 계정으로 로그인하세요.
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  bool _emailChecked = false;
  String? _checkedEmail;

  bool _agreeTerms = false;
  bool _agreePrivacy = false;

  bool _submitting = false;
  bool _checkingEmail = false;
  bool _obscurePassword = true;

  String? _errorText;

  bool get _busy => _submitting || _checkingEmail;

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  void _showToast(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(backgroundColor: _deepPurple, content: Text(message)),
      );
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _errorText = message);
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException) {
      return '서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.';
    }

    if (error is ApiException) {
      switch (error.statusCode) {
        case 400:
          return '입력한 내용을 확인해주세요.';
        case 401:
          return '인증에 실패했습니다. 다시 로그인해주세요.';
        case 403:
          return '이 기능에 접근할 권한이 없습니다.';
        case 404:
          return '요청한 API를 찾을 수 없습니다. 서버 주소를 확인해주세요.';
        case 409:
          return '이미 등록된 정보입니다. 입력한 내용을 확인해주세요.';
        case 422:
          return '입력한 정보의 형식이나 길이를 확인해주세요.';
        case 429:
          return '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.';
        default:
          if (error.statusCode >= 500) {
            return '서버에서 오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
          }
          return error.message;
      }
    }

    return '서버에 연결하지 못했습니다. '
        '인터넷 연결과 서버 주소를 확인해주세요. '
        '웹에서는 CORS 설정도 확인이 필요합니다.';
  }

  void _changeMode(bool signUp) {
    if (_busy) return;

    setState(() {
      _isSignUpMode = signUp;
      _errorText = null;
    });
  }

  // --------------------------------------------------
  // 이메일 중복 확인
  // --------------------------------------------------

  Future<void> _checkDuplicateEmail() async {
    if (_busy) return;

    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();

    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      _setError('올바른 이메일을 입력해주세요.');
      return;
    }

    if (!Api.isBackendConfigured) {
      _setError('서버 주소가 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _checkingEmail = true;
      _emailChecked = false;
      _checkedEmail = null;
      _errorText = null;
    });

    try {
      final result = await Api.get(
        Api.checkEmailEndpoint,
        queryParameters: {'email': email},
      );

      if (!mounted) return;

      // API 응답:
      // {"email": "...", "available": true 또는 false}
      if (result is! Map || result['available'] is! bool) {
        _setError('이메일 확인 응답 형식이 올바르지 않습니다.');
        return;
      }

      if (result['available'] != true) {
        _setError('이미 사용 중인 이메일입니다.');
        return;
      }

      // 확인 요청 중 이메일이 변경됐다면 확인 결과를 적용하지 않습니다.
      if (_emailController.text.trim() != email) {
        _setError('이메일이 변경되었습니다. 다시 중복 확인해주세요.');
        return;
      }

      setState(() {
        _emailChecked = true;
        _checkedEmail = email;
        _errorText = null;
      });

      _showToast('사용 가능한 이메일입니다.');
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        _setError('이미 사용 중인 이메일입니다.');
      } else {
        _setError(_errorMessage(e));
      }
    } catch (e) {
      _setError(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _checkingEmail = false);
      }
    }
  }

  // --------------------------------------------------
  // 로그인
  // --------------------------------------------------

  Future<void> _handleLogin() async {
    if (_busy) return;

    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      _setError('올바른 이메일을 입력해주세요.');
      return;
    }

    if (password.isEmpty) {
      _setError('비밀번호를 입력해주세요.');
      return;
    }

    if (!Api.isBackendConfigured) {
      _setError('서버 주소가 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    bool loggedIn = false;
    bool studentVerified = false;

    try {
      // 로그인 성공 시 api.dart 내부에서 두 토큰을 저장합니다.
      await Api.login(email: email, password: password);

      loggedIn = true;

      // 로그인 응답에는 role이 없으므로 내 정보 API에서 확인합니다.
      final me = await Api.getMe();
      final role = me['role']?.toString().toUpperCase();

      if (role != 'STUDENT') {
        Api.clearTokens();

        if (!mounted) return;

        if (role == 'PARENT' || role == 'TEACHER') {
          _setError('선생님/학부모 계정은 전용 WEB에서 로그인해주세요.');
          _showWebRedirectModal();
        } else {
          _setError('계정의 학생 권한을 확인하지 못했습니다.');
        }

        return;
      }

      studentVerified = true;

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (context) => const MainScreen()),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _setError(
          loggedIn
              ? '로그인 인증을 확인하지 못했습니다. 다시 시도해주세요.'
              : '이메일 또는 비밀번호가 올바르지 않습니다.',
        );
      } else {
        _setError(_errorMessage(e));
      }
    } catch (e) {
      _setError(_errorMessage(e));
    } finally {
      // 학생 확인까지 완료되지 않았다면 인증 정보를 남기지 않습니다.
      if (loggedIn && !studentVerified) {
        Api.clearTokens();
      }

      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  // --------------------------------------------------
  // 회원가입
  // --------------------------------------------------

  Future<void> _handleSignUp() async {
    if (_busy) return;

    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _passwordConfirmController.text;

    if (name.isEmpty || name.length > 100) {
      _setError('이름은 1~100자로 입력해주세요.');
      return;
    }

    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      _setError('올바른 이메일을 입력해주세요.');
      return;
    }

    if (!_emailChecked || _checkedEmail != email) {
      _setError('이메일 중복 확인을 먼저 진행해주세요.');
      return;
    }

    if (password.length < 8 || password.length > 128) {
      _setError('비밀번호는 8~128자로 입력해주세요.');
      return;
    }

    if (password != confirm) {
      _setError('비밀번호가 일치하지 않습니다.');
      return;
    }

    if (!_agreeTerms || !_agreePrivacy) {
      _setError('필수 약관에 모두 동의해주세요.');
      return;
    }

    if (!Api.isBackendConfigured) {
      _setError('서버 주소가 설정되지 않았습니다.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      // API 명세에 있는 회원가입 필드만 전송합니다.
      await Api.signup(
        email: email,
        password: password,
        name: name,
        role: 'STUDENT',
      );

      if (!mounted) return;

      setState(() {
        _isSignUpMode = false;
        _emailChecked = false;
        _checkedEmail = null;
        _agreeTerms = false;
        _agreePrivacy = false;
        _errorText = null;
      });

      _passwordConfirmController.clear();

      // 이메일과 비밀번호 입력은 유지하므로 바로 로그인할 수 있습니다.
      _showToast('회원가입이 완료되었습니다. 로그인해주세요!');
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        if (!mounted) return;

        setState(() {
          _emailChecked = false;
          _checkedEmail = null;
          _errorText = '이미 가입된 이메일입니다. 로그인해주세요.';
        });
      } else {
        _setError(_errorMessage(e));
      }
    } catch (e) {
      _setError(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  // --------------------------------------------------
  // 선생님 / 학부모 안내
  // --------------------------------------------------

  void _showWebRedirectModal() {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            '선생님 · 학부모 WEB 안내',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '이 앱은 학생용입니다.\n\n'
            '선생님과 학부모님은 전용 WEB 대시보드를 이용해주세요.',
            style: TextStyle(fontSize: 14, height: 1.55),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(backgroundColor: _deepPurple),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  // --------------------------------------------------
  // 화면
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightPurple,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -24),
                    child: const Center(
                      child: StepILogo(width: 248, borderRadius: 14),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '로그인하여 내게 딱 맞는 역추적 학습을 시작하세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _mutedColor,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildModeTabButton(
                                title: '학생 로그인',
                                active: !_isSignUpMode,
                                onTap: () => _changeMode(false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildModeTabButton(
                                title: '회원가입',
                                active: _isSignUpMode,
                                onTap: () => _changeMode(true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        if (_isSignUpMode) ...[
                          TextField(
                            controller: _nameController,
                            enabled: !_busy,
                            decoration: _inputDecoration(
                              label: '이름',
                              hint: '홍길동',
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _emailController,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                onChanged: (_) {
                                  setState(() {
                                    _emailChecked = false;
                                    _checkedEmail = null;
                                    _errorText = null;
                                  });
                                },
                                decoration: _inputDecoration(
                                  label: '이메일',
                                  hint: 'student@example.com',
                                  icon: Icons.alternate_email_rounded,
                                ),
                              ),
                            ),
                            if (_isSignUpMode) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : _checkDuplicateEmail,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _emailChecked
                                        ? const Color(0xFF278B4B)
                                        : _deepPurple,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    _checkingEmail
                                        ? '확인 중'
                                        : _emailChecked
                                        ? '확인완료'
                                        : '중복확인',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _passwordController,
                          enabled: !_busy,
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) {
                            if (!_isSignUpMode && !_busy) {
                              _handleLogin();
                            }
                          },
                          decoration: _inputDecoration(
                            label: '비밀번호',
                            hint: _isSignUpMode
                                ? '8~128자로 입력해주세요'
                                : '비밀번호를 입력해주세요',
                            icon: Icons.lock_outline_rounded,
                            suffix: IconButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                        ),

                        if (_isSignUpMode) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordConfirmController,
                            enabled: !_busy,
                            obscureText: _obscurePassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _inputDecoration(
                              label: '비밀번호 확인',
                              hint: '비밀번호를 한 번 더 입력해주세요',
                              icon: Icons.lock_reset_rounded,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildTermsAgreementBox(),
                        ],

                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF5F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _errorText!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE53E3E),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: _busy
                              ? null
                              : _isSignUpMode
                              ? _handleSignUp
                              : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _submitting
                                ? (_isSignUpMode ? '가입 중입니다...' : '로그인 중입니다...')
                                : (_isSignUpMode ? '학생 계정으로 가입하기' : '로그인'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _busy ? null : _showWebRedirectModal,
                    child: const Text(
                      '선생님 / 학부모이신가요? (전용 WEB 안내)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _deepPurple,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeTabButton({
    required String title,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? _lightPurple : const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? _deepPurple : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: active ? _deepPurple : _mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _buildTermsAgreementBox() {
    final allAgreed = _agreeTerms && _agreePrivacy;

    return Material(
      color: const Color(0xFFF8F9FA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAgreementRow(
              value: allAgreed,
              label: '전체 약관 동의',
              bold: true,
              onChanged: (value) {
                setState(() {
                  _agreeTerms = value ?? false;
                  _agreePrivacy = value ?? false;
                });
              },
            ),
            const Divider(height: 6),
            _buildAgreementRow(
              value: _agreeTerms,
              label: '[필수] 서비스 이용약관 동의',
              onChanged: (value) {
                setState(() {
                  _agreeTerms = value ?? false;
                });
              },
            ),
            _buildAgreementRow(
              value: _agreePrivacy,
              label: '[필수] 개인정보 처리방침 동의',
              onChanged: (value) {
                setState(() {
                  _agreePrivacy = value ?? false;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgreementRow({
    required bool value,
    required String label,
    required ValueChanged<bool?> onChanged,
    bool bold = false,
  }) {
    return MergeSemantics(
      child: InkWell(
        onTap: _busy ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: value,
                activeColor: _deepPurple,
                onChanged: _busy ? null : onChanged,
              ),
              Expanded(
                child: Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: bold ? 13 : 12,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: _primaryPurple),
      suffixIcon: suffix,
      isDense: true,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accentOrange, width: 2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
