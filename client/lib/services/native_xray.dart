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

  static Future<bool> requestPermission() async {
    return await _methods.invokeMethod<bool>('prepare') ?? false;
  }

  static Future<void> connect({
    required String config,
    required String profileName,
  }) async {
    await _methods.invokeMethod<bool>('connect', {
      'config': config,
      'profileName': profileName,
    });
  }

  static Future<void> disconnect() async {
    await _methods.invokeMethod<bool>('disconnect');
  }

  static Future<Map<String, dynamic>> status() async {
    final result = await _methods.invokeMapMethod<String, dynamic>('getStatus');
    return result ?? const {'state': 'unknown', 'message': ''};
  }

  static Future<String> version() async {
    return await _methods.invokeMethod<String>('getVersion') ?? 'Unknown';
  }
}
