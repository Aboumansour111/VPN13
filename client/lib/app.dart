import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'flag_asset.dart';
import 'screens/home.dart';

// Cache the login header flag to prevent visual flicker during widget rebuilds.
final ImageProvider _loginFlagImage = MemoryImage(base64Decode(vpn13FlagBase64));

class Vpn13ClientApp extends StatelessWidget {
  const Vpn13ClientApp({super.key});

  static const navy = Color(0xFF142A30);
  static const blue = Color(0xFF167D86);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
      surface: const Color(0xFFFFFFFF),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: vpn13DarkMode,
      builder: (context, isDark, _) => MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF39B9A8),
          brightness: Brightness.dark,
          surface: const Color(0xFF171F28),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1218),
        cardColor: const Color(0xFF171F28),
        dividerColor: const Color(0xFF2D3B45),
        fontFamily: 'Roboto',
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFE8EEF2),
          displayColor: const Color(0xFFE8EEF2),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF202A34),
          hintStyle: TextStyle(color: Color(0xFF9AA8B3)),
          labelStyle: TextStyle(color: Color(0xFFE8EEF2)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFFE8EEF2),
          elevation: 0,
        ),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7F8),
        cardColor: const Color(0xFFFFFFFF),
        dividerColor: const Color(0xFFE5ECEE),
        fontFamily: 'Roboto',
        textTheme: ThemeData.light().textTheme.apply(bodyColor: const Color(0xFF142A30), displayColor: const Color(0xFF142A30)),
        inputDecorationTheme: InputDecorationTheme(labelStyle: const TextStyle(color: Color(0xFF142A30)), hintStyle: const TextStyle(color: Color(0xFF71808A)), filled: true, fillColor: const Color(0xFFF7FAFA)),
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
    _restoreTheme();
  }

  Future<void> _restoreTheme() async {
    final prefs = await SharedPreferences.getInstance();
    vpn13DarkMode.value = prefs.getBool('vpn13_dark_mode') ?? false;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFE8EEF2) : const Color(0xFF142A30);
    final muted = isDark ? const Color(0xFF9AA8B3) : const Color(0xFF7B8790);
    final teal = isDark ? const Color(0xFF39B9A8) : const Color(0xFF20A39A);
    final deepTeal = isDark ? const Color(0xFF203B36) : const Color(0xFF155F68);
    final pageBackground = isDark ? const Color(0xFF0D1218) : const Color(0xFFF4F7F8);
    final cardBackground = isDark ? const Color(0xFF171F28) : Colors.white;
    final inputBackground = isDark ? const Color(0xFF202A34) : const Color(0xFFF7FAFA);
    return Scaffold(
      backgroundColor: pageBackground,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.15,
                colors: isDark ? [Color(0xFF203B36), pageBackground, pageBackground] : [Color(0xFFD8F0EC), pageBackground, pageBackground],
                stops: [0, .48, 1],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 14,
            child: SafeArea(
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image(image: _loginFlagImage, width: 44, height: 27, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 66, 22, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 410),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 86,
                        height: 86,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [teal, deepTeal]),
                          borderRadius: BorderRadius.circular(27),
                          boxShadow: [BoxShadow(color: deepTeal.withValues(alpha: .24), blurRadius: 26, offset: const Offset(0, 10))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(23),
                          child: Image.asset('assets/icon/vpn13_icon.jpg', fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('VPN13', style: TextStyle(color: ink, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.6)),
                      const SizedBox(height: 4),
                      Text('اتصال امن و پایدار', style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 30),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 23, 20, 22),
                        decoration: BoxDecoration(
                          color: cardBackground,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: isDark ? const Color(0xFF2D3B45) : const Color(0xFFDCE7E8)),
                          boxShadow: const [BoxShadow(color: Color(0x190F2A2E), blurRadius: 34, offset: Offset(0, 13))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('ورود به برنامه', textAlign: TextAlign.center, style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 7),
                            Text('برای ادامه، کد دسترسی خود را وارد کنید', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11, height: 1.8)),
                            const SizedBox(height: 23),
                            Text('کد ورود', style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 9),
                            TextField(
                              controller: _controller,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.center,
                              onSubmitted: (_) => _submit(),
                              style: TextStyle(color: ink, fontSize: 16, letterSpacing: 2),
                              decoration: InputDecoration(
                                hintText: 'کد دسترسی را وارد کنید',
                                hintStyle: const TextStyle(color: Color(0xFF87969D), fontSize: 12, letterSpacing: 0),
                                prefixIcon: Icon(Icons.key_rounded, color: teal, size: 20),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: muted, size: 19),
                                ),
                                filled: true,
                                fillColor: inputBackground,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: isDark ? const Color(0xFF2D3B45) : const Color(0xFFDCE7E8))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFDCE7E8))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: teal, width: 1.6)),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 11),
                              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD9485F), fontSize: 11, fontWeight: FontWeight.w700, height: 1.6)),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: _busy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: teal,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: const Color(0xFF83BDB9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  elevation: 2,
                                ),
                                child: _busy
                                    ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('ورود به برنامه', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'اللهم صل علی محمد و آل محمد الائمه و المهدیین و سلم تسلیما',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF167D86), fontSize: 12, fontWeight: FontWeight.w800, height: 2),
                      ),
                      const SizedBox(height: 8),
                      Text('دسترسی خصوصی  •  VPN13', style: TextStyle(color: muted, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
