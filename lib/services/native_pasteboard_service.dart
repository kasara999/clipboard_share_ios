import 'package:flutter/services.dart';

/// iOS / Android ネイティブクリップボードへのアクセス。
class NativePasteboardService {
  static const _channel = MethodChannel('clipsync/pasteboard');

  Future<bool> getHasStrings() async {
    return await _channel.invokeMethod<bool>('hasStrings') ?? false;
  }

  Future<bool> getHasImages() async {
    return await _channel.invokeMethod<bool>('hasImages') ?? false;
  }

  Future<String?> getText() async {
    return await _channel.invokeMethod<String>('getText');
  }

  Future<Uint8List?> getImagePng() async {
    return await _channel.invokeMethod<Uint8List>('getImage');
  }

  Future<void> setText(String text) async {
    await _channel.invokeMethod<void>('setText', text);
  }

  Future<void> setImage(Uint8List pngData) async {
    await _channel.invokeMethod<void>('setImage', pngData);
  }
}
