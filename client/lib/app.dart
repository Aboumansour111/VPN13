import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'screens/home.dart';

class Vpn13ClientApp extends StatelessWidget {
  const Vpn13ClientApp({super.key});
  static const ink = Color(0xFF20352E), forest = Color(0xFF285447), paper = Color(0xFFF6F4EE), muted = Color(0xFF78827B);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: forest, brightness: Brightness.light, surface: paper);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: paper,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, foregroundColor: ink, elevation: 0),
        splashColor: forest.withValues(alpha: 0.06),
      ),
      home: const Directionality(textDirection: TextDirection.rtl, child: _AccessGate()),
    );
  }
}

class _AccessGate extends StatefulWidget {
  const _AccessGate();
  @override
  State<_AccessGate> createState() => _AccessGateState();
}
class _AccessGateState extends State<_AccessGate> {
  bool _checking = true, _authorized = false;
  @override
  void initState() { super.initState(); _restoreAccess(); }
  Future<void> _restoreAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('vpn13_access_granted') ?? false;
    if (!mounted) return;
    setState(() { _authorized = saved; _checking = false; });
  }
  Future<void> _grantAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vpn13_access_granted', true);
    if (!mounted) return;
    setState(() => _authorized = true);
  }
  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Vpn13ClientApp.forest)));
    return _authorized ? const HomeScreen() : _LoginScreen(onSuccess: _grantAccess);
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
  bool _obscure = true, _busy = false;
  String? _error;
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (_busy) return;
    if (_controller.text.trim() != AppConfig.accessCode) { setState(() => _error = 'کد ورود صحیح نیست.'); return; }
    setState(() { _busy = true; _error = null; });
    try { await widget.onSuccess(); } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    const ink = Vpn13ClientApp.ink, forest = Vpn13ClientApp.forest, muted = Vpn13ClientApp.muted;
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 84, height: 84, decoration: BoxDecoration(color: forest, borderRadius: BorderRadius.circular(27),
              boxShadow: [BoxShadow(color: forest.withValues(alpha: 0.17), blurRadius: 28, offset: const Offset(0, 13))]),
              child: Stack(alignment: Alignment.center, children: [
                Container(width: 59, height: 59, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFB7C9B8).withValues(alpha: 0.6)))),
                const Icon(Icons.shield_outlined, color: Color(0xFFF4E8D2), size: 35),
                Positioned(right: 19, bottom: 18, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFD7A45C), shape: BoxShape.circle))),
              ])),
            const SizedBox(height: 25),
            const Text('VPN13', style: TextStyle(color: ink, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            const SizedBox(height: 7),
            const Text('دسترسی اختصاصی به شبکه', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 42),
            Container(padding: const EdgeInsets.all(21), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25),
              border: Border.all(color: const Color(0xFFE8E7DF)), boxShadow: [BoxShadow(color: const Color(0xFF293A31).withValues(alpha: 0.045), blurRadius: 30, offset: const Offset(0, 12))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('کد دسترسی', style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 11),
                TextField(controller: _controller, obscureText: _obscure, autocorrect: false, enableSuggestions: false,
                  textDirection: TextDirection.ltr, textAlign: TextAlign.center, onSubmitted: (_) => _submit(),
                  onChanged: (_) { if (_error != null) setState(() => _error = null); },
                  decoration: InputDecoration(
                    hintText: 'کد اختصاصی خود را وارد کنید', hintStyle: const TextStyle(color: Color(0xFFA7ADA5), fontSize: 12),
                    filled: true, fillColor: const Color(0xFFF8F7F2),
                    prefixIcon: const Icon(Icons.key_rounded, color: muted, size: 19),
                    suffixIcon: IconButton(tooltip: _obscure ? 'نمایش کد' : 'مخفی کردن کد', onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: muted, size: 19)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE7E6DE))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE7E6DE))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: forest, width: 1.5)),
                  )),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xFFFFF1ED), borderRadius: BorderRadius.circular(11)),
                    child: Row(children: [const Icon(Icons.error_outline_rounded, color: Color(0xFFB75D48), size: 17), const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF9E4939), fontSize: 12, fontWeight: FontWeight.w600)))])),
                ],
                const SizedBox(height: 18),
                SizedBox(height: 53, child: FilledButton(onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: forest, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0),
                  child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('ورود به VPN13', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)), SizedBox(width: 8), Icon(Icons.arrow_back_rounded, size: 18)]))),
              ])),
            const SizedBox(height: 24),
            const Text('PRIVATE ACCESS  /  VPN13', style: TextStyle(color: Color(0xFF9AA198), fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700)),
          ],
        )),
      ))),
    );
  }
}
