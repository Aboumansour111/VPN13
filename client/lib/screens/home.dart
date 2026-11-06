import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sing_box/sing_box.dart';

import '../config.dart';

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
  static const _ink = Color(0xFF10213D);
  static const _muted = Color(0xFF71809A);
  static const _blue = Color(0xFF3867F4);
  static const _green = Color(0xFF19A879);

  List<ServerItem> servers = [];
  int? selectedId;
  bool loading = true;
  bool manualMode = false;
  bool busy = false;
  String? error;
  String? connectionError;

  StreamSubscription<SingBoxConnectionStatus>? statusSub;
  StreamSubscription<SingBoxConnectionStats>? statsSub;
  StreamSubscription<SingBoxConnectionState>? stateSub;
  Timer? timer;
  DateTime? connectedAt;
  Duration elapsed = Duration.zero;
  SingBoxConnectionStatus status = SingBox.instance.status;
  SingBoxConnectionStats? stats;

  bool get connected => status == SingBoxConnectionStatus.connected;

  ServerItem? get selected {
    for (final server in servers) {
      if (server.id == selectedId) return server;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    statusSub = SingBox.instance.watchConnectionStatus().listen((value) {
      if (value == SingBoxConnectionStatus.connected &&
          status != SingBoxConnectionStatus.connected) {
        connectedAt = DateTime.now();
        elapsed = Duration.zero;
        connectionError = null;
        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && connectedAt != null) {
            setState(() => elapsed = DateTime.now().difference(connectedAt!));
          }
        });
      } else if (value != SingBoxConnectionStatus.connected) {
        timer?.cancel();
        connectedAt = null;
        elapsed = Duration.zero;
      }
      if (mounted) setState(() => status = value);
    });
    statsSub = SingBox.instance.watchConnectionStats().listen((value) {
      if (mounted) setState(() => stats = value);
    });
    stateSub = SingBox.instance.watchConnectionState().listen((value) {
      if (value.error != null && value.error!.isNotEmpty && mounted) {
        setState(() => connectionError = value.error);
      }
    });
    loadServers();
  }

  @override
  void dispose() {
    statusSub?.cancel();
    statsSub?.cancel();
    stateSub?.cancel();
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadServers({bool manual = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      late final String responseBody;
      if (manual) {
        responseBody = await rootBundle.loadString('assets/servers.json');
      } else {
        final response = await http
            .get(
              Uri.parse(AppConfig.serversJsonUrl),
              headers: const {'Cache-Control': 'no-cache'},
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        responseBody = response.body;
      }
      final document = jsonDecode(responseBody) as Map<String, dynamic>;
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
        manualMode = manual;
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
      if (SingBox.instance.status.isActive) {
        await SingBox.instance.disconnect();
      }
      await SingBox.instance.requestNotificationPermission();
      await SingBox.instance.connect(server.config);
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
      await SingBox.instance.disconnect();
    } catch (e) {
      if (mounted) setState(() => connectionError = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> selectServer(ServerItem server) async {
    if (connected || busy || server.id == selectedId) return;
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
      backgroundColor: const Color(0xFFF4F7FC),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: loadServers,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                  children: [
                    _topBar(),
                    const SizedBox(height: 18),
                    _connectionPanel(),
                    const SizedBox(height: 16),
                    _serverListCard(),
                    if (connected) ...[
                      const SizedBox(height: 16),
                      _trafficPanel(),
                    ],
                    if (connectionError != null) ...[
                      const SizedBox(height: 14),
                      _errorPanel(connectionError!),
                    ],
                    if (manualMode) ...[
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'حالت دستی: فهرست سرورها از فایل داخلی برنامه بارگذاری شده است.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, fontSize: 10),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      _errorPanel(error!),
                      const SizedBox(height: 8),
                      Center(
                        child: OutlinedButton.icon(
                          onPressed: loading || busy
                              ? null
                              : () => loadServers(manual: true),
                          icon: const Icon(Icons.phone_android_rounded, size: 18),
                          label: const Text('آزمایش حالت دستی (بدون GitHub)'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Center(
                      child: TextButton.icon(
                        onPressed: loadServers,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('به‌روزرسانی فهرست سرورها'),
                        style: TextButton.styleFrom(
                          foregroundColor: _muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'VPN13  •  اتصال امن و ساده',
                        style: TextStyle(
                          color: Color(0xFF9AA6B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _topBar() => Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 13, top: 3),
            child: Text(
              'اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF168B68),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4778FF), Color(0xFF2549C8)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: _blue.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VPN13',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'اتصال پایدار، بدون پیچیدگی',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFE7ECF4)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: connected ? _green : const Color(0xFFB3BDCC),
                ),
                const SizedBox(width: 7),
                Text(
                  connected ? 'آنلاین' : 'آفلاین',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
          ),
        ],
      );

  Widget _connectionPanel() {
    final active = connected;
    final statusLabel = active
        ? 'اتصال برقرار است'
        : status == SingBoxConnectionStatus.connecting
            ? 'در حال اتصال…'
            : 'آماده اتصال';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF142D59), Color(0xFF203F78), Color(0xFF28529A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(27),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF18396F).withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_rounded,
                  color: Color(0xFFB8CCF8), size: 17),
              const SizedBox(width: 7),
              const Text(
                'وضعیت تونل',
                style: TextStyle(
                  color: Color(0xFFD7E2F8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (active)
                Text(
                  durationText(elapsed),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.07),
              border: Border.all(
                color: (active ? const Color(0xFF63D9B1) : Colors.white)
                    .withValues(alpha: 0.55),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? const Color(0xFF1B9C79)
                      : Colors.white.withValues(alpha: 0.12),
                ),
                child: Icon(
                  active ? Icons.shield_rounded : Icons.power_settings_new,
                  color: Colors.white,
                  size: 39,
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            statusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            selected == null
                ? 'ابتدا یک سرور انتخاب کنید'
                : active
                    ? 'ترافیک دستگاه از تونل VPN عبور می‌کند'
                    : 'برای شروع، دکمه اتصال را بزنید',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFC4D2EA),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: busy ||
                      status == SingBoxConnectionStatus.connecting ||
                      selected == null
                  ? null
                  : (active ? disconnect : connect),
              style: FilledButton.styleFrom(
                backgroundColor: active
                    ? const Color(0xFFEBF2FF)
                    : const Color(0xFF5B83FF),
                foregroundColor:
                    active ? const Color(0xFF18386F) : Colors.white,
                disabledBackgroundColor: Colors.white24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: busy ||
                      status == SingBoxConnectionStatus.connecting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(active
                            ? Icons.stop_rounded
                            : Icons.power_settings_new_rounded),
                        const SizedBox(width: 8),
                        Text(
                          active ? 'قطع اتصال' : 'اتصال به VPN',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serverListCard() => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8EDF5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_rounded, color: _blue, size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'انتخاب سرور',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${servers.length} سرور',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (servers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    'هنوز سروری اضافه نشده است',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              )
            else
              ...servers.map((server) {
                final active = server.id == selectedId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: active
                        ? const Color(0xFFF0F5FF)
                        : const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: connected || busy
                          ? null
                          : () => selectServer(server),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: active
                                ? _blue.withValues(alpha: 0.55)
                                : const Color(0xFFE9EEF5),
                            width: active ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: active
                                    ? const Color(0xFFE0E9FF)
                                    : const Color(0xFFEDF1F7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.dns_rounded,
                                color: active ? _blue : _muted,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    server.name,
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    server.description ?? 'سرور VPN13',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              active
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: active ? _blue : const Color(0xFFB7C1D0),
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            if (connected)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'برای تغییر سرور، ابتدا اتصال را قطع کنید.',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ),
          ],
        ),
      );

  Widget _trafficPanel() => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8EDF5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.swap_vert_rounded, color: _blue, size: 19),
                SizedBox(width: 7),
                Text(
                  'مصرف ترافیک',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Spacer(),
                Text(
                  'لحظه‌ای',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _trafficValue(
                    icon: Icons.south_rounded,
                    title: 'دریافت',
                    speed: speedText(stats?.downloadSpeed ?? 0),
                    total: bytesText(stats?.downloadTotal ?? 0),
                    color: _green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _trafficValue(
                    icon: Icons.north_rounded,
                    title: 'ارسال',
                    speed: speedText(stats?.uploadSpeed ?? 0),
                    total: bytesText(stats?.uploadTotal ?? 0),
                    color: _blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _trafficValue({
    required IconData icon,
    required String title,
    required String speed,
    required String total,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FD),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 17),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              speed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'کل: $total',
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
      );

  Widget _errorPanel(String details) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF4D7D0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFC45A43), size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                details,
                style: const TextStyle(
                  color: Color(0xFF8D4435),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}
