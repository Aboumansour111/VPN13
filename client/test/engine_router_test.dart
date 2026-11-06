import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn13_client/services/engine_router.dart';

void main() {
  group('EngineRouter', () {
    test('routes VLESS XHTTP share links to Xray', () {
      expect(
        EngineRouter.engineFor(
          'vless://00000000-0000-4000-8000-000000000000@example.com:443?type=xhttp&security=tls',
        ),
        VpnEngine.xray,
      );
    });

    test('routes sing-box XHTTP outbound to Xray', () {
      const outbound = {
        'type': 'vless',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '00000000-0000-4000-8000-000000000000',
        'transport': {'type': 'xhttp', 'path': '/edge', 'mode': 'auto'},
      };
      expect(EngineRouter.engineFor(jsonEncode(outbound)), VpnEngine.xray);
    });

    test('keeps ordinary sing-box outbound on sing-box', () {
      const outbound = {
        'type': 'vless',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '00000000-0000-4000-8000-000000000000',
        'transport': {'type': 'ws', 'path': '/edge'},
      };
      expect(EngineRouter.engineFor(jsonEncode(outbound)), VpnEngine.singBox);
    });

    test('converts sing-box XHTTP outbound to Xray JSON without downgrading', () {
      const outbound = {
        'type': 'vless',
        'tag': 'xhttp-test',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '00000000-0000-4000-8000-000000000000',
        'transport': {'type': 'xhttp', 'path': '/edge', 'mode': 'auto'},
        'tls': {'enabled': true, 'server_name': 'example.com'},
      };
      final result = jsonDecode(
        EngineRouter.toXrayConfiguration(jsonEncode(outbound)),
      ) as Map<String, dynamic>;
      final outbounds = result['outbounds'] as List;
      final stream = (outbounds.first as Map)['streamSettings'] as Map;
      expect(stream['network'], 'xhttp');
    });
  });
}
