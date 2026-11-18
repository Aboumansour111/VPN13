import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dnsPresets = <String, Map<String, String>>{
  'cloudflare': {'primary': '1.1.1.1', 'secondary': '1.0.0.1'},
  'google': {'primary': '8.8.8.8', 'secondary': '8.8.4.4'},
  'quad9': {'primary': '9.9.9.9', 'secondary': '149.112.112.112'},
};

Future<void> showDnsSettings(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DnsSettingsSheet(prefs: prefs),
  );
}

/// Applies the user's DNS selection to a decoded sing-box configuration.
/// The original server's outbound, routing and inbounds are preserved.
String applyDnsSettings(String rawConfig, SharedPreferences prefs) {
  final mode = prefs.getString('vpn13_dns_mode') ?? 'cloudflare';
  final secure = prefs.getBool('vpn13_dns_secure') ?? false;
  final customPrimary = prefs.getString('vpn13_dns_primary') ?? '';
  final customSecondary = prefs.getString('vpn13_dns_secondary') ?? '';

  final addresses = mode == 'custom'
      ? [customPrimary, customSecondary].where((v) => v.trim().isNotEmpty).toList()
      : [_dnsPresets[mode]?['primary'], _dnsPresets[mode]?['secondary']]
          .whereType<String>()
          .toList();
  if (addresses.isEmpty) return rawConfig;

  final config = jsonDecode(rawConfig) as Map<String, dynamic>;
  final servers = <Map<String, dynamic>>[];
  for (var i = 0; i < addresses.length; i++) {
    final address = addresses[i].trim();
    final useHttps = secure;
    servers.add({
      'tag': i == 0 ? 'vpn13-dns-primary' : 'vpn13-dns-secondary',
      'address': useHttps
          ? 'https://dns.google/dns-query'
          : 'udp://$address',
    });
  }
  config['dns'] = {
    'servers': servers,
    'final': 'vpn13-dns-primary',
    'strategy': 'prefer_ipv4',
  };
  return jsonEncode(config);
}

class _DnsSettingsSheet extends StatefulWidget {
  const _DnsSettingsSheet({required this.prefs});

  final SharedPreferences prefs;

  @override
  State<_DnsSettingsSheet> createState() => _DnsSettingsSheetState();
}

class _DnsSettingsSheetState extends State<_DnsSettingsSheet> {
  static const _ink = Color(0xFF10213D);
  static const _teal = Color(0xFF0E7C86);

  late String _mode;
  late bool _secure;
  late final TextEditingController _primary;
  late final TextEditingController _secondary;

  @override
  void initState() {
    super.initState();
    _mode = widget.prefs.getString('vpn13_dns_mode') ?? 'cloudflare';
    _secure = widget.prefs.getBool('vpn13_dns_secure') ?? false;
    _primary = TextEditingController(
      text: widget.prefs.getString('vpn13_dns_primary') ?? '1.1.1.1',
    );
    _secondary = TextEditingController(
      text: widget.prefs.getString('vpn13_dns_secondary') ?? '1.0.0.1',
    );
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_mode == 'custom' &&
        (_primary.text.trim().isEmpty ||
            !_isIpAddress(_primary.text.trim()) ||
            (_secondary.text.trim().isNotEmpty &&
                !_isIpAddress(_secondary.text.trim())))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('آدرس DNS سفارشی معتبر نیست.')),
      );
      return;
    }
    await widget.prefs.setString('vpn13_dns_mode', _mode);
    await widget.prefs.setBool('vpn13_dns_secure', _secure);
    await widget.prefs.setString('vpn13_dns_primary', _primary.text.trim());
    await widget.prefs.setString('vpn13_dns_secondary', _secondary.text.trim());
    if (mounted) Navigator.pop(context);
  }

  bool _isIpAddress(String value) {
    final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    final ipv6 = RegExp(r'^[0-9a-fA-F:]+$');
    if (!ipv4.hasMatch(value) && !ipv6.hasMatch(value)) return false;
    if (ipv4.hasMatch(value)) {
      return value.split('.').every((part) {
        final n = int.tryParse(part);
        return n != null && n >= 0 && n <= 255;
      });
    }
    return value.contains(':');
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF4F7FC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5DCE7),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Icon(Icons.dns_rounded, color: _teal, size: 23),
                    SizedBox(width: 9),
                    Text('تنظیمات DNS',
                        style: TextStyle(
                            color: _ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  'DNS انتخاب‌شده هنگام اتصال بعدی روی کانفیگ سرور اعمال می‌شود.',
                  style: TextStyle(color: Color(0xFF71809A), fontSize: 11),
                ),
                const SizedBox(height: 18),
                _preset('cloudflare', 'Cloudflare', '1.1.1.1  •  1.0.0.1'),
                _preset('google', 'Google', '8.8.8.8  •  8.8.4.4'),
                _preset('quad9', 'Quad9', '9.9.9.9  •  149.112.112.112'),
                _preset('custom', 'سفارشی', 'آدرس DNS دلخواه'),
                if (_mode == 'custom') ...[
                  const SizedBox(height: 12),
                  _field(_primary, 'DNS اصلی'),
                  const SizedBox(height: 9),
                  _field(_secondary, 'DNS جایگزین (اختیاری)'),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _secure,
                  onChanged: (value) => setState(() => _secure = value),
                  activeColor: _teal,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('DNS رمزگذاری‌شده (DoH)',
                      style: TextStyle(
                          color: _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  subtitle: const Text('ارسال درخواست DNS از طریق HTTPS',
                      style: TextStyle(
                          color: Color(0xFF71809A), fontSize: 10)),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text('ذخیره تنظیمات',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'برای جلوگیری از قطع ارتباط، تغییر DNS در اتصال فعال اعمال نمی‌شود؛ پس از ذخیره، VPN را یک‌بار قطع و دوباره وصل کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF8793A6), fontSize: 10, height: 1.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _preset(String value, String title, String subtitle) {
    final selected = _mode == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => setState(() => _mode = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? _teal : const Color(0xFFE6EBF2),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? _teal : const Color(0xFFB5BFCD),
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: _ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0xFF8793A6), fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.url,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE6EBF2))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE6EBF2))),
        ),
      );
}
