import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sing_box/sing_box.dart';

import '../config.dart';

class ServerItem {
  const ServerItem({required this.id, required this.name, this.description});
  final int id;
  final String name;
  final String? description;

  factory ServerItem.fromJson(Map<String, dynamic> json) => ServerItem(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const navy = Color(0xFF092B68);
  static const blue = Color(0xFF174BC4);
  static const muted = Color(0xFF64749A);
  final secure = const FlutterSecureStorage();

  List<ServerItem> servers = [];
  int? selectedId;
  bool loading = true, busy = false;
  String? error, token;
  StreamSubscription<SingBoxConnectionStatus>? statusSub;
  StreamSubscription<SingBoxConnectionStats>? statsSub;
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
    loadServers();
  }

  @override
  void dispose() {
    statusSub?.cancel();
    statsSub?.cancel();
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
          .get(Uri.parse('${AppConfig.apiBaseUrl}/api/servers'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final list = (jsonDecode(response.body) as List)
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
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'ارتباط با سرور برقرار نشد. آدرس API و اینترنت را بررسی کنید.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> ensureAccess() async {
    token = await secure.read(key: 'sharedClientToken');
    if (token != null) return true;
    if (!mounted) return false;
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('ورود به VPN13'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'کد دسترسی',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('ورود'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return false;
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/client/access'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('کد دسترسی صحیح نیست.');
      }
      token = jsonDecode(response.body)['access_token'] as String;
      await secure.write(key: 'sharedClientToken', value: token);
      return true;
    } catch (e) {
      if (mounted) message('ورود ناموفق بود: $e');
      return false;
    }
  }

  Future<http.Response> getProfile() => http
      .get(
        Uri.parse(
          '${AppConfig.apiBaseUrl}/api/client/servers/$selectedId/profile',
        ),
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(const Duration(seconds: 15));

  Future<void> connect() async {
    if (selectedId == null || busy || !await ensureAccess()) return;
    setState(() => busy = true);
    try {
      var response = await getProfile();
      if (response.statusCode == 401 || response.statusCode == 403) {
        await secure.delete(key: 'sharedClientToken');
        token = null;
        if (!await ensureAccess()) return;
        response = await getProfile();
      }
      if (response.statusCode != 200) {
        throw Exception('پروفایل اتصال در دسترس نیست.');
      }
      final config = jsonDecode(response.body)['config'] as String;
      if (SingBox.instance.status.isActive) {
        await SingBox.instance.disconnect();
      }
      await SingBox.instance.requestNotificationPermission();
      await SingBox.instance.connect(config);
    } catch (e) {
      if (mounted) message('اتصال ناموفق بود: $e');
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
      if (mounted) message('قطع اتصال ناموفق بود: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseServer() async {
    if (servers.isEmpty || connected || busy) return;
    final id = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: RadioGroup<int>(
            groupValue: selectedId,
            onChanged: (value) => Navigator.pop(ctx, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('انتخاب سرور',
                    style: TextStyle(
                        color: navy,
                        fontSize: 19,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...servers.map((server) => ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFEAF0FF),
                        child: Icon(Icons.public, color: blue),
                      ),
                      title: Text(server.name),
                      subtitle: Text(server.description?.isNotEmpty == true
                          ? server.description!
                          : 'سرور فعال'),
                      trailing: Radio<int>(value: server.id),
                      onTap: () => Navigator.pop(ctx, server.id),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selectedServer', id);
    if (mounted) setState(() => selectedId = id);
  }

  void message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
    );
  }

  String durationText(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:'
      '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  String bytesText(int n) {
    if (n < 1024) return '$n B';
    if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        bottom: false,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: loadServers,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    header(),
                    const SizedBox(height: 24),
                    statusCard(),
                    const SizedBox(height: 22),
                    powerIcon(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: FilledButton(
                        onPressed: busy || selected == null
                            ? null
                            : (connected ? disconnect : connect),
                        child: busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(connected ? 'قطع اتصال' : 'اتصال'),
                      ),
                    ),
                    const SizedBox(height: 28),
                    serverSection(),
                    if (connected && stats != null) trafficCards(),
                    if (error != null) errorPanel(),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
      ),
    );
  }

  Widget header() => Container(
        height: 222,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF061F50), Color(0xFF12489B), Color(0xFF0A3478)],
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
        ),
        child: Column(
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFE8C77C), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: Color(0x66E8C77C))),
              const SizedBox(width: 10),
              const Icon(Icons.auto_awesome, color: Color(0xFFE8C77C), size: 18),
            ]),
            const SizedBox(height: 20),
            const Text(
              'اللَّهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ وَآلِ مُحَمَّدٍ',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.8,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_rounded, color: Color(0xFFE8C77C), size: 28),
                SizedBox(width: 9),
                Text('VPN13',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2)),
              ],
            ),
          ],
        ),
      );

  Widget statusCard() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          decoration: BoxDecoration(
              color: const Color(0xFFEAF0FF),
              borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            const Text('وضعیت اتصال',
                style: TextStyle(color: muted, fontSize: 15)),
            const SizedBox(height: 5),
            Text(connected ? 'متصل' : 'متصل نیست',
                style: TextStyle(
                    color: connected ? const Color(0xFF149B72) : navy,
                    fontSize: 27,
                    fontWeight: FontWeight.w800)),
            if (connected)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text('مدت اتصال: ${durationText(elapsed)}',
                    style: const TextStyle(color: muted, fontSize: 13)),
              ),
          ]),
        ),
      );

  Widget powerIcon() {
    final color = connected ? const Color(0xFF149B72) : blue;
    return Center(
      child: Container(
        width: 164,
        height: 164,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.07),
          border: Border.all(color: color.withValues(alpha: 0.16), width: 10),
        ),
        child: Container(
          margin: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: color, width: 4)),
          child: Icon(
              connected ? Icons.shield_rounded : Icons.power_settings_new,
              color: color,
              size: 66),
        ),
      ),
    );
  }

  Widget serverSection() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Expanded(child: Divider(color: Color(0xFFD5DDF0))),
            Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.public, color: muted, size: 23)),
            Expanded(child: Divider(color: Color(0xFFD5DDF0))),
          ]),
          const SizedBox(height: 15),
          const Text('انتخاب سرور',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: navy, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 13),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: chooseServer,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFDCE4F5))),
                child: Row(children: [
                  const CircleAvatar(
                      radius: 25,
                      backgroundColor: Color(0xFFEAF0FF),
                      child: Icon(Icons.public, color: blue, size: 27)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selected?.name ?? 'سروری انتخاب نشده',
                              style: const TextStyle(
                                  color: navy,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(selected == null ? 'سرور در دسترس نیست' : 'فعال',
                              style: const TextStyle(color: muted, fontSize: 13)),
                        ]),
                  ),
                  Icon(connected ? Icons.lock_outline : Icons.keyboard_arrow_down,
                      color: navy, size: 27),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
                color: const Color(0xFFEAF0FF),
                borderRadius: BorderRadius.circular(30)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.info_outline, color: muted, size: 19),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  connected
                      ? 'برای تغییر سرور، ابتدا اتصال را قطع کنید'
                      : 'برای اتصال، ابتدا یک سرور انتخاب کنید',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget trafficCards() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
        child: Row(children: [
          Expanded(
              child: trafficCard(Icons.south, 'دریافت',
                  bytesText(stats!.downloadTotal))),
          const SizedBox(width: 10),
          Expanded(
              child: trafficCard(
                  Icons.north, 'ارسال', bytesText(stats!.uploadTotal))),
        ]),
      );

  Widget trafficCard(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFDCE4F5))),
        child: Row(children: [
          Icon(icon, color: blue, size: 21),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: const TextStyle(color: muted, fontSize: 12)),
                Text(value,
                    style: const TextStyle(
                        color: navy, fontWeight: FontWeight.bold)),
              ])),
        ]),
      );

  Widget errorPanel() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        child: OutlinedButton.icon(
            onPressed: loadServers,
            icon: const Icon(Icons.refresh),
            label: Text(error!)),
      );
}
