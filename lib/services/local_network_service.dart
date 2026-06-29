import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// ローカルネットワーク許可の準備（iOS のみ。Android は不要）。
class LocalNetworkService {
  static const _channel = MethodChannel('clipsync/network');

  Future<void> prepareAccess({required String host, required int port}) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('prepareAccess', {
      'host': host,
      'port': port,
    });
  }

  static String messageFor(PlatformException e) {
    switch (e.code) {
      case 'local_network_denied':
        return 'ローカルネットワークが拒否されています。\n'
            '設定 → ClipSync → ローカルネットワーク をオンにしてください。';
      case 'unreachable':
        return 'PCに到達できません。\n'
            '同じWi-Fiに接続されているか、PCのファイアウォール設定を確認してください。';
      case 'timeout':
        return 'ネットワークの準備がタイムアウトしました。\n'
            '同じWi-Fiに接続されているか確認してください。';
      case 'cancelled':
        return 'ネットワークの準備が中断されました。\n'
            'もう一度接続を試してください。';
      default:
        return e.message ?? 'ネットワークエラー (${e.code})';
    }
  }
}
