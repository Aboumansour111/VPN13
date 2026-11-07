import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vpn13_client/services/engine_router.dart';

void main() {
  group('Xray configuration conversion', () {
    test('converts a Shadowsocks 2022 sing-box outbound', () {
      const outbound = {
        'type': 'shadowsocks',
        'tag': 'vpn13-ss',
        'server': 'ss.example.com',
        'server_port': 443,
        'method': '2022-blake3-aes-256-gcm',
        'password': 'server-key:client-key',
      };
      final result = jsonDecode(
        EngineRouter.toXrayConfiguration(jsonEncode(outbound)),
      ) as Map<String, dynamic>;
      final proxy = (result['outbounds'] as List).first as Map;
      final server = ((proxy['settings'] as Map)['servers'] as List).first as Map;
      expect(proxy['protocol'], 'shadowsocks');
      expect(server['method'], '2022-blake3-aes-256-gcm');
      expect(server['password'], 'server-key:client-key');
    });

    test('preserves XHTTP transport and enables outbound traffic counters', () {
      const outbound = {
        'type': 'vless',
        'tag': 'xhttp-test',
        'server': 'example.com',
        'server_port': 443,
        'uuid': '00000000-0000-4000-8000-000000000000',
        'transport': {
          'type': 'xhttp',
          'path': '/edge',
          'mode': 'auto',
          'extra': {'xPaddingBytes': '100-1000'},
        },
        'tls': {
          'enabled': true,
          'server_name': 'example.com',
          'reality': {
            'enabled': true,
            'public_key': 'public-key',
            'short_id': 'abcd1234',
          },
        },
      };
      final result = jsonDecode(
        EngineRouter.toXrayConfiguration(jsonEncode(outbound)),
      ) as Map<String, dynamic>;
      final proxy = (result['outbounds'] as List).first as Map;
      final stream = proxy['streamSettings'] as Map;
      expect(stream['network'], 'xhttp');
      expect((stream['xhttpSettings'] as Map)['mode'], 'auto');
      expect(result['stats'], isA<Map>());
      final system = ((result['policy'] as Map)['system'] as Map);
      expect(system['statsOutboundUplink'], true);
      expect(system['statsOutboundDownlink'], true);
    });
  });
}
