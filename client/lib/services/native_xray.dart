import 'dart:async';

import 'package:flutter/services.dart';

/// Flutter bridge to VPN13's Android VpnService and AndroidLibXrayLite.
class NativeXray {
  NativeXray._();

  static const MethodChannel _methods = MethodChannel('vpn13/xray');
  static const EventChannel _events = EventChannel('vpn13/xray/events');

  static Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, dynamic>.from(event as Map));

  static Future<bool> requestNotificationPermission() async {
    return await _methods.invokeMethod<bool>('requestNotifications') ?? false;
  }

  static Future<bool> requestPermission() async {
    return await _methods.invokeMethod<bool>('prepare') ?? false;
  }

  static Future<List<Map<String, String>>> installedApps() async {
    final result = await _methods.invokeListMethod<dynamic>('getApps');
    return (result ?? []).map((item) => Map<String, String>.from(item as Map)).toList();
  }

  static Future<void> connect({
    required String config,
    required String profileName,
    String dnsAddress = '1.1.1.1',
    List<String> excludedApps = const [],
  }) async {
    await _methods.invokeMethod<bool>('connect', {
      'config': config,
      'profileName': profileName,
      'dnsAddress': dnsAddress,
      'excludedApps': excludedApps,
    });
  }

  static Future<void> disconnect() async {
    await _methods.invokeMethod<bool>('disconnect');
  }

  static Future<Map<String, dynamic>> status() async {
    final result = await _methods.invokeMapMethod<String, dynamic>('getStatus');
    return result ?? const {'state': 'unknown', 'message': ''};
  }

  static Future<int> measureOutboundDelay(String config) async {
    final result = await _methods.invokeMethod<int>('measureOutboundDelay', {
      'config': config,
      'url': 'https://www.google.com/generate_204',
    });
    if (result == null || result < 0) {
      throw Exception('پاسخی از سرور دریافت نشد.');
    }
    return result;
  }

  static Future<String> version() async {
    return await _methods.invokeMethod<String>('getVersion') ?? 'Unknown';
  }
}
