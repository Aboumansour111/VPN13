import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _checking = true;
  bool _authorized = false;

  @override
  void initState() {
    super.initState();
    _restoreAccess();
  }

  Future<void> _restoreAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('vpn13_access_granted') ?? false;
    if (!mounted) return;
    setState(() {
      _authorized = saved;
      _checking = false;
    });
  }

  Future<void> _grantAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vpn13_access_granted', true);
    if (!mounted) return;
    setState(() => _authorized = true);
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
        : _LoginScreen(onSuccess: _grantAccess);
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.onSuccess});

  final Future<void> Function() onSuccess;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_controller.text.trim() != AppConfig.accessCode) {
      setState(() => _error = 'کد ورود صحیح نیست.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSuccess();
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
                      color: Color(0xFF10213D),
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
                            color: Color(0xFF10213D),
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
                                color: const Color(0xFF71809A),
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
