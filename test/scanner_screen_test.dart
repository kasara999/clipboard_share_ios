import 'package:clipboard_share_ios/screens/scanner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseQrData', () {
    test('有効なQRデータをパースする', () {
      const raw = 'clipsync://192.168.1.10:8765?token=abc123';
      final info = parseQrData(raw);

      expect(info, isNotNull);
      expect(info!.ip, '192.168.1.10');
      expect(info.port, 8765);
      expect(info.token, 'abc123');
    });

    test('ポート省略時は8765を使う', () {
      const raw = 'clipsync://192.168.0.5?token=xyz';
      final info = parseQrData(raw);

      expect(info?.port, 8765);
    });

    test('無効なIPは拒否する', () {
      expect(parseQrData('clipsync://0.0.0.0:8765?token=abc'), isNull);
      expect(parseQrData('clipsync://8.8.8.8:8765?token=abc'), isNull);
      expect(parseQrData('clipsync://127.0.0.1:8765?token=abc'), isNull);
    });

    test('スキーム・トークン不正は拒否する', () {
      expect(parseQrData('http://192.168.1.1?token=abc'), isNull);
      expect(parseQrData('clipsync://192.168.1.1:8765'), isNull);
      expect(parseQrData('clipsync://192.168.1.1:8765?token='), isNull);
    });
  });
}
