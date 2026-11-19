import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../flag_asset.dart';
import '../services/engine_router.dart';
import '../services/native_xray.dart';

enum _VpnStatus { disconnected, connecting, connected, disconnecting }

// Reuse one decoded image provider; HomeScreen rebuilds frequently for live stats.
final ImageProvider _vpn13FlagImage = MemoryImage(base64Decode(vpn13FlagBase64));

// Entrance motion is deliberately visible but runs only when a section is
// inserted, not on every parent rebuild (such as live traffic updates).
class _ConnectionPulse extends StatefulWidget {
  const _ConnectionPulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_ConnectionPulse> createState() => _ConnectionPulseState();
}

class _ConnectionPulseState extends State<_ConnectionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ConnectionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) => Transform.scale(
          scale: widget.active ? 1 + (_controller.value * 0.045) : 1,
          child: child,
        ),
      );
}

class _EntranceMotion extends StatefulWidget {
  const _EntranceMotion({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<_EntranceMotion> createState() => _EntranceMotionState();
}

class _EntranceMotionState extends State<_EntranceMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  ));
  late final Animation<double> _scale = Tween<double>(
    begin: 0.94,
    end: 1,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  ));

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(scale: _scale, child: widget.child),
        ),
      );
}

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
  Timer? _serversRefreshTimer;
  DateTime? connectedAt;
  Duration elapsed = Duration.zero;
  _VpnStatus status = _VpnStatus.disconnected;
  int _activeTab = 0;
  String _serverQuery = '';

  String dnsAddress = '1.1.1.1';
  final Set<String> excludedApps = {};
  List<Map<String, String>> installedApps = [];
  bool appsLoading = false;
  final Map<int, int> _pingResults = {};
  final Set<int> _pingTesting = {};
  bool _testingAll = false;
  bool _checkingHandshake = false;
  int? _connectionPingMs;

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
    _serversRefreshTimer = Timer.periodic(_serversRefreshInterval, (_) {
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        loadServers();
      }
    });
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
      setState(() {
        _connectionPingMs = null;
        connectionError = message?.isNotEmpty == true
          ? message
          : 'خطا در هسته Xray';
      });
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
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
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
        timer = Timer.periodic(const Duration(seconds: 1), (_) {
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
    _serversRefreshTimer?.cancel();
    super.dispose();
  }

  static const _serversCacheKey = 'vpn13_servers_cache_json';
  static const _serversFetchedAtKey = 'vpn13_servers_fetched_at';
  static const _serversRefreshInterval = Duration(hours: 4);

  List<ServerItem> _parseServers(String raw) {
    final document = jsonDecode(raw) as Map<String, dynamic>;
    return (document['servers'] as List)
        .map((item) => ServerItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _showServers(List<ServerItem> list, SharedPreferences prefs) async {
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
      loading = false;
    });
  }

  Future<void> loadServers({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRaw = prefs.getString(_serversCacheKey);
    final cachedAtMs = prefs.getInt(_serversFetchedAtKey);
    List<ServerItem>? cached;
    if (cachedRaw != null) {
      try {
        cached = _parseServers(cachedRaw);
      } catch (_) {
        cached = null;
      }
    }

    if (!force && cached != null) {
      await _showServers(cached, prefs);
      final fresh = cachedAtMs != null &&
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(cachedAtMs)) <
              _serversRefreshInterval;
      if (fresh) {
        if (mounted) setState(() => error = null);
        return;
      }
    } else if (mounted) {
      setState(() {
        loading = cached == null;
        error = null;
      });
    }

    try {
      final baseUri = Uri.parse(AppConfig.serversJsonUrl);
      final requestUri = force
          ? baseUri.replace(queryParameters: {
              ...baseUri.queryParameters,
              '_refresh': DateTime.now().microsecondsSinceEpoch.toString(),
            })
          : baseUri;
      final response = await http
          .get(
            requestUri,
            headers: const {
              'Cache-Control': 'no-cache, no-store, max-age=0',
              'Pragma': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ' + response.statusCode.toString());
      }
      final document = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (document['servers'] as List)
          .map((item) => ServerItem.fromJson(item as Map<String, dynamic>))
          .toList();

      await prefs.setString(_serversCacheKey, response.body);
      await prefs.setInt(_serversFetchedAtKey, DateTime.now().millisecondsSinceEpoch);
      await _showServers(list, prefs);
      if (mounted) {
        setState(() => error = null);
        if (force) message('سرورها به‌روز شدند');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = cached != null
              ? 'به‌روزرسانی سرورها انجام نشد؛ فهرست ذخیره‌شده نمایش داده می‌شود.\n$e'
              : 'دریافت فهرست سرورها ناموفق بود. اتصال اینترنت را بررسی کنید.\n$e';
        });
      }
    }
  }

  Future<void> connect() async {
    final server = selected;
    if (server == null || busy) return;
    setState(() {
      busy = true;
      _checkingHandshake = true;
      _connectionPingMs = null;
      connectionError = null;
    });
    try {
      final xrayConfig = EngineRouter.toXrayConfiguration(server.config, remoteDns: dnsAddress);
      await NativeXray.requestNotificationPermission();
      if (!await NativeXray.requestPermission()) {
        throw Exception('مجوز VPN صادر نشد.');
      }

      // Verify a real request through this server before starting the VPN UI state.
      final delay = await NativeXray.measureOutboundDelay(xrayConfig)
          .timeout(const Duration(seconds: 20));
      if (delay < 0) {
        throw Exception('سرور به درخواست آزمایشی پاسخ نداد.');
      }
      if (!mounted) return;
      setState(() {
        _connectionPingMs = delay;
        _checkingHandshake = false;
      });

      await NativeXray.connect(
        config: xrayConfig,
        profileName: server.name,
        dnsAddress: dnsAddress,
        excludedApps: excludedApps.toList(),
      );
    } catch (e) {
      if (mounted) {
        final detail = e is TimeoutException
            ? 'مهلت بررسی سرور تمام شد؛ پاسخ پینگ دریافت نشد.'
            : 'هندشیک یا پینگ سرور ناموفق بود؛ اتصال برقرار نشد.\n$e';
        setState(() {
          _checkingHandshake = false;
          _connectionPingMs = null;
          connectionError = detail;
        });
        message('سرور پاسخ نداد؛ اتصال انجام نشد.');
      }
    } finally {
      if (mounted) setState(() {
        busy = false;
        _checkingHandshake = false;
      });
    }
  }

  Future<void> disconnect() async {
    if (busy) return;
    setState(() {
      busy = true;
      _connectionPingMs = null;
    });
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
    backgroundColor: const Color(0xFFF4F7F8),
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4F7F8), Color(0xFFF4F7F8), Color(0xFFF4F7F8)],
        ),
      ),
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey<int>(_activeTab),
            child: switch (_activeTab) {
              0 => _homePage(),
              1 => _serversPage(),
              2 => _statsPage(),
              _ => _settingsPage(),
            },
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      height: 72,
      backgroundColor: const Color(0xFFFFFFFF),
      indicatorColor: const Color(0xFFDDF1EE),
      selectedIndex: _activeTab,
      onDestinationSelected: (index) => setState(() => _activeTab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'خانه'),
        NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public_rounded), label: 'سرورها'),
        NavigationDestination(icon: Icon(Icons.query_stats_outlined), selectedIcon: Icon(Icons.query_stats_rounded), label: 'آمار'),
        NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'تنظیمات'),
      ],
    ),
  );

  Widget _pageHeader(String eyebrow, String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(eyebrow, style: const TextStyle(color: Color(0xFF167D86), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
      const SizedBox(height: 7),
      Text(title, style: const TextStyle(color: Color(0xFF142A30), fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(color: Color(0xFF71808A), fontSize: 12, height: 1.6)),
    ]),
  );

  Widget _serversPage() => ListView(
    primary: false,
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
    children: [
      _topBar(),
      _pageHeader('نقاط دسترسی', 'سرور موردنظرت را انتخاب کن', 'فهرست زنده از مخزن VPN13؛ پینگ با درخواست واقعی از هسته Xray اندازه‌گیری می‌شود.'),
      Container(
        decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFDCE7E8))),
        child: TextField(
          onChanged: (value) => setState(() => _serverQuery = value.trim().toLowerCase()),
          style: const TextStyle(color: Color(0xFF142A30), fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'جستجوی کشور یا نام سرور…',
            hintStyle: TextStyle(color: Color(0xFF71808A), fontSize: 12),
            prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF167D86)),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('${servers.length} سرور در فهرست', style: const TextStyle(color: Color(0xFF71808A), fontSize: 11, fontWeight: FontWeight.w700))),
        TextButton.icon(
          onPressed: _testingAll || servers.isEmpty ? null : _testAllServers,
          icon: _testingAll ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.speed_rounded, size: 17),
          label: const Text('تست همه'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF167D86)),
        ),
        IconButton(
          tooltip: 'به‌روزرسانی',
          onPressed: loading ? null : () => loadServers(force: true),
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF167D86)),
        ),
      ]),
      if (loading && servers.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
      else if (servers.where((s) => s.name.toLowerCase().contains(_serverQuery) || (s.description ?? '').toLowerCase().contains(_serverQuery)).isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('سروری با این عبارت پیدا نشد.', style: TextStyle(color: Color(0xFF71808A)))))
      else
        ...servers.where((s) => s.name.toLowerCase().contains(_serverQuery) || (s.description ?? '').toLowerCase().contains(_serverQuery)).map((server) {
          final chosen = server.id == selectedId;
          final testing = _pingTesting.contains(server.id);
          final ping = _pingResults[server.id];
          return Container(
            margin: const EdgeInsets.only(bottom: 9),
            decoration: BoxDecoration(
              color: chosen ? const Color(0xFF164B49) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: chosen ? const Color(0xFF43CDB6) : const Color(0xFFDCE7E8)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: status == _VpnStatus.disconnected && !busy ? () => selectServer(server) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                child: Row(children: [
                  Container(width: 39, height: 39, decoration: BoxDecoration(color: const Color(0xFFE6F4F3), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.dns_rounded, color: Color(0xFF167D86))),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(server.name, style: TextStyle(color: chosen ? const Color(0xFF142A30) : const Color(0xFFD1E0E4), fontSize: 12, fontWeight: FontWeight.w800)),
                    if (server.description?.isNotEmpty == true) Text(server.description!, style: const TextStyle(color: Color(0xFF71808A), fontSize: 10)),
                    Text(ping == null ? 'پینگ اندازه‌گیری نشده' : ping < 0 ? 'پاسخی دریافت نشد' : 'پینگ واقعی: $ping ms', style: const TextStyle(color: Color(0xFF167D86), fontSize: 10)),
                  ])),
                  IconButton(
                    tooltip: 'تست پینگ',
                    onPressed: testing || _testingAll ? null : () => _testServer(server),
                    icon: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.speed_rounded, color: Color(0xFF167D86)),
                  ),
                  Icon(chosen ? Icons.check_circle_rounded : Icons.circle_outlined, color: chosen ? const Color(0xFF167D86) : const Color(0xFF607C86), size: 20),
                ]),
              ),
            ),
          );
        }),
      if (error != null) ...[const SizedBox(height: 10), _errorPanel(error!)],
    ],
  );

  Widget _statsPage() => ListView(
    primary: false,
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
    children: [
      _topBar(),
      _pageHeader('مرکز داده‌ها', 'مصرف و عملکرد', 'آمار از رویدادهای واقعی سرویس Xray دریافت می‌شود؛ هنگام قطع اتصال سرعت زنده صفر است.'),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF1C4A4D), Color(0xFF17333D), Color(0xFFFFFFFF)]),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: const Color(0xFF397A79)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('مجموع ترافیک این نشست', style: TextStyle(color: Color(0xFFB5D4D2), fontSize: 11)),
          const SizedBox(height: 7),
          Text(bytesText(uploadTotal + downloadTotal), style: const TextStyle(color: Color(0xFF142A30), fontSize: 29, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(connected ? 'در حال دریافت آمار زنده' : 'برای مشاهده آمار زنده به Xray متصل شوید', style: const TextStyle(color: Color(0xFF8FB8B8), fontSize: 10)),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _statTile('دانلود', speedText(downloadSpeed), bytesText(downloadTotal), Icons.south_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _statTile('آپلود', speedText(uploadSpeed), bytesText(uploadTotal), Icons.north_rounded)),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(19), border: Border.all(color: const Color(0xFFDCE7E8))),
        child: Column(children: [
          _statLine('وضعیت تونل', connected ? 'متصل' : status == _VpnStatus.connecting ? 'در حال اتصال' : 'قطع', connected ? const Color(0xFF62E0BB) : const Color(0xFF71808A)),
          const Divider(color: Color(0xFFDCE7E8), height: 22),
          _statLine('مدت اتصال', durationText(elapsed), const Color(0xFF142A30)),
          const Divider(color: Color(0xFFDCE7E8), height: 22),
          _statLine('سرور انتخاب‌شده', selected?.name ?? 'انتخاب نشده', const Color(0xFF142A30)),
          const Divider(color: Color(0xFFDCE7E8), height: 22),
          _statLine('پینگ آخرین اتصال', _connectionPingMs == null ? '—' : '$_connectionPingMs ms', const Color(0xFF167D86)),
        ]),
      ),
      const SizedBox(height: 12),
      if (connected) OutlinedButton.icon(onPressed: () => NativeXray.status().then(_handleNativeEvent), icon: const Icon(Icons.sync_rounded), label: const Text('به‌روزرسانی وضعیت')),
      if (connectionError != null) ...[const SizedBox(height: 10), _errorPanel(connectionError!)],
    ],
  );

  Widget _statTile(String title, String speed, String total, IconData icon) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDCE7E8))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: const Color(0xFF167D86), size: 21),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: Color(0xFF71808A), fontSize: 11)),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(speed, style: const TextStyle(color: Color(0xFF142A30), fontSize: 19, fontWeight: FontWeight.w900))),
      Text('کل: $total', style: const TextStyle(color: Color(0xFF167D86), fontSize: 10)),
    ]),
  );

  Widget _statLine(String label, String value, Color valueColor) => Row(children: [
    Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF71808A), fontSize: 11))),
    Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.w800))),
  ]);

  Widget _homePage() => RefreshIndicator(
    onRefresh: () => loadServers(force: true),
    child: ListView(
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
      children: [
        _EntranceMotion(child: _topBar()),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE6F4F3), Color(0xFFF1FAFF)]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(children: [
            Icon(Icons.format_quote_rounded, color: Color(0xFF167D86), size: 20),
            SizedBox(width: 9),
            Expanded(child: Text(
              'اللهم صل علی محمد و آل محمد الائمه و المهدیین و سلم تسلیما',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF2C5A63), fontSize: 10, height: 1.9, fontWeight: FontWeight.w700),
            )),
          ]),
        ),
        const SizedBox(height: 14),
        _EntranceMotion(
          delay: const Duration(milliseconds: 70),
          child: _connectionPanel(),
        ),
        const SizedBox(height: 12),
        _EntranceMotion(
          delay: const Duration(milliseconds: 130),
          child: _selectedServerCard(),
        ),
        const SizedBox(height: 12),
        _EntranceMotion(
          delay: const Duration(milliseconds: 190),
          child: _durationSummary(),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _statTile('دانلود', speedText(downloadSpeed), bytesText(downloadTotal), Icons.south_rounded)),
          const SizedBox(width: 10),
          Expanded(child: _statTile('آپلود', speedText(uploadSpeed), bytesText(uploadTotal), Icons.north_rounded)),
        ]),
        if (connectionError != null) ...[
          const SizedBox(height: 12),
          _errorPanel(connectionError!),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          _errorPanel(error!),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => loadServers(force: true),
          icon: const Icon(Icons.sync_rounded, size: 19),
          label: const Text('به‌روزرسانی فهرست سرورها'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF167D86),
            side: const BorderSide(color: Color(0xFFE1E8E7)),
            backgroundColor: const Color(0xFFFFFFFF),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 10),
        const Center(child: Text('VPN13  •  Xray Core', style: TextStyle(color: Color(0xFF71808A), fontSize: 11))),
      ],
    ),
  );

  Widget _selectedServerCard() => Material(
    color: const Color(0xFFFFFFFF),
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      borderRadius: BorderRadius.circular(19),
      onTap: () => setState(() => _activeTab = 1),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(color: const Color(0xFFE6F4F3), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.public_rounded, color: Color(0xFF167D86), size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('مسیر اتصال شما', style: TextStyle(color: Color(0xFF71808A), fontSize: 10)),
            const SizedBox(height: 4),
            Text(selected?.name ?? 'هنوز سروری انتخاب نشده', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF142A30), fontSize: 13, fontWeight: FontWeight.w800)),
            Text(_connectionPingMs == null ? 'برای مشاهده سرورها لمس کنید' : 'پینگ اتصال: $_connectionPingMs ms', style: const TextStyle(color: Color(0xFF167D86), fontSize: 10)),
          ])),
          const Icon(Icons.chevron_left_rounded, color: Color(0xFF167D86)),
        ]),
      ),
    ),
  );

  Widget _durationSummary() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE9EAF2))),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.schedule_rounded, color: Color(0xFF167D86), size: 21), const SizedBox(width: 10),
      Column(children: [
        const Text('مدت زمان اتصال', style: TextStyle(color: Color(0xFF71808A), fontSize: 11)),
        Text(durationText(elapsed), style: const TextStyle(color: Color(0xFF142A30), fontSize: 17, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    ]),
  );

  Future<void> _runPingTest(ServerItem server) async {
    if (!mounted) return;
    setState(() => _pingTesting.add(server.id));
    try {
      final config = EngineRouter.toXrayConfiguration(
        server.config,
        remoteDns: dnsAddress,
      );
      final delay = await NativeXray.measureOutboundDelay(config);
      if (mounted) setState(() => _pingResults[server.id] = delay);
    } catch (_) {
      if (mounted) setState(() => _pingResults[server.id] = -1);
    } finally {
      if (mounted) setState(() => _pingTesting.remove(server.id));
    }
  }

  Future<void> _testServer(ServerItem server) async {
    if (_testingAll || _pingTesting.contains(server.id)) return;
    await _runPingTest(server);
  }

  Future<void> _testAllServers() async {
    if (_testingAll || servers.isEmpty) return;
    setState(() => _testingAll = true);
    try {
      for (final server in servers) {
        if (!mounted) return;
        await _runPingTest(server);
      }
    } finally {
      if (mounted) setState(() => _testingAll = false);
    }
  }


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

  Widget _settingsPage() => ListView(primary: false, padding: const EdgeInsets.fromLTRB(18, 12, 18, 24), children: [
    _EntranceMotion(child: _topBar()),
    const SizedBox(height: 20),
    _EntranceMotion(delay: const Duration(milliseconds: 70), child: const Text('تنظیمات اتصال', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF142A30), fontSize: 21, fontWeight: FontWeight.w900))),
    const SizedBox(height: 18),
    _EntranceMotion(delay: const Duration(milliseconds: 140), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE9EAF2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Remote DNS (Xray)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF142A30))),
      const SizedBox(height: 8), const Text('درخواست‌های DNS پورت 53 از داخل تونل Xray و با TCP به این سرور ارسال می‌شوند. برای اعمال، اتصال را دوباره برقرار کنید.', style: TextStyle(fontSize: 11, color: Color(0xFF71808A))),
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
    ]))),
    const SizedBox(height: 12),
    _EntranceMotion(delay: const Duration(milliseconds: 230), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE9EAF2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('برنامه‌های خارج از VPN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF142A30))),
      const SizedBox(height: 8), const Text('ترافیک این برنامه‌ها از تونل VPN عبور نمی‌کند.', style: TextStyle(fontSize: 11, color: Color(0xFF71808A))),
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: _chooseExcludedApps, icon: const Icon(Icons.apps_rounded), label: Text('انتخاب برنامه‌ها (${excludedApps.length})'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
      if (excludedApps.isNotEmpty) ...[const SizedBox(height: 8), Text(excludedApps.map((p) => installedApps.firstWhere((a) => a['package'] == p, orElse: () => {'label': p})['label']).join('، '), style: const TextStyle(fontSize: 12, color: Color(0xFF71808A)))],
    ]))),
    const SizedBox(height: 14),
    _EntranceMotion(delay: const Duration(milliseconds: 310), child: const Text('برای اعمال DNS و فهرست استثناها، اتصال فعلی را قطع و دوباره وصل کنید.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF71808A), fontSize: 11))),
  ]);



  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
    child: Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.asset('assets/icon/vpn13_icon.jpg', width: 46, height: 46, fit: BoxFit.cover),
      ),
      const SizedBox(width: 10),
      const Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VPN13', style: TextStyle(color: Color(0xFF142A30), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.5)),
          SizedBox(height: 2),
          Text('اتصال امن و پایدار', style: TextStyle(color: Color(0xFF71808A), fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      )),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: connected ? const Color(0xFFE6F4F3) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE9EAF2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 7, color: connected ? const Color(0xFF32B68A) : status == _VpnStatus.connecting || status == _VpnStatus.disconnecting ? const Color(0xFFFFC66D) : const Color(0xFF9AA5AD)),
          const SizedBox(width: 6),
          Text(
            connected ? 'آنلاین' : status == _VpnStatus.connecting ? 'در حال اتصال' : status == _VpnStatus.disconnecting ? 'در حال قطع' : 'آفلاین',
            style: const TextStyle(color: Color(0xFF142A30), fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ]),
      ),
      const SizedBox(width: 9),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.memory(base64Decode(vpn13FlagBase64), width: 39, height: 24, fit: BoxFit.cover),
      ),
    ]),
  );

  Widget _connectionPanel() {
    final active = connected;
    final waiting = busy || status == _VpnStatus.connecting || status == _VpnStatus.disconnecting;
    final accent = active ? const Color(0xFF32B68A) : const Color(0xFF20A39A);
    final statusLabel = active
        ? 'اتصال برقرار است'
        : _checkingHandshake
            ? 'در حال بررسی سرور…'
            : status == _VpnStatus.connecting
                ? 'در حال اتصال…'
                : status == _VpnStatus.disconnecting
                    ? 'در حال قطع اتصال…'
                    : 'آماده اتصال';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF164B50), Color(0xFF102F38), Color(0xFF174B46)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF3C7880).withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .09), blurRadius: 28, spreadRadius: 1),
          const BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.shield_outlined, color: accent, size: 19),
          const SizedBox(width: 8),
          const Text('وضعیت امنیت اتصال', style: TextStyle(color: Color(0xFFC5D9DE), fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (active) Text(durationText(elapsed), style: const TextStyle(color: Color(0xFFE9FFFF), fontSize: 12, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 19),
        _ConnectionPulse(
          active: active,
          child: GestureDetector(
            onTap: waiting || selected == null ? null : (active ? disconnect : connect),
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: 188, height: 188,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent.withValues(alpha: .22), width: 1), boxShadow: [BoxShadow(color: accent.withValues(alpha: .12), blurRadius: 26, spreadRadius: 3)]),
                ),
                Container(
                  width: 164, height: 164,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent.withValues(alpha: .38), width: 2)),
                ),
                Container(
                  width: 138, height: 138,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [accent.withValues(alpha: .28), const Color(0xFF17343D), const Color(0xFF102832)]),
                    border: Border.all(color: accent.withValues(alpha: .75), width: 1.5),
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: .22), blurRadius: 22, spreadRadius: 2)],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (waiting)
                      const SizedBox(width: 43, height: 43, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF20A39A)))
                    else
                      Icon(active ? Icons.shield_rounded : Icons.power_settings_new_rounded, color: const Color(0xFF9DE8D2), size: 49),
                    const SizedBox(height: 9),
                    Text(active ? durationText(elapsed) : 'VPN13', style: const TextStyle(color: Color(0xFFF0FFFF), fontSize: 17, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
                  ]),
                ),
                Positioned(top: 11, right: 39, child: Icon(Icons.circle, size: 5, color: accent.withValues(alpha: .8))),
                Positioned(bottom: 20, left: 31, child: Icon(Icons.circle, size: 4, color: accent.withValues(alpha: .65))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(statusLabel, key: ValueKey(statusLabel), style: const TextStyle(color: Color(0xFFF0FFFF), fontSize: 20, fontWeight: FontWeight.w900)),
        ),
        if (_connectionPingMs != null) ...[
          const SizedBox(height: 5),
          Text('پینگ اتصال: $_connectionPingMs ms', style: const TextStyle(color: Color(0xFF9DE8D2), fontSize: 11, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 8),
        Text(selected == null ? 'ابتدا سرور را انتخاب کنید' : 'برای اتصال یا قطع، آیکون مرکزی را لمس کنید',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFC5D9DE), fontSize: 10)),
      ]),
    );
  }


  Widget _errorPanel(String details) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFC5D0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFD9485F), size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: SelectableText(
                details,
                style: const TextStyle(
                  color: Color(0xFFD9485F),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}