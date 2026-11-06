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
    final input = hasOutbounds
        ? decoded
        : decoded.containsKey('type')
            ? <String, dynamic>{'outbounds': [decoded]}
            : throw const FormatException(
                'کانفیگ باید یک outbound یا پروفایل کامل sing-box باشد.',
              );

    return FlutterVless.parse(jsonEncode(input)).getFullConfiguration();
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
