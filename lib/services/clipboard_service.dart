import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

enum ClipboardItemType { text, image }

class ClipboardItem {
  final ClipboardItemType type;
  final String? text;
  final Uint8List? imageBytes;
  final DateTime timestamp;

  ClipboardItem.text(this.text)
      : type = ClipboardItemType.text,
        imageBytes = null,
        timestamp = DateTime.now();

  ClipboardItem.image(this.imageBytes)
      : type = ClipboardItemType.image,
        text = null,
        timestamp = DateTime.now();
}

/// iOS クリップボード監視。
/// iOS はフォアグラウンド時のみ読み取り可能なため、
/// WidgetsBindingObserver と連携して外側から start/stop を呼ぶこと。
class ClipboardService {
  static const Duration _pollInterval = Duration(milliseconds: 500);

  Timer? _timer;
  String? _lastText;
  String? _lastImageHash;
  bool _ignoreNext = false;

  final _itemController = StreamController<ClipboardItem>.broadcast();
  Stream<ClipboardItem> get itemStream => _itemController.stream;

  void startPolling() {
    _timer ??= Timer.periodic(_pollInterval, (_) => _poll());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_ignoreNext) {
      _ignoreNext = false;
      return;
    }

    // テキスト確認
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && text != _lastText) {
      _lastText = text;
      _itemController.add(ClipboardItem.text(text));
      return;
    }

    // 画像確認
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null) {
        final hash = base64Encode(bytes.sublist(0, bytes.length.clamp(0, 64)));
        if (hash != _lastImageHash) {
          _lastImageHash = hash;
          _itemController.add(ClipboardItem.image(bytes));
        }
      }
    } catch (_) {}
  }

  /// リモートから受け取った内容をローカルに書き込む
  Future<void> applyRemote(Map<String, dynamic> message) async {
    _ignoreNext = true;
    final type = message['content_type'] as String?;
    if (type == 'text') {
      final text = message['content'] as String?;
      if (text != null) {
        await Clipboard.setData(ClipboardData(text: text));
        _lastText = text;
      }
    } else if (type == 'image') {
      final b64 = message['content'] as String?;
      if (b64 != null) {
        await Pasteboard.writeImage(base64Decode(b64));
        _lastImageHash = b64.substring(0, b64.length.clamp(0, 64));
      }
    }
  }

  void dispose() {
    stopPolling();
    _itemController.close();
  }
}
