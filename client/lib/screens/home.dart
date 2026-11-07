import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/engine_router.dart';
import '../services/native_xray.dart';

enum _VpnStatus { disconnected, connecting, connected, disconnecting }

class ServerItem {
  const ServerItem({
    required this.id,
    required this.name,
    required this.config,
    this.description,
  });

  final int id;
  final String name;
  final String config;
  final String? description;

  factory ServerItem.fromJson(Map<String, dynamic> json) => ServerItem(
        id: json['id'] as int,
        name: json['name'] as String,
        config: json['config'] as String,
        description: json['description'] as String?,
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _ink = Color(0xFF17243B);
  static const _muted = Color(0xFF74829A);
  static const _blue = Color(0xFF4169E8);
  static const _green = Color(0xFF16A783);

  List<ServerItem> servers = [];
  int? selectedId;
  bool loading = true;
  bool busy = false;
  String? error;
  String? connectionError;

  StreamSubscription<Map<String, dynamic>>? statusSub;
  num uploadSpeed = 0;
  num downloadSpeed = 0;
  num uploadTotal = 0;
  num downloadTotal = 0;
  Timer? timer;
  DateTime? connectedAt;
  Duration elapsed = Duration.zero;
  _VpnStatus status = _VpnStatus.disconnected;

  bool get connected => status == _VpnStatus.connected;

  ServerItem? get selected {
    for (final server in servers) {
      if (server.id == selectedId) return server;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    statusSub = NativeXray.events.listen(
      _handleNativeEvent,
      onError: (Object e) {
        if (mounted) setState(() => connectionError = e.toString());
      },
    );
    NativeXray.status().then(_handleNativeEvent).catchError((Object e) {
      if (mounted) setState(() => connectionError = e.toString());
    });
    loadServers();
  }

  num _number(Object? value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;

  void _handleNativeEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final stateName = event['state']?.toString() ?? 'disconnected';
    final message = event['message']?.toString();
    if (stateName == 'error') {
      setState(() => connectionError = message?.isNotEmpty == true
          ? message
          : 'خطا در هسته Xray');
      _handleStatus(_VpnStatus.disconnected);
      return;
    }
    final nextStatus = switch (stateName) {
      'connected' => _VpnStatus.connected,
      'connecting' => _VpnStatus.connecting,
      'disconnecting' => _VpnStatus.disconnecting,
      'disconnected' => _VpnStatus.disconnected,
      _ => status,
    };
    _handleStatus(nextStatus);
    if (mounted) {
      setState(() {
        uploadSpeed = _number(event['uploadSpeed']);
        downloadSpeed = _number(event['downloadSpeed']);
        uploadTotal = _number(event['uploadTotal']);
        downloadTotal = _number(event['downloadTotal']);
        if (stateName == 'connected') connectionError = null;
      });
    }
  }

  void _handleStatus(_VpnStatus value) {
    if (value == _VpnStatus.connected && status != _VpnStatus.connected) {
      connectedAt = DateTime.now();
      elapsed = Duration.zero;
      connectionError = null;
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && connectedAt != null) {
          setState(() => elapsed = DateTime.now().difference(connectedAt!));
        }
      });
    } else if (value != _VpnStatus.connected) {
      timer?.cancel();
      connectedAt = null;
      elapsed = Duration.zero;
    }
    if (mounted) setState(() => status = value);
  }

  @override
  void dispose() {
    statusSub?.cancel();
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadServers() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse(AppConfig.serversJsonUrl),
            headers: const {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final document = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (document['servers'] as List)
          .map((item) => ServerItem.fromJson(item as Map<String, dynamic>))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getInt('selectedServer');
      if (id == null || !list.any((server) => server.id == id)) {
        id = list.isEmpty ? null : list.first.id;
        if (id == null) {
          await prefs.remove('selectedServer');
        } else {
          await prefs.setInt('selectedServer', id);
        }
      }
      if (!mounted) return;
      setState(() {
        servers = list;
        selectedId = id;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error =
            'دریافت فهرست سرورها ناموفق بود. اتصال اینترنت را بررسی کنید.\n$e');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> connect() async {
    final server = selected;
    if (server == null || busy) return;
    setState(() {
      busy = true;
      connectionError = null;
    });
    try {
      final xrayConfig = EngineRouter.toXrayConfiguration(server.config);
      if (!await NativeXray.requestPermission()) {
        throw Exception('مجوز VPN صادر نشد.');
      }
      await NativeXray.connect(config: xrayConfig, profileName: server.name);
    } catch (e) {
      if (mounted) {
        setState(() => connectionError = e.toString());
        message('اتصال برقرار نشد؛ جزئیات خطا در پایین صفحه آمده است.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnect() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await NativeXray.disconnect();
    } catch (e) {
      if (mounted) setState(() => connectionError = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> selectServer(ServerItem server) async {
    if (status != _VpnStatus.disconnected || busy || server.id == selectedId) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selectedServer', server.id);
    if (mounted) {
      setState(() {
        selectedId = server.id;
        connectionError = null;
      });
    }
  }

  void message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
      ),
    );
  }

  String durationText(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:'
      '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  String bytesText(num n) {
    if (n < 1024) return '${n.toStringAsFixed(0)} B';
    if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1073741824) return '${(n / 1048576).toStringAsFixed(1)} MB';
    return '${(n / 1073741824).toStringAsFixed(2)} GB';
  }

  String speedText(num n) => '${bytesText(n)}/s';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4EE),
      body: SafeArea(child: loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF285447)))
        : RefreshIndicator(color: const Color(0xFF285447), onRefresh: loadServers,
          child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(21, 10, 21, 34), children: [
            _topBar(), const SizedBox(height: 24), _connectionPanel(), const SizedBox(height: 22), _serverList(),
            const SizedBox(height: 16), _trafficPanel(),
            if (connectionError != null) ...[const SizedBox(height: 14), _errorPanel(connectionError!)],
            if (error != null) ...[const SizedBox(height: 14), _errorPanel(error!)],
            const SizedBox(height: 20),
            Center(child: TextButton.icon(onPressed: loading ? null : loadServers, icon: const Icon(Icons.sync_rounded, size: 17),
              label: const Text('به‌روزرسانی فهرست سرورها'), style: TextButton.styleFrom(foregroundColor: const Color(0xFF66756C), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
            const SizedBox(height: 7),
            const Center(child: Text('VPN13  ·  PRIVATE NETWORK', style: TextStyle(color: Color(0xFFA2A69D), fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w700))),
          ]))),
    );
  }

  Widget _topBar() => Column(children: [
    Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFEDEFE7), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E6DB))),
      child: const Text('اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ', textAlign: TextAlign.center, textDirection: TextDirection.rtl,
        style: TextStyle(color: Color(0xFF315B49), fontSize: 15, fontWeight: FontWeight.w700, height: 1.7))),
    const SizedBox(height: 19),
    Row(children: [
      Container(width: 49, height: 49, decoration: BoxDecoration(color: const Color(0xFF285447), borderRadius: BorderRadius.circular(17),
        boxShadow: [BoxShadow(color: const Color(0xFF285447).withValues(alpha: 0.16), blurRadius: 17, offset: const Offset(0, 7))]),
        child: Stack(alignment: Alignment.center, children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFB8C9B9).withValues(alpha: 0.7)))),
          const Icon(Icons.shield_outlined, color: Color(0xFFF4E8D2), size: 25),
          Positioned(right: 11, bottom: 11, child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFD7A45C), shape: BoxShape.circle))),
        ])),
      const SizedBox(width: 13),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('VPN13', style: TextStyle(color: Color(0xFF20352E), fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        SizedBox(height: 3), Text('اتصال پایدار، بدون پیچیدگی', style: TextStyle(color: Color(0xFF7A847B), fontSize: 11)),
      ])),
      _statusBadge(),
    ]),
  ]);

  Widget _statusBadge() {
    final waiting = status == _VpnStatus.connecting || status == _VpnStatus.disconnecting;
    final color = connected ? const Color(0xFF2F8A68) : waiting ? const Color(0xFFC18A43) : const Color(0xFF8B938A);
    final label = connected ? 'متصل' : status == _VpnStatus.connecting ? 'در حال اتصال' : status == _VpnStatus.disconnecting ? 'در حال قطع' : 'قطع';
    return Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(30), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7), Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      ]));
  }

  Widget _connectionPanel() {
    final waiting = busy || status == _VpnStatus.connecting || status == _VpnStatus.disconnecting;
    final label = connected ? 'اتصال شما برقرار است' : status == _VpnStatus.connecting ? 'در حال برقراری ارتباط' : status == _VpnStatus.disconnecting ? 'در حال بستن تونل' : 'آماده برای اتصال';
    final description = selected == null ? 'برای شروع، یک سرور انتخاب کنید' : connected ? 'ترافیک دستگاه از مسیر امن عبور می‌کند' : 'برای فعال‌سازی تونل امن، دکمه را لمس کنید';
    return Container(padding: const EdgeInsets.fromLTRB(21, 20, 21, 19),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: const Color(0xFFE7E6DE)),
        boxShadow: [BoxShadow(color: const Color(0xFF34453A).withValues(alpha: 0.055), blurRadius: 25, offset: const Offset(0, 10))]),
      child: Column(children: [
        Row(children: [
          const Text('وضعیت شبکه', style: TextStyle(color: Color(0xFF7A847B), fontSize: 11, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (connected) ...[const Icon(Icons.schedule_rounded, color: Color(0xFF899188), size: 14), const SizedBox(width: 5),
            Text(durationText(elapsed), style: const TextStyle(color: Color(0xFF53645A), fontSize: 12, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]))]
          else const Text('XRAY CORE', style: TextStyle(color: Color(0xFFB2B6AC), fontSize: 9, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 19),
        Text(label, style: const TextStyle(color: Color(0xFF20352E), fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5), Text(description, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF899188), fontSize: 11, height: 1.6)),
        const SizedBox(height: 22),
        GestureDetector(onTap: waiting || selected == null ? null : (connected ? disconnect : connect),
          child: AnimatedContainer(duration: const Duration(milliseconds: 220), width: 142, height: 142,
            decoration: BoxDecoration(shape: BoxShape.circle, color: connected ? const Color(0xFFE6F0E8) : const Color(0xFFF2F0E7),
              border: Border.all(color: connected ? const Color(0xFFB5D0BC) : const Color(0xFFE4DDCB), width: 1.5)),
            child: Center(child: Container(width: 108, height: 108, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF285447),
              boxShadow: [BoxShadow(color: const Color(0xFF285447).withValues(alpha: 0.22), blurRadius: 20, offset: const Offset(0, 8))]),
              child: Center(child: waiting ? const SizedBox(width: 29, height: 29, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFF4E8D2)))
                : Icon(connected ? Icons.stop_rounded : Icons.power_settings_new_rounded, color: const Color(0xFFF4E8D2), size: 39))))),
        const SizedBox(height: 13),
        Text(waiting ? 'لطفاً صبر کنید…' : connected ? 'برای قطع اتصال لمس کنید' : 'برای اتصال لمس کنید',
          style: const TextStyle(color: Color(0xFF7D887F), fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12), decoration: BoxDecoration(color: const Color(0xFFF7F6F1), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.dns_outlined, color: Color(0xFF8B947F), size: 18), const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('سرور انتخاب‌شده', style: TextStyle(color: Color(0xFF9AA096), fontSize: 9)),
              const SizedBox(height: 3), Text(selected?.name ?? 'سروری انتخاب نشده', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF35483D), fontSize: 12, fontWeight: FontWeight.w800)),
            ])),
            if (connected) const Icon(Icons.verified_rounded, color: Color(0xFF4D946F), size: 18) else const Icon(Icons.chevron_left_rounded, color: Color(0xFF9AA096), size: 20),
          ])),
      ]));
  }

  Widget _serverList() => Container(padding: const EdgeInsets.fromLTRB(17, 17, 17, 12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23), border: Border.all(color: const Color(0xFFE7E6DE))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('موقعیت‌های اتصال', style: TextStyle(color: Color(0xFF20352E), fontSize: 15, fontWeight: FontWeight.w900))),
        Text(servers.length.toString() + ' سرور', style: const TextStyle(color: Color(0xFF9AA096), fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4), const Text('مسیر موردنظر خود را انتخاب کنید', style: TextStyle(color: Color(0xFF9AA096), fontSize: 10)),
      const SizedBox(height: 13),
      if (servers.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('هنوز سروری اضافه نشده است', style: TextStyle(color: Color(0xFF899188), fontSize: 12))))
      else ...servers.map((server) {
        final active = server.id == selectedId;
        final enabled = status == _VpnStatus.disconnected && !busy;
        return Padding(padding: const EdgeInsets.only(bottom: 7),
          child: Material(color: active ? const Color(0xFFF0F3EC) : Colors.white, borderRadius: BorderRadius.circular(15),
            child: InkWell(borderRadius: BorderRadius.circular(15), onTap: !enabled || active ? null : () => selectServer(server),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: active ? const Color(0xFF9EB7A1) : const Color(0xFFEEEDE7), width: active ? 1.3 : 1)),
                child: Row(children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: active ? const Color(0xFFDCE8DB) : const Color(0xFFF4F3EE), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.public_rounded, color: active ? const Color(0xFF285447) : const Color(0xFF899188), size: 19)),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(server.name, style: const TextStyle(color: Color(0xFF35483D), fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3), Text(server.description ?? 'مسیر امن VPN13', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9AA096), fontSize: 10)),
                  ])),
                  const SizedBox(width: 8), Icon(active ? Icons.check_circle_rounded : Icons.circle_outlined, color: active ? const Color(0xFF39745B) : const Color(0xFFD0D3CA), size: 20),
                ])),
            )),
        );
      }),
      if (connected) const Padding(padding: EdgeInsets.only(top: 2, bottom: 3), child: Text('برای تغییر مسیر، ابتدا اتصال را قطع کنید.', style: TextStyle(color: Color(0xFF9AA096), fontSize: 10))),
    ]));

  Widget _trafficPanel() => Container(padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(color: const Color(0xFFECEFE8), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE1E6DC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.swap_vert_rounded, color: Color(0xFF52705D), size: 19), SizedBox(width: 8),
        Text('آمار ترافیک', style: TextStyle(color: Color(0xFF35483D), fontSize: 14, fontWeight: FontWeight.w900)),
        Spacer(), Text('لحظه‌ای', style: TextStyle(color: Color(0xFF899188), fontSize: 10)),
      ]),
      const SizedBox(height: 13),
      Row(children: [
        Expanded(child: _trafficValue(icon: Icons.south_rounded, title: 'دریافت', speed: speedText(downloadSpeed), total: bytesText(downloadTotal), color: const Color(0xFF39745B))),
        const SizedBox(width: 9),
        Expanded(child: _trafficValue(icon: Icons.north_rounded, title: 'ارسال', speed: speedText(uploadSpeed), total: bytesText(uploadTotal), color: const Color(0xFFB47B3F))),
      ]),
      const SizedBox(height: 11),
      Row(children: [
        const Icon(Icons.timer_outlined, color: Color(0xFF899188), size: 15), const SizedBox(width: 6),
        const Text('مدت اتصال', style: TextStyle(color: Color(0xFF899188), fontSize: 10)), const Spacer(),
        Text(durationText(elapsed), style: const TextStyle(color: Color(0xFF53645A), fontSize: 11, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    ]));

  Widget _trafficValue({required IconData icon, required String title, required String speed, required String total, required Color color}) =>
    Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: color, size: 16), const SizedBox(width: 6), Text(title, style: const TextStyle(color: Color(0xFF899188), fontSize: 10, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 9), Text(speed, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF35483D), fontSize: 16, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 4), Text('کل: ' + total, style: const TextStyle(color: Color(0xFF9AA096), fontSize: 10)),
      ]));

  Widget _errorPanel(String details) => Container(padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFFFFF0EC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF0D5CE))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.error_outline_rounded, color: Color(0xFFB75D48), size: 20), const SizedBox(width: 9),
      Expanded(child: SelectableText(details, style: const TextStyle(color: Color(0xFF8E493D), fontSize: 11, height: 1.65))),
    ]));
}
