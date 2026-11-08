import 'dart:convert';

import 'package:xray_profile_parser/xray_profile_parser.dart';

/// Converts supported profile inputs into a validated Xray-core configuration.
class EngineRouter {
  const EngineRouter._();

  /// Converts supported share links, sing-box profiles or raw Xray JSON into Xray JSON.
  /// Traffic counters are enabled for the native AndroidLibXrayLite controller.
  static String toXrayConfiguration(String source) {
    final value = source.trim();
    if (RegExp(r'^(vless|vmess|trojan|ss|socks|hysteria2|hy2)://', caseSensitive: false)
        .hasMatch(value)) {
      return _enableTrafficStats(XrayProfileParser.parse(value).getFullConfiguration());
    }

    final decoded = _tryDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('فرمت کانفیگ برای هسته Xray معتبر نیست.');
    }

    final hasOutbounds = decoded['outbounds'] is List;
    final outbounds = hasOutbounds
        ? (decoded['outbounds'] as List).whereType<Map<String, dynamic>>()
        : <Map<String, dynamic>>[
            if (decoded.containsKey('type')) decoded,
          ];
    Map<String, dynamic>? xhttp;
    for (final outbound in outbounds) {
      if (_isXhttpOutbound(outbound)) {
        xhttp = outbound;
        break;
      }
    }
    if (xhttp != null && xhttp['protocol'] == null) {
      return _enableTrafficStats(_xhttpOutboundToXray(xhttp));
    }

    final input = hasOutbounds
        ? decoded
        : decoded.containsKey('type')
            ? <String, dynamic>{'outbounds': [decoded]}
            : throw const FormatException(
                'کانفیگ باید یک outbound یا پروفایل کامل sing-box باشد.',
              );

