import 'dart:convert';

import 'package:flutter_vless/flutter_vless.dart';

enum VpnEngine { singBox, xray }

/// Selects the runtime without silently translating XHTTP to another transport.
class EngineRouter {
  const EngineRouter._();

  static VpnEngine engineFor(String source) {
    final value = source.trim();
    if (_isXhttpShareLink(value)) return VpnEngine.xray;

    final decoded = _tryDecode(value);
    if (decoded is Map<String, dynamic>) {
      if (_isXhttpOutbound(decoded)) return VpnEngine.xray;
      final outbounds = decoded['outbounds'];
      if (outbounds is List &&
          outbounds.whereType<Map<String, dynamic>>().any(_isXhttpOutbound)) {
        return VpnEngine.xray;
      }
    }
    return VpnEngine.singBox;
  }

  /// Converts a sing-box outbound or profile into Xray JSON for flutter_vless.
  /// The Xray parser performs the protocol-specific conversion and validation.
  static String toXrayConfiguration(String source) {
    final value = source.trim();
    if (value.contains('://')) {
      return FlutterVless.parse(value).getFullConfiguration();
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
      return _xhttpOutboundToXray(xhttp);
    }

    final input = hasOutbounds
        ? decoded
        : decoded.containsKey('type')
            ? <String, dynamic>{'outbounds': [decoded]}
            : throw const FormatException(
                'کانفیگ باید یک outbound یا پروفایل کامل sing-box باشد.',
              );

    return FlutterVless.parse(jsonEncode(input)).getFullConfiguration();
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
    final server = outbound['server']?.toString();
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
    return FlutterVless.parse(uri.toString()).getFullConfiguration();
  }

  static bool _isXhttpShareLink(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !value.contains('://')) return false;
    final scheme = value.substring(0, value.indexOf('://')).toLowerCase();
    if (scheme != 'vless' && scheme != 'vmess' && scheme != 'trojan') {
      return false;
    }
    return (uri.queryParameters['type'] ??
            uri.queryParameters['net'] ??
            '')
        .toLowerCase() == 'xhttp';
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
