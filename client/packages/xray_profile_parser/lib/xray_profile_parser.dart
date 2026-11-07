// Copyright (c) 2024-2026 13FOX Studio / tfox.dev.
// SPDX-License-Identifier: MIT

import 'package:xray_profile_parser/url/hysteria2.dart';
import 'package:xray_profile_parser/url/shadowsocks.dart';
import 'package:xray_profile_parser/url/socks.dart';
import 'package:xray_profile_parser/url/subscription.dart';
import 'package:xray_profile_parser/url/trojan.dart';
import 'package:xray_profile_parser/url/url.dart';
import 'package:xray_profile_parser/url/vless.dart';
import 'package:xray_profile_parser/url/vmess.dart';
import 'package:xray_profile_parser/url/xray_config.dart';

/// Pure Dart parser for supported proxy links and Xray/sing-box/Clash profiles.
///
/// This package contains no platform plugin or native VPN runtime. It is used
/// only to convert imported profiles into Xray JSON for the AndroidLibXrayLite
/// runtime owned by VPN13.
class XrayProfileParser {
  XrayProfileParser._();

  /// Parses one supported share link, Xray JSON or subscription payload.
  static FlutterVlessURL parse(String input) {
    final trimmed = input.trim();
    if (_isSingleShareLink(trimmed)) {
      return parseFromUrl(trimmed);
    }
    return parseMany(trimmed).first;
  }

  /// Parses all supported profiles from a subscription, Clash YAML or sing-box JSON.
  static List<FlutterVlessURL> parseMany(String input) {
    return VlessSubscriptionParser.parseMany(
      input: input,
      parseUrl: parseFromUrl,
      parseJson: (json) => XrayJsonConfig(url: json),
    );
  }

  /// Parses one supported proxy share link.
  static FlutterVlessURL parseFromUrl(String url) {
    final separator = url.indexOf('://');
    if (separator <= 0) {
      throw ArgumentError('url is invalid');
    }
    final scheme = url.substring(0, separator).toLowerCase();
    final normalized = scheme + url.substring(separator);
    switch (scheme) {
      case 'vmess':
        return VmessURL(url: normalized);
      case 'vless':
        return VlessURL(url: normalized);
      case 'trojan':
        return TrojanURL(url: normalized);
      case 'ss':
        return ShadowSocksURL(url: normalized);
      case 'socks':
        return SocksURL(url: normalized);
      case 'hysteria2':
      case 'hy2':
        return Hysteria2URL(url: normalized);
      default:
        throw ArgumentError('url is invalid');
    }
  }

  static bool _isSingleShareLink(String input) {
    if (input.contains('\n') || input.contains('\r')) return false;
    final separator = input.indexOf('://');
    if (separator <= 0) return false;
    return const {
      'vmess',
      'vless',
      'trojan',
      'ss',
      'socks',
      'hysteria2',
      'hy2',
    }.contains(input.substring(0, separator).toLowerCase());
  }
}