    return _enableTrafficStats(XrayProfileParser.parse(jsonEncode(input)).getFullConfiguration());
  }

  static String _xhttpOutboundToXray(Map<String, dynamic> outbound) {
    final transport = outbound['transport'] is Map
        ? outbound['transport'] as Map
        : const <String, dynamic>{};
    final tls = outbound['tls'] is Map
        ? outbound['tls'] as Map
        : const <String, dynamic>{};
    final reality = tls['reality'] is Map
        ? tls['reality'] as Map
        : const <String, dynamic>{};
    final utls = tls['utls'] is Map
        ? tls['utls'] as Map
        : const <String, dynamic>{};
    final rawServer = outbound['server']?.toString();
    final server = rawServer != null && rawServer.startsWith('[') && rawServer.endsWith(']')
        ? rawServer.substring(1, rawServer.length - 1)
        : rawServer;
    final uuid = outbound['uuid']?.toString();
    final port = outbound['server_port'];
    if (server == null || server.isEmpty || uuid == null || uuid.isEmpty ||
        port is! num || port < 1 || port > 65535) {
      throw const FormatException('اطلاعات VLESS + XHTTP ناقص است.');
    }

    final query = <String, String>{
      'type': 'xhttp',
      'security': reality['enabled'] == true
          ? 'reality'
          : tls['enabled'] == true
              ? 'tls'
              : 'none',
    };
    void add(String key, Object? value) {
      if (value != null && value.toString().isNotEmpty) {
        query[key] = value.toString();
      }
    }

    add('sni', tls['server_name']);
    add('alpn', tls['alpn'] is List ? (tls['alpn'] as List).join(',') : tls['alpn']);
    add('fp', utls['fingerprint']);
    add('encryption', outbound['encryption']);
    add('pbk', reality['public_key']);
    add('sid', reality['short_id']);
    add('flow', outbound['flow']);
    add('host', transport['host']);
    add('path', transport['path']);
    add('mode', transport['mode']);
    if (transport['extra'] != null) {
      query['extra'] = jsonEncode(transport['extra']);
    }

    final uri = Uri(
      scheme: 'vless',
      userInfo: uuid,
      host: server,
      port: port.toInt(),
      queryParameters: query,
      fragment: outbound['tag']?.toString() ?? server,
    );
    return _enableTrafficStats(
      XrayProfileParser.parse(uri.toString()).getFullConfiguration(),
    );
  }

  static String _enableTrafficStats(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('پیکربندی تولیدشده Xray معتبر نیست.');
    }
    final config = Map<String, dynamic>.from(decoded);

    // AndroidLibXrayLite passes VpnService's file descriptor through
    // xray.tun.fd. Xray only reads packets from that descriptor when a TUN
    // inbound is present in the runtime configuration.
    final inbounds = config['inbounds'] is List
        ? List<dynamic>.from(config['inbounds'] as List)
        : <dynamic>[];
    inbounds.removeWhere(
      (inbound) => inbound is Map && inbound['protocol'] == 'tun',
    );
    inbounds.insert(0, <String, dynamic>{
      'tag': 'tun',
      'port': 0,
      'protocol': 'tun',
      'settings': <String, dynamic>{
        'name': 'VPN13',
        'mtu': 1500,
      },
    });
    config['inbounds'] = inbounds;

    // Remote DNS: send Xray's own DNS requests to the selected resolver over
    // TCP. The DNS module traffic follows routing and therefore uses the
    // profile's first (proxy) outbound instead of the phone's direct network.
    final outbounds = config['outbounds'] is List
        ? List<dynamic>.from(config['outbounds'] as List)
        : <dynamic>[];
    String? proxyTag;
    for (final item in outbounds) {
      if (item is Map<String, dynamic>) {
        final tag = item['tag']?.toString();
        final protocol = item['protocol']?.toString();
        if (tag != null && tag.isNotEmpty &&
            protocol != 'freedom' && protocol != 'blackhole' && protocol != 'dns') {
          proxyTag = tag;
          break;
        }
      }
    }
    proxyTag ??= outbounds.whereType<Map<String, dynamic>>()
        .map((item) => item['tag']?.toString())
        .whereType<String>().firstOrNull;

    config['dns'] = <String, dynamic>{
      'servers': ['tcp://1.1.1.1'],
      'queryStrategy': 'UseIPv4',
      'tag': 'vpn13-dns',
    };
    outbounds.removeWhere((item) =>
        item is Map && (item['tag'] == 'vpn13-dns-out' || item['tag'] == 'vpn13-dns-direct'));
    outbounds.add(<String, dynamic>{
      'tag': 'vpn13-dns-out',
      'protocol': 'dns',
      'settings': <String, dynamic>{
        'rules': <Map<String, dynamic>>[
          <String, dynamic>{'action': 'hijack'},
        <String, dynamic>{'action': 'direct'},
        ],
      },
      if (proxyTag != null) 'proxySettings': <String, dynamic>{'tag': proxyTag},
    });
    config['outbounds'] = outbounds;

    final routing = config['routing'] is Map
        ? Map<String, dynamic>.from(config['routing'] as Map)
        : <String, dynamic>{};
    final rules = routing['rules'] is List
        ? List<dynamic>.from(routing['rules'] as List)
        : <dynamic>[];
    rules.removeWhere((rule) =>
        rule is Map && rule['ruleTag'] == 'VPN13 DNS interception');
    rules.insert(0, <String, dynamic>{
      'type': 'field',
      'ruleTag': 'VPN13 DNS interception',
      'inboundTag': ['tun'],
      'network': 'tcp,udp',
      'port': '53',
      'outboundTag': 'vpn13-dns-out',
    });
    routing['rules'] = rules;
    config['routing'] = routing;

    config['stats'] = config['stats'] is Map
        ? Map<String, dynamic>.from(config['stats'] as Map)
        : <String, dynamic>{};
    final policy = config['policy'] is Map
        ? Map<String, dynamic>.from(config['policy'] as Map)
        : <String, dynamic>{};
    final system = policy['system'] is Map
        ? Map<String, dynamic>.from(policy['system'] as Map)
        : <String, dynamic>{};
    system['statsOutboundUplink'] = true;
    system['statsOutboundDownlink'] = true;
    policy['system'] = system;
    config['policy'] = policy;
    return jsonEncode(config);
  }

  static bool _isXhttpOutbound(Map<String, dynamic> outbound) {
    final transport = outbound['transport'];
    if (transport is Map &&
        (transport['type']?.toString().toLowerCase() == 'xhttp')) {
      return true;
    }

    final streamSettings = outbound['streamSettings'];
    return streamSettings is Map &&
        streamSettings['network']?.toString().toLowerCase() == 'xhttp';
  }

  static Object? _tryDecode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }
}
