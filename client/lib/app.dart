import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'screens/home.dart';

class Vpn13ClientApp extends StatelessWidget {
  const Vpn13ClientApp({super.key});

  static const navy = Color(0xFFF0F3F4);
  static const blue = Color(0xFF39A98B);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.dark,
      surface: const Color(0xFF35434C),
    );

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF252F38),
        cardColor: const Color(0xFF35434C),
        dividerColor: const Color(0xFF46555E),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: navy,
          elevation: 0,
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: _AccessGate(),
      ),
    );
  }
}

class _AccessGate extends StatefulWidget {
  const _AccessGate();

  @override
  State<_AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<_AccessGate> {
  static const _storage = FlutterSecureStorage();
  static const _accessCodeKey = 'vpn13_access_code';

  bool _checking = true;
  bool _authorized = false;
  String? _gateMessage;

  @override
  void initState() {
    super.initState();
    _restoreAccess();
  }

  Future<bool> _validateCode(String code) async {
    final response = await http
        .post(
          Uri.parse(AppConfig.serversJsonUrl),
          headers: const {
            'Content-Type': 'application/json; charset=UTF-8',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'action': 'validate',
            'code': code,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Validation server returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw const FormatException('Invalid validation response');
    }

    return decoded['valid'] == true;
  }

  Future<void> _restoreAccess() async {
    try {
      final savedCode = await _storage.read(key: _accessCodeKey);
      if (savedCode == null || savedCode.isEmpty) {
        return;
      }

      final valid = await _validateCode(savedCode);
      if (valid) {
        _authorized = true;
      } else {
        await _storage.delete(key: _accessCodeKey);
        _gateMessage = 'کد ذخیره‌شده دیگر معتبر نیست؛ کد جدید را وارد کنید.';
      }
    } catch (_) {
      _gateMessage =
          'برای بررسی اعتبار کد، اتصال اینترنت لازم است. پس از اتصال دوباره تلاش کنید.';
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<bool> _authenticate(String code) async {
    final valid = await _validateCode(code);
    if (!valid) return false;

    await _storage.write(key: _accessCodeKey, value: code);
    if (mounted) {
      setState(() => _authorized = true);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _authorized
        ? const HomeScreen()
        : _LoginScreen(
            onSubmit: _authenticate,
            initialMessage: _gateMessage,
          );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.onSubmit, this.initialMessage});

  final Future<bool> Function(String code) onSubmit;
  final String? initialMessage;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialMessage;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'کد ورود را وارد کنید.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final accepted = await widget.onSubmit(code);
      if (!accepted && mounted) {
        setState(() => _error = 'کد ورود صحیح نیست یا اعتبار آن پایان یافته است.');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _error = 'پاسخ سرور دریافت نشد؛ اتصال اینترنت را بررسی کنید.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ارتباط با سرور برقرار نشد؛ اینترنت را بررسی و دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF39A98B),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/icon/vpn13_icon.jpg',
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'VPN13',
                    style: TextStyle(
                      color: Color(0xFFF0F3F4),
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'برای ورود، کد دسترسی را وارد کنید',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFB5C0C6),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xFF35434C),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF46555E)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10171C).withValues(alpha: 0.22),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'کد ورود',
                          style: TextStyle(
                            color: Color(0xFFF0F3F4),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _controller,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: 'کد دسترسی را وارد کنید',
                            hintStyle: const TextStyle(
                              color: Color(0xFF91A0A8),
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF293740),
                            prefixIcon: const Icon(
                              Icons.key_rounded,
                              color: Color(0xFFB5C0C6),
                            ),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: const Color(0xFFB5C0C6),
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Color(0xFF53636B),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Color(0xFF53636B),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Color(0xFF39A98B),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFFA39A),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF39A98B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 21,
                                    height: 21,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'ورود به برنامه',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'دسترسی خصوصی  •  VPN13',
                    style: TextStyle(
                      color: Color(0xFF91A0A8),
                      fontSize: 11,
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
}
