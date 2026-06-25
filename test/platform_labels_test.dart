import 'package:clipboard_share_ios/constants/platform_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformLabels', () {
    test('desktop labels', () {
      expect(PlatformLabels.desktop('macos'), 'Mac');
      expect(PlatformLabels.desktop('windows'), 'Windows');
      expect(PlatformLabels.desktop(null), 'PC');
    });
  });
}
