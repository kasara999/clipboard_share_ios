import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// ClipSync BLE GATT 定義（PC = Peripheral、スマホ = Central）。
class BleProtocol {
  static final serviceUuid = UUID.short(0xC151);
  static final deviceInfoUuid = UUID.short(0xC152);
  static final messageUuid = UUID.short(0xC153);

  static const advertiseName = 'ClipSync';
  static const protocolVersion = 1;

  static const maxChunkBytes = 400;
}
