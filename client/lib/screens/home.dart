import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/engine_router.dart';
import '../services/native_xray.dart';

enum _VpnStatus { disconnected, connecting, connected, disconnecting }

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
    super.dispose();
  }

  static const _serversCacheKey = 'vpn13_servers_cache_json';
  static const _serversFetchedAtKey = 'vpn13_servers_fetched_at';
  static const _serversRefreshInterval = Duration(hours: 24);

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
      if (mounted) setState(() => error = null);
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
    backgroundColor: const Color(0xFF081923),
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF102A36), Color(0xFF091923), Color(0xFF07141D)]),
      ),
      child: SafeArea(
      child: loading ? const Center(child: CircularProgressIndicator()) :
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 560),
          reverseDuration: const Duration(milliseconds: 440),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final settingsPage = child.key == const ValueKey<int>(1);
            final slide = Tween<Offset>(
              begin: Offset(settingsPage ? 0.16 : -0.16, 0.025),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ));
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: slide,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.965, end: 1).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_activeTab),
            child: _activeTab == 0 ? _homePage() : _settingsPage(),
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      height: 70, backgroundColor: const Color(0xFF10232D), indicatorColor: const Color(0xFF185D5C),
      selectedIndex: _activeTab,
      onDestinationSelected: (index) => setState(() => _activeTab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'خانه'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'تنظیمات'),
      ],
    ),
  );

  Widget _homePage() => RefreshIndicator(
    onRefresh: () => loadServers(force: true),
    child: ListView(
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        _EntranceMotion(child: _topBar()),
        const SizedBox(height: 18),
        _EntranceMotion(delay: const Duration(milliseconds: 70), child: _connectionPanel()),
        const SizedBox(height: 16),
        _EntranceMotion(
          delay: const Duration(milliseconds: 140),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _homeServersSection()),
              const SizedBox(width: 10),
              Expanded(child: _trafficPanel()),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _EntranceMotion(delay: const Duration(milliseconds: 280), child: _durationSummary()),
        if (connectionError != null) ...[const SizedBox(height: 12), _errorPanel(connectionError!)],
        if (error != null) ...[const SizedBox(height: 12), _errorPanel(error!)],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => loadServers(force: true), icon: const Icon(Icons.sync_rounded, size: 19),
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
    decoration: BoxDecoration(color: const Color(0xFF202E37), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF46555E))),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.schedule_rounded, color: Color(0xFFC5D0D5), size: 21), const SizedBox(width: 10),
      Column(children: [
        const Text('مدت زمان اتصال', style: TextStyle(color: Color(0xFF758297), fontSize: 11)),
        Text(durationText(elapsed), style: const TextStyle(color: Color(0xFFF0F3F4), fontSize: 17, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    ]),
  );

  Widget _homeServersSection() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1B303A),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF35545E)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.dns_rounded, color: Color(0xFF80E5D4), size: 17),
        SizedBox(width: 6),
        Expanded(child: Text('سرور', maxLines: 1, style: TextStyle(color: Color(0xFFEAFBFB), fontSize: 12, fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 8),
      DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: servers.any((s) => s.id == selectedId) ? selectedId : null,
          isExpanded: true,
          dropdownColor: const Color(0xFF203640),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF80E5D4), size: 18),
          style: const TextStyle(color: Color(0xFFEAFBFB), fontSize: 11, fontWeight: FontWeight.w700),
          hint: const Text('انتخاب سرور', style: TextStyle(color: Color(0xFF9BB8C1), fontSize: 11)),
          items: servers.map((server) => DropdownMenuItem<int>(
            value: server.id,
            child: Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: status != _VpnStatus.disconnected || busy ? null : (id) {
            final server = servers.where((s) => s.id == id).firstOrNull;
            if (server != null) selectServer(server);
          },
        ),
      ),
      if (selected != null && _pingResults.containsKey(selectedId)) ...[
        const SizedBox(height: 4),
        Text(_pingResults[selectedId]! >= 0 ? '${_pingResults[selectedId]} ms' : 'پینگ ناموفق',
          style: const TextStyle(color: Color(0xFF80E5D4), fontSize: 10)),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          tooltip: 'تست پینگ سرور',
          onPressed: selected == null || _pingTesting.contains(selectedId) ? null : () => _testServer(selected!),
          icon: _pingTesting.contains(selectedId)
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.speed_rounded, color: Color(0xFF80E5D4), size: 17),
        ),
      ),
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
    if (_testingAll || _pingTesting.isNotEmpty || servers.isEmpty) return;
    setState(() {
      _testingAll = true;
      _pingResults.clear();
    });
    try {
      // Two independent Xray test instances at a time keeps memory and CPU use bounded.
      for (var i = 0; i < servers.length; i += 2) {
        final batch = servers.skip(i).take(2).toList();
        await Future.wait(batch.map(_runPingTest));
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
    _EntranceMotion(delay: const Duration(milliseconds: 70), child: const Text('تنظیمات اتصال', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFF0F3F4), fontSize: 21, fontWeight: FontWeight.w900))),
    const SizedBox(height: 18),
    _EntranceMotion(delay: const Duration(milliseconds: 140), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF35434C), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF46555E))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    ]))),
    const SizedBox(height: 12),
    _EntranceMotion(delay: const Duration(milliseconds: 230), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF35434C), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF46555E))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('برنامه‌های خارج از VPN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFF0F3F4))),
      const SizedBox(height: 8), const Text('ترافیک این برنامه‌ها از تونل VPN عبور نمی‌کند.', style: TextStyle(fontSize: 11, color: Color(0xFFB5C0C6))),
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: _chooseExcludedApps, icon: const Icon(Icons.apps_rounded), label: Text('انتخاب برنامه‌ها (${excludedApps.length})'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
      if (excludedApps.isNotEmpty) ...[const SizedBox(height: 8), Text(excludedApps.map((p) => installedApps.firstWhere((a) => a['package'] == p, orElse: () => {'label': p})['label']).join('، '), style: const TextStyle(fontSize: 12, color: Color(0xFFC5D0D5)))],
    ]))),
    const SizedBox(height: 14),
    _EntranceMotion(delay: const Duration(milliseconds: 310), child: const Text('برای اعمال DNS و فهرست استثناها، اتصال فعلی را قطع و دوباره وصل کنید.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB5C0C6), fontSize: 11))),
  ]);



  Widget _topBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF263F4B), Color(0xFF142832), Color(0xFF10212B)],
          ),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: const Color(0xFF4A7D82).withValues(alpha: .55)),
          boxShadow: [
            BoxShadow(color: const Color(0xFF36DCC5).withValues(alpha: .08), blurRadius: 24, spreadRadius: 1),
          ],
        ),
        child: Column(children: [
          const Text(
            'اللهم صل علی محمد و آل محمد الائمه و المهدیین و سلم تسلیما',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9BE9DF), fontSize: 12, fontWeight: FontWeight.w800, height: 1.6),
          ),
          const SizedBox(height: 12),
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset('assets/icon/vpn13_icon.jpg', width: 49, height: 49, fit: BoxFit.cover),
            ),
            const SizedBox(width: 11),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VPN13', style: TextStyle(color: Color(0xFFF1FFFF), fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: .4)),
                SizedBox(height: 2),
                Text('اتصال امن و پایدار', style: TextStyle(color: Color(0xFF9BB8C1), fontSize: 11)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: connected ? const Color(0xFF0D604F).withValues(alpha: .55) : const Color(0xFF30424C),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: connected ? const Color(0xFF4CE0B5) : const Color(0xFF58717A)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: connected ? const Color(0xFF4CE0B5) : status == _VpnStatus.connecting || status == _VpnStatus.disconnecting ? const Color(0xFFFFC66D) : const Color(0xFF8499A2)),
                const SizedBox(width: 7),
                Text(
                  connected ? 'آنلاین' : status == _VpnStatus.connecting ? 'در حال اتصال' : status == _VpnStatus.disconnecting ? 'در حال قطع' : 'آفلاین',
                  style: const TextStyle(color: Color(0xFFE8F7F6), fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
          ]),
        ]),
      );

  Widget _connectionPanel() {
    final active = connected;
    final waiting = busy || status == _VpnStatus.connecting || status == _VpnStatus.disconnecting;
    final accent = active ? const Color(0xFF42E4C2) : const Color(0xFF36B8C5);
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
          colors: [Color(0xFF203B48), Color(0xFF142A35), Color(0xFF10232D)],
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
          const Text('وضعیت امنیت اتصال', style: TextStyle(color: Color(0xFFB5CED2), fontSize: 12, fontWeight: FontWeight.w700)),
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
                    gradient: RadialGradient(colors: [accent.withValues(alpha: .28), const Color(0xFF102832), const Color(0xFF0C1D27)]),
                    border: Border.all(color: accent.withValues(alpha: .75), width: 1.5),
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: .22), blurRadius: 22, spreadRadius: 2)],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (waiting)
                      const SizedBox(width: 43, height: 43, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF83F2E1)))
                    else
                      Icon(active ? Icons.shield_rounded : Icons.power_settings_new_rounded, color: const Color(0xFF79F0E0), size: 49),
                    const SizedBox(height: 9),
                    Text(active ? durationText(elapsed) : 'VPN13', style: const TextStyle(color: Color(0xFFE8FFFF), fontSize: 17, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
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
          Text('پینگ اتصال: $_connectionPingMs ms', style: const TextStyle(color: Color(0xFF83E8D8), fontSize: 11, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 8),
        Text(selected == null ? 'ابتدا سرور را انتخاب کنید' : 'برای اتصال یا قطع، آیکون مرکزی را لمس کنید',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8EADB7), fontSize: 10)),
      ]),
    );
  }


  Widget _trafficPanel() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1B303A),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF35545E)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.swap_vert_rounded, color: Color(0xFF80E5D4), size: 17),
        SizedBox(width: 6),
        Expanded(child: Text('ترافیک', style: TextStyle(color: Color(0xFFEAFBFB), fontSize: 12, fontWeight: FontWeight.w800))),
        Icon(Icons.circle, color: Color(0xFF52DDBB), size: 6),
      ]),
      const SizedBox(height: 10),
      _miniTrafficLine(Icons.south_rounded, 'دریافت', speedText(downloadSpeed), bytesText(downloadTotal)),
      const SizedBox(height: 7),
      _miniTrafficLine(Icons.north_rounded, 'ارسال', speedText(uploadSpeed), bytesText(uploadTotal)),
    ]),
  );

  Widget _miniTrafficLine(IconData icon, String label, String speed, String total) => Row(
    children: [
      Icon(icon, color: const Color(0xFF80E5D4), size: 14),
      const SizedBox(width: 4),
      Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF9BB8C1), fontSize: 10))),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(speed, maxLines: 1, style: const TextStyle(color: Color(0xFFEAFBFB), fontSize: 10, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        Text(total, maxLines: 1, style: const TextStyle(color: Color(0xFF80E5D4), fontSize: 9, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    ],
  );

  Widget _trafficValue({
    required IconData icon,
    required String title,
    required String speed,
    required String total,
    required Color color,
  }) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF203B45), Color(0xFF10232C)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .32)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .07), blurRadius: 12)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(color: Color(0xFFB5D0D3), fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(speed, key: ValueKey(speed), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(height: 5),
          Text('حجم کل: $total', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9BB8C1), fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
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
