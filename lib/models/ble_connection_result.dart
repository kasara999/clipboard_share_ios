import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// Bluetooth スキャン画面から返す接続情報。
class BleConnectionResult {
  final Peripheral peripheral;
  final String token;
  final String displayName;

  const BleConnectionResult({
    required this.peripheral,
    required this.token,
    required this.displayName,
  });
}
