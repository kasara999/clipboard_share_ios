import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'clipboard_events.dart';
import 'native_pasteboard_service.dart';

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

/// モバイル（iOS / Android）クリップボード監視。
/// ネイティブのクリップボード変化イベントで検知する。
/// フォアグラウンド時のみ読み取り可能なため、
/// WidgetsBindingObserver と連携して外側から start/stop を呼ぶこと。
class ClipboardService {
  final _pasteboard = NativePasteboardService();

  StreamSubscription<void>? _clipboardSub;
  String? _lastText;
  String? _lastImageHash;
  bool _ignoreNext = false;

  final _itemController = StreamController<ClipboardItem>.broadcast();
  Stream<ClipboardItem> get itemStream => _itemController.stream;

  void startPolling() {
    if (_clipboardSub != null) return;
    _clipboardSub = ClipboardEvents.changes.listen(
      (_) => unawaited(_readClipboard()),
    );
  }

  void stopPolling() {
    unawaited(_clipboardSub?.cancel());
    _clipboardSub = null;
  }

  Future<void> _readClipboard() async {
    if (_ignoreNext) {
      _ignoreNext = false;
      return;
    }

    if (await _pasteboard.getHasStrings()) {
      final text = await _pasteboard.getText();
      if (text != null && text.isNotEmpty && text != _lastText) {
        _lastText = text;
        _itemController.add(ClipboardItem.text(text));
        return;
      }
    }

    if (await _pasteboard.getHasImages()) {
      try {
        final bytes = await _pasteboard.getImagePng();
        if (bytes != null) {
          final hash = base64Encode(bytes.sublist(0, bytes.length.clamp(0, 64)));
          if (hash != _lastImageHash) {
            _lastImageHash = hash;
            _itemController.add(ClipboardItem.image(bytes));
          }
        }
      } catch (_) {}
    }
  }

  /// リモート受信直後に OS クリップボード連携で同じ内容がローカルとして
  /// 検知されるのを防ぐ。
  void noteRemoteContent(ClipboardItem item) {
    if (item.type == ClipboardItemType.text) {
      _lastText = item.text;
    } else if (item.imageBytes != null) {
      _lastImageHash =
          base64Encode(item.imageBytes!.sublist(0, item.imageBytes!.length.clamp(0, 64)));
    }
  }

  /// リモートまたはアプリ内操作でクリップボードに書き込む
  Future<void> applyRemote(Map<String, dynamic> message) async {
    _ignoreNext = true;
    final type = message['content_type'] as String?;
    if (type == 'text') {
      final text = message['content'] as String?;
      if (text != null) {
        await _pasteboard.setText(text);
        _lastText = text;
      }
    } else if (type == 'image') {
      final b64 = message['content'] as String?;
      if (b64 != null) {
        await _pasteboard.setImage(base64Decode(b64));
        _lastImageHash = b64.substring(0, b64.length.clamp(0, 64));
      }
    }
  }

  void dispose() {
    stopPolling();
    _itemController.close();
  }
}
