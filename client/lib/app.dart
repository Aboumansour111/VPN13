import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      surface: const Color(0xFF202E37),
    );

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF10191F),
        cardColor: const Color(0xFF202E37),
        dividerColor: const Color(0xFF46555E),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: navy,
          elevation: 0,
        ),
        splashFactory: InkSparkle.splashFactory,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          },
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
  static const _accessCheckedAtKey = 'vpn13_access_checked_at';
  static const _accessCheckInterval = Duration(days: 7);

  bool _checking = true;
  bool _authorized = false;
  String? _gateMessage;

  @override
  void initState() {
    super.initState();
    _restoreAccess();
  }

  Future<bool> _validateCode(String code) async {
    final uri = Uri.parse(AppConfig.serversJsonUrl);
    final client = http.Client();

    try {
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll(const {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json',
        })
        ..body = jsonEncode({
          'action': 'validate',
          'code': code,
        });

      var streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 20));

      // Google Apps Script redirects ContentService responses to
      // script.googleusercontent.com. Fetch that one-time response URL
      // with GET instead of letting the HTTP client rewrite the POST.
      if ([301, 302, 303, 307, 308].contains(streamed.statusCode)) {
        final location = streamed.headers['location'];
        if (location == null || location.isEmpty) {
          throw const FormatException(
            'Validation redirect did not include a Location header',
          );
        }

        final redirectUri = uri.resolve(location);
        streamed = await client
            .send(http.Request('GET', redirectUri))
            .timeout(const Duration(seconds: 20));
      }

      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(
          'Validation server returned HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true ||
          decoded['valid'] is! bool) {
        throw const FormatException('Invalid validation response');
      }

      return decoded['valid'] as bool;
    } finally {
      client.close();
    }
  }

  Future<void> _restoreAccess() async {
    try {
      final savedCode = await _storage.read(key: _accessCodeKey);
      if (savedCode == null || savedCode.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final checkedAtMs = prefs.getInt(_accessCheckedAtKey);
      final checkedAt = checkedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(checkedAtMs);
      final now = DateTime.now();

      // Reuse the locally stored authorization for seven days.
      if (checkedAt != null && now.difference(checkedAt) < _accessCheckInterval) {
        _authorized = true;
        return;
      }

      try {
        final valid = await _validateCode(savedCode);
        if (valid) {
          await prefs.setInt(_accessCheckedAtKey, now.millisecondsSinceEpoch);
          _authorized = true;
        } else {
          await _storage.delete(key: _accessCodeKey);
          await prefs.remove(_accessCheckedAtKey);
          _gateMessage = 'کد ذخیره‌شده دیگر معتبر نیست؛ کد جدید را وارد کنید.';
        }
      } catch (_) {
        // Network failure must not lock out a previously authenticated user.
        _authorized = true;
        _gateMessage = 'بررسی دوره‌ای کد به اینترنت دسترسی نداشت؛ از کد ذخیره‌شده استفاده شد.';
      }
    } catch (_) {
      _gateMessage = 'بازیابی اطلاعات ورود انجام نشد؛ دوباره برنامه را باز کنید.';
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<bool> _authenticate(String code) async {
    final valid = await _validateCode(code);
    if (!valid) return false;

    await _storage.write(key: _accessCodeKey, value: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accessCheckedAtKey, DateTime.now().millisecondsSinceEpoch);
    if (mounted) {
      setState(() => _authorized = true);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        reverseDuration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: _checking
            ? const Scaffold(
                key: ValueKey('access-checking'),
                body: Center(child: CircularProgressIndicator()),
              )
            : _authorized
                ? const HomeScreen(key: ValueKey('home-screen'))
                : _LoginScreen(
                    key: const ValueKey('login-screen'),
                    onSubmit: _authenticate,
                    initialMessage: _gateMessage,
                  ),
      );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({super.key, required this.onSubmit, this.initialMessage});

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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF142B36),
              Color(0xFF101F28),
              Color(0xFF0B171F),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 410),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 17, 18, 19),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            Color(0xFF263F4B),
                            Color(0xFF142832),
                            Color(0xFF10212B),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Color(0xFF4A7D82)),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF36DCC5).withValues(alpha: .08),
                            blurRadius: 24,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'اللهم صل علی محمد و آل محمد الائمه و المهدیین و سلم تسلیما',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF9BE9DF),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 17),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(17),
                            child: Image.asset(
                              'assets/icon/vpn13_icon.jpg',
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'VPN13',
                            style: TextStyle(
                              color: Color(0xFFF1FFFF),
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .5,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'اتصال امن و پایدار',
                            style: TextStyle(
                              color: Color(0xFF9BB8C1),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B303A),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFF35545E)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'ورود به برنامه',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFEAFBFB),
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'برای ادامه، کد دسترسی خود را وارد کنید',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF9BB8C1),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'کد ورود',
                            style: TextStyle(
                              color: Color(0xFFEAFBFB),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 9),
                          TextField(
                            controller: _controller,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            onSubmitted: (_) => _submit(),
                            style: const TextStyle(
                              color: Color(0xFFEAFBFB),
                              fontSize: 15,
                              letterSpacing: 1.2,
                            ),
                            decoration: InputDecoration(
                              hintText: 'کد دسترسی را وارد کنید',
                              hintStyle: const TextStyle(
                                color: Color(0xFF91AAB2),
                                fontSize: 12,
                                letterSpacing: 0,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF12232C),
                              prefixIcon: const Icon(
                                Icons.key_rounded,
                                color: Color(0xFF80E5D4),
                                size: 19,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscure = !_obscure,
                                ),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0xFF9BB8C1),
                                  size: 19,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF45636D),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF45636D),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF80E5D4),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 11),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFA39A),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 17),
                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF168F79),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFF31534F),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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
                    const SizedBox(height: 17),
                    const Text(
                      'دسترسی خصوصی  •  VPN13',
                      style: TextStyle(
                        color: Color(0xFF819BA4),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
