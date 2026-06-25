import 'dart:io' show Platform;

/// OS 名（dart:io Platform.operatingSystem）を UI 表示用ラベルに変換する。
class PlatformLabels {
  PlatformLabels._();

  static String desktop(String? platform) {
    switch (platform) {
      case 'macos':
        return 'Mac';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      default:
        return 'PC';
    }
  }

  static String mobile(String? platform) {
    switch (platform) {
      case 'ios':
        return 'iPhone';
      case 'android':
        return 'Android';
      default:
        return 'Mobile';
    }
  }

  static String localMobile() {
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android';
    return 'Mobile';
  }
}
