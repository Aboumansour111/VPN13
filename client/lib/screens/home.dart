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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _ink = Color(0xFFF0F3F4);
  static const _muted = Color(0xFFB5C0C6);
  static const _blue = Color(0xFF8FA9B5);
  static const _green = Color(0xFF39A98B);

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
  int _activeTab = 0;
  String _serverQuery = '';
  String dnsAddress = '1.1.1.1';
  final Set<String> excludedApps = {};
  List<Map<String, String>> installedApps = [];
  bool appsLoading = false;

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
    WidgetsBinding.instance.addObserver(this);
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
    _loadConnectionSettings();
  }

  Future<void> _loadConnectionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      dnsAddress = prefs.getString('dnsAddress') ?? '1.1.1.1';
      excludedApps.addAll(prefs.getStringList('excludedApps') ?? const []);
    });
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && connected && connectedAt != null) {
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted && connectedAt != null) setState(() => elapsed = DateTime.now().difference(connectedAt!));
      });
      setState(() => elapsed = DateTime.now().difference(connectedAt!));
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      timer?.cancel();
      timer = null;
    }
  }

  void _handleStatus(_VpnStatus value) {
    if (value == _VpnStatus.connected && status != _VpnStatus.connected) {
      connectedAt = DateTime.now();
      elapsed = Duration.zero;
      connectionError = null;
      timer?.cancel();
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        timer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (mounted && connectedAt != null) setState(() => elapsed = DateTime.now().difference(connectedAt!));
        });
      }
    } else if (value != _VpnStatus.connected) {
      timer?.cancel();
      connectedAt = null;
      elapsed = Duration.zero;
    }
    if (mounted) setState(() => status = value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      final xrayConfig = EngineRouter.toXrayConfiguration(server.config, remoteDns: dnsAddress);
      await NativeXray.requestNotificationPermission();
      if (!await NativeXray.requestPermission()) {
        throw Exception('مجوز VPN صادر نشد.');
      }
      await NativeXray.connect(config: xrayConfig, profileName: server.name, dnsAddress: dnsAddress, excludedApps: excludedApps.toList());
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF252F38),
    body: SafeArea(
      child: loading ? const Center(child: CircularProgressIndicator()) :
        IndexedStack(index: _activeTab, children: [_homePage(), _settingsPage()]),
    ),
    bottomNavigationBar: NavigationBar(
      height: 70, backgroundColor: const Color(0xFF202930), indicatorColor: const Color(0xFF405B58),
      selectedIndex: _activeTab,
      onDestinationSelected: (index) => setState(() => _activeTab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'خانه'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'تنظیمات'),
      ],
    ),
  );

  Widget _homePage() => RefreshIndicator(
    onRefresh: loadServers,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        _topBar(), const SizedBox(height: 18), _connectionPanel(),
        const SizedBox(height: 16), _homeServersSection(),
        const SizedBox(height: 12), _trafficPanel(),
        const SizedBox(height: 12), _durationSummary(),
        if (connectionError != null) ...[const SizedBox(height: 12), _errorPanel(connectionError!)],
        if (error != null) ...[const SizedBox(height: 12), _errorPanel(error!)],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: loadServers, icon: const Icon(Icons.sync_rounded, size: 19),
          label: const Text('به‌روزرسانی فهرست سرورها'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF72CDB0), side: const BorderSide(color: Color(0xFF53636B)),
            backgroundColor: const Color(0xFF35434C), minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 10),
        const Center(child: Text('VPN13  •  اتصال امن و ساده', style: TextStyle(color: Color(0xFF8A96A8), fontSize: 11))),
      ],
    ),
  );

  Widget _durationSummary() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(color: const Color(0xFF35434C), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF46555E))),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.schedule_rounded, color: Color(0xFFC5D0D5), size: 21), const SizedBox(width: 10),
      Column(children: [
        const Text('مدت زمان اتصال', style: TextStyle(color: Color(0xFF758297), fontSize: 11)),
        Text(durationText(elapsed), style: const TextStyle(color: Color(0xFFF0F3F4), fontSize: 17, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    ]),
  );

  Widget _homeServersSection() => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFF35434C),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF46555E)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('انتخاب سرور', style: TextStyle(color: Color(0xFFF0F3F4), fontSize: 15, fontWeight: FontWeight.w900))),
        IconButton(onPressed: loadServers, icon: const Icon(Icons.refresh_rounded, size: 20), tooltip: 'به‌روزرسانی'),
      ]),
      TextField(
        onChanged: (value) => setState(() => _serverQuery = value),
        decoration: InputDecoration(
          hintText: 'جستجو در سرورها...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: const Color(0xFF293740),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      if (servers.isEmpty)
        Text(loading ? 'در حال دریافت سرورها...' : 'سروری موجود نیست', style: const TextStyle(color: Color(0xFFB5C0C6)))
      else
        ...servers.where((server) => server.name.toLowerCase().contains(_serverQuery.trim().toLowerCase())).map((server) {
          final active = server.id == selectedId;
          final canSelect = status == _VpnStatus.disconnected && !busy;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: active ? const Color(0xFF405B58) : const Color(0xFF2D3942),
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                onTap: !canSelect ? null : () => selectServer(server),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: active ? const Color(0xFF39A98B) : const Color(0xFF46555E), width: active ? 1.4 : 1),
                  ),
                  child: Row(children: [
                    Icon(active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: active ? const Color(0xFF75D6B5) : const Color(0xFF9BAAB1), size: 21),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(server.name, style: const TextStyle(color: Color(0xFFF0F3F4), fontSize: 14, fontWeight: FontWeight.w800)),
                      if (server.description != null)
                        Text(server.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF79CDB2), fontSize: 10)),
                    ])),
                    const Icon(Icons.dns_rounded, color: Color(0xFF39A98B), size: 23),
                  ]),
                ),
              ),
            ),
          );
        }),
      if (connected)
        const Padding(padding: EdgeInsets.only(top: 4), child: Text('برای تغییر سرور، ابتدا اتصال را قطع کنید.', style: TextStyle(color: Color(0xFF77849A), fontSize: 10))),
    ]),
  );

  Future<void> loadInstalledApps() async {
    setState(() => appsLoading = true);
    try {
      final apps = await NativeXray.installedApps();
      if (mounted) setState(() => installedApps = apps);
    } catch (e) {
      if (mounted) message('دریافت برنامه‌ها ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => appsLoading = false);
    }
  }

  Future<void> _chooseExcludedApps() async {
    if (installedApps.isEmpty && !appsLoading) await loadInstalledApps();
    if (!mounted) return;
    final draft = Set<String>.from(excludedApps);
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('برنامه‌های خارج از تونل'),
        content: SizedBox(width: double.maxFinite, height: 440, child: appsLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: installedApps.map((app) {
              final pkg = app['package']!;
              return CheckboxListTile(
                dense: true, value: draft.contains(pkg),
                title: Text(app['label'] ?? pkg, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(pkg, maxLines: 1, overflow: TextOverflow.ellipsis),
                onChanged: (v) => setDialogState(() { if (v == true) draft.add(pkg); else draft.remove(pkg); }),
              );
            }).toList())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
          FilledButton(onPressed: () async {
            setState(() { excludedApps..clear()..addAll(draft); });
            final p = await SharedPreferences.getInstance();
            await p.setStringList('excludedApps', excludedApps.toList());
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('ذخیره')),
        ],
      ),
    ));
  }

  Widget _settingsPage() => ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 24), children: [
    _topBar(), const SizedBox(height: 20),
    const Text('تنظیمات اتصال', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFF0F3F4), fontSize: 21, fontWeight: FontWeight.w900)),
    const SizedBox(height: 18),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF35434C), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF46555E))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Remote DNS (Xray)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFF0F3F4))),
      const SizedBox(height: 8), const Text('درخواست‌های DNS پورت 53 از داخل تونل Xray و با TCP به این سرور ارسال می‌شوند. برای اعمال، اتصال را دوباره برقرار کنید.', style: TextStyle(fontSize: 11, color: Color(0xFFB5C0C6))),
      const SizedBox(height: 12), DropdownButtonFormField<String>(key: ValueKey(dnsAddress), initialValue: dnsAddress, decoration: const InputDecoration(labelText: 'سرور DNS', border: OutlineInputBorder()), items: const [
        DropdownMenuItem(value: '1.1.1.1', child: Text('Cloudflare — 1.1.1.1')),
        DropdownMenuItem(value: '1.0.0.1', child: Text('Cloudflare — 1.0.0.1')),
        DropdownMenuItem(value: '8.8.8.8', child: Text('Google — 8.8.8.8')),
        DropdownMenuItem(value: '8.8.4.4', child: Text('Google — 8.8.4.4')),
        DropdownMenuItem(value: '9.9.9.9', child: Text('Quad9 — 9.9.9.9')),
      ], onChanged: (v) async {
        if (v == null) return;
        setState(() => dnsAddress = v);
        final p = await SharedPreferences.getInstance();
        await p.setString('dnsAddress', v);
      }),
    ])),
    const SizedBox(height: 12),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF35434C), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF46555E))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('برنامه‌های خارج از VPN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFF0F3F4))),
      const SizedBox(height: 8), const Text('ترافیک این برنامه‌ها از تونل VPN عبور نمی‌کند.', style: TextStyle(fontSize: 11, color: Color(0xFFB5C0C6))),
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: _chooseExcludedApps, icon: const Icon(Icons.apps_rounded), label: Text('انتخاب برنامه‌ها (${excludedApps.length})'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
      if (excludedApps.isNotEmpty) ...[const SizedBox(height: 8), Text(excludedApps.map((p) => installedApps.firstWhere((a) => a['package'] == p, orElse: () => {'label': p})['label']).join('، '), style: const TextStyle(fontSize: 12, color: Color(0xFFC5D0D5)))],
    ])),
    const SizedBox(height: 14),
    const Text('برای اعمال DNS و فهرست استثناها، اتصال فعلی را قطع و دوباره وصل کنید.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB5C0C6), fontSize: 11)),
  ]);



  Widget _topBar() => Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 11, top: 5),
            child: Text(
              'اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF39A98B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.15,
              ),
            ),
          ),
          Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.asset('assets/icon/vpn13_icon.jpg', width: 48, height: 48, fit: BoxFit.cover),
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
              color: const Color(0xFF35434C),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFF46555E)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: connected
                      ? _green
                      : status == _VpnStatus.connecting || status == _VpnStatus.disconnecting
                          ? const Color(0xFFFFC66D)
                          : const Color(0xFF536A84),
                ),
                const SizedBox(width: 7),
                Text(
                  connected
                      ? 'آنلاین'
                      : status == _VpnStatus.disconnecting
                          ? 'در حال قطع'
                          : status == _VpnStatus.connecting
                              ? 'در حال اتصال'
                              : 'آفلاین',
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
        : status == _VpnStatus.connecting
            ? 'در حال اتصال…'
            : status == _VpnStatus.disconnecting
                ? 'در حال قطع اتصال…'
                : 'آماده اتصال';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 19, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF35434C),
        borderRadius: BorderRadius.circular(27),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10171C).withValues(alpha: 0.22),
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
                  color: Color(0xFF39A98B), size: 17),
              const SizedBox(width: 7),
              const Text(
                'وضعیت تونل',
                style: TextStyle(
                  color: Color(0xFFB5C0C6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (active)
                Text(
                  durationText(elapsed),
                  style: const TextStyle(
                    color: Color(0xFFF0F3F4),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 17),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF293D3C),
              border: Border.all(
                color: (active ? const Color(0xFF39A98B) : const Color(0xFF657780))
                    .withValues(alpha: 0.75),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? const Color(0xFF39A98B) : const Color(0xFF405B58),
                ),
                child: Icon(
                  active ? Icons.shield_rounded : Icons.power_settings_new,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Text(
            statusLabel,
            style: const TextStyle(
              color: Color(0xFFF0F3F4),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            selected == null
                ? 'ابتدا یک سرور انتخاب کنید'
                : active
                    ? 'تونل Xray فعال است؛ وضعیت ترافیک در پایین نمایش داده می‌شود'
                    : 'برای شروع، دکمه اتصال را بزنید',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF7D899B),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: busy ||
                      status == _VpnStatus.connecting ||
                      status == _VpnStatus.disconnecting ||
                      selected == null
                  ? null
                  : (active ? disconnect : connect),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF39A98B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF496D63),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: busy ||
                      status == _VpnStatus.connecting ||
                      status == _VpnStatus.disconnecting
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

  Widget _trafficPanel() => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFF35434C),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF46555E)),
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
                    speed: speedText(downloadSpeed),
                    total: bytesText(downloadTotal),
                    color: _green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _trafficValue(
                    icon: Icons.north_rounded,
                    title: 'ارسال',
                    speed: speedText(uploadSpeed),
                    total: bytesText(uploadTotal),
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
          color: const Color(0xFF2B3740),
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
          color: const Color(0xFF49383A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF805456)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFFFA39A), size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                details,
                style: const TextStyle(
                  color: Color(0xFFFFD5D0),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}
