import 'package:flutter/services.dart';

/// ネイティブのクリップボード変化イベント（iOS / Android 共通チャンネル）。
class ClipboardEvents {
  static const _channel = EventChannel('clipsync/clipboard_events');

  static Stream<void> get changes =>
      _channel.receiveBroadcastStream().map((_) {});
}
