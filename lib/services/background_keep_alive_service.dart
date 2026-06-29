import 'package:flutter/services.dart';

/// 接続中に OS がプロセスを止めないようネイティブへ依頼する。
/// Android: フォアグラウンドサービス（通知付き）
/// iOS: beginBackgroundTask（最大約30秒の延長 + 復帰時の再接続が本体）
class BackgroundKeepAliveService {
  static const _channel = MethodChannel('clipsync/background');

  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on PlatformException {
      // 権限不足等は無視（再接続でカバー）
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // ignore
    }
  }
}
