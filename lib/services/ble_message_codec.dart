import 'dart:convert';
import 'dart:typed_data';

import '../constants/ble_protocol.dart';

/// BLE 向け JSON メッセージのチャンク分割・復元。
class BleMessageCodec {
  static List<Uint8List> encode(String json) {
    final bytes = utf8.encode(json);
    if (bytes.length <= BleProtocol.maxChunkBytes) {
      return [Uint8List.fromList(bytes)];
    }
    final chunks = <Uint8List>[];
    final total = (bytes.length / BleProtocol.maxChunkBytes).ceil();
    for (var i = 0; i < total; i++) {
      final start = i * BleProtocol.maxChunkBytes;
      final end = (start + BleProtocol.maxChunkBytes).clamp(0, bytes.length);
      final payload = base64Encode(bytes.sublist(start, end));
      final frame = jsonEncode({'i': i, 'n': total, 'p': payload});
      chunks.add(Uint8List.fromList(utf8.encode(frame)));
    }
    return chunks;
  }

  static String? decodeChunk(Uint8List data, {Map<int, String>? assembly}) {
    final text = utf8.decode(data);
    if (!text.startsWith('{')) {
      return text;
    }
    final map = jsonDecode(text) as Map<String, dynamic>;
    if (!map.containsKey('i')) {
      return text;
    }
    final index = map['i'] as int;
    final total = map['n'] as int;
    final payload = map['p'] as String;
    assembly ??= {};
    assembly[index] = payload;
    if (assembly.length < total) return null;
    final bytes = BytesBuilder();
    for (var i = 0; i < total; i++) {
      final part = assembly[i];
      if (part == null) return null;
      bytes.add(base64Decode(part));
    }
    assembly.clear();
    return utf8.decode(bytes.takeBytes());
  }
}
