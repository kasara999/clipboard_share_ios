import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import '../constants/ble_protocol.dart';
import 'ble_message_codec.dart';
import 'websocket_client.dart';

class DiscoveredPc {
  final Peripheral peripheral;
  final String? name;
  final int rssi;

  DiscoveredPc({
    required this.peripheral,
    required this.name,
    required this.rssi,
  });

  String get displayName =>
      name?.isNotEmpty == true ? name! : BleProtocol.advertiseName;
}

/// スマホ側 BLE Central（スキャン・接続・メッセージ送受信）。
class BleClientService {
  CentralManager? _manager;
  CentralManager get _mgr => _manager!;

  Peripheral? _peripheral;
  GATTCharacteristic? _messageCharacteristic;

  final _stateController = StreamController<ClientState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _discoveriesController =
      StreamController<List<DiscoveredPc>>.broadcast();

  ClientState _state = ClientState.disconnected;
  String? _lastError;
  String? _serverPlatform;
  final Map<int, String> _assemblyBuffer = {};

  StreamSubscription? _discoveredSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _notifiedSub;
  StreamSubscription? _stateSub;

  final List<DiscoveredPc> _discoveries = [];
  bool _discovering = false;

  Stream<ClientState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<List<DiscoveredPc>> get discoveriesStream =>
      _discoveriesController.stream;

  ClientState get state => _state;
  String? get lastError => _lastError;
  String? get serverPlatform => _serverPlatform;
  List<DiscoveredPc> get discoveries => List.unmodifiable(_discoveries);
  bool get isDiscovering => _discovering;
  BluetoothLowEnergyState get adapterState =>
      _manager?.state ?? BluetoothLowEnergyState.unknown;

  void _ensureManager() => _manager ??= CentralManager();

  Future<void> ensureAuthorized() async {
    _ensureManager();
    if (_mgr.state == BluetoothLowEnergyState.unauthorized) {
      await _mgr.authorize();
    }
  }

  Future<void> startDiscovery() async {
    _ensureManager();
    await ensureAuthorized();
    if (_discovering) return;

    _discoveries.clear();
    _discoveriesController.add(_discoveries);

    _discoveredSub ??= _mgr.discovered.listen(_onDiscovered);
    _stateSub ??= _mgr.stateChanged.listen((event) async {
      if (event.state == BluetoothLowEnergyState.unauthorized) {
        await ensureAuthorized();
      }
    });

    await _mgr.startDiscovery(serviceUUIDs: [BleProtocol.serviceUuid]);
    _discovering = true;
  }

  Future<void> stopDiscovery() async {
    if (!_discovering) return;
    await _mgr.stopDiscovery();
    _discovering = false;
  }

  void _onDiscovered(DiscoveredEventArgs event) {
    final name = event.advertisement.name;
    final serviceUuids = event.advertisement.serviceUUIDs;
    final matchesName = name == BleProtocol.advertiseName;
    final matchesService = serviceUuids.contains(BleProtocol.serviceUuid);
    if (!matchesName && !matchesService) return;

    final pc = DiscoveredPc(
      peripheral: event.peripheral,
      name: name,
      rssi: event.rssi,
    );
    final index = _discoveries.indexWhere(
      (d) => d.peripheral.uuid == pc.peripheral.uuid,
    );
    if (index < 0) {
      _discoveries.add(pc);
    } else {
      _discoveries[index] = pc;
    }
    _discoveries.sort((a, b) => b.rssi.compareTo(a.rssi));
    _discoveriesController.add(List.unmodifiable(_discoveries));
  }

  Future<String?> readDeviceToken(Peripheral peripheral) async {
    _ensureManager();
    try {
      await _mgr.connect(peripheral);
      await _waitForConnection(peripheral);

      final services = await _mgr.discoverGATT(peripheral);
      for (final service in services) {
        if (service.uuid != BleProtocol.serviceUuid) continue;
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid != BleProtocol.deviceInfoUuid) continue;
          final bytes =
              await _mgr.readCharacteristic(peripheral, characteristic);
          final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          return map['token'] as String?;
        }
      }
      return null;
    } finally {
      try {
        await _mgr.disconnect(peripheral);
      } catch (_) {}
    }
  }

  Future<void> connect(Peripheral peripheral, String token) async {
    _ensureManager();
    await disconnect();
    _assemblyBuffer.clear();
    _peripheral = peripheral;

    _setState(ClientState.connecting);
    Completer<void>? authCompleter;

    try {
      await ensureAuthorized();
      await stopDiscovery();

      _connectionSub ??= _mgr.connectionStateChanged.listen((event) {
        if (event.peripheral != _peripheral) return;
        if (event.state == ConnectionState.disconnected &&
            _state == ClientState.connected) {
          _lastError = 'Bluetooth 接続が切断されました';
          _setState(ClientState.disconnected);
        }
      });

      _notifiedSub ??= _mgr.characteristicNotified.listen(_onNotified);

      await _mgr.connect(peripheral);
      await _waitForConnection(peripheral);

      final services = await _mgr.discoverGATT(peripheral);
      GATTCharacteristic? messageChar;
      for (final service in services) {
        if (service.uuid != BleProtocol.serviceUuid) continue;
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == BleProtocol.messageUuid) {
            messageChar = characteristic;
            break;
          }
        }
      }
      if (messageChar == null) {
        throw StateError('ClipSync サービスが見つかりません');
      }
      _messageCharacteristic = messageChar;

      await _mgr.setCharacteristicNotifyState(
        peripheral,
        messageChar,
        state: true,
      );

      authCompleter = Completer<void>();
      _pendingAuthCompleter = authCompleter;

      _setState(ClientState.authenticating);
      await _writeMessage({
        'type': 'auth',
        'token': token,
        'platform': Platform.operatingSystem,
      });

      await authCompleter.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('Bluetooth 認証がタイムアウトしました'),
      );

      if (_state != ClientState.connected) {
        throw TimeoutException('Bluetooth 認証がタイムアウトしました');
      }
    } on TimeoutException catch (e) {
      _lastError = e.message;
      _setState(ClientState.error);
      await disconnect();
    } catch (e) {
      _lastError = 'Bluetooth 接続に失敗しました: $e';
      _setState(ClientState.error);
      await disconnect();
    } finally {
      _pendingAuthCompleter = null;
    }
  }

  Completer<void>? _pendingAuthCompleter;

  Future<void> _waitForConnection(Peripheral peripheral) async {
    final completer = Completer<void>();
  late final StreamSubscription sub;
    sub = _mgr.connectionStateChanged.listen((event) {
      if (event.peripheral != peripheral) return;
      if (event.state == ConnectionState.connected &&
          !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw TimeoutException('Bluetooth 接続がタイムアウトしました');
    } finally {
      await sub.cancel();
    }
  }

  void _onNotified(GATTCharacteristicNotifiedEventArgs event) {
    if (_peripheral == null || event.peripheral != _peripheral) return;
    if (event.characteristic.uuid != BleProtocol.messageUuid) return;

    final jsonText = BleMessageCodec.decodeChunk(
      event.value,
      assembly: _assemblyBuffer,
    );
    if (jsonText == null) return;

    try {
      final msg = jsonDecode(jsonText) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      if (type == 'auth_ok') {
        _serverPlatform = msg['platform'] as String?;
        _setState(ClientState.connected);
        final completer = _pendingAuthCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }
      if (type == 'auth_error') {
        _lastError = 'トークンが一致しません';
        _setState(ClientState.error);
        final completer = _pendingAuthCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        unawaited(disconnect());
        return;
      }

      if (_state == ClientState.connected) {
        _messageController.add(msg);
      }
    } catch (_) {}
  }

  Future<void> _writeMessage(Map<String, dynamic> message) async {
    final peripheral = _peripheral;
    final characteristic = _messageCharacteristic;
    if (peripheral == null || characteristic == null) return;

    final chunks = BleMessageCodec.encode(jsonEncode(message));
    for (final chunk in chunks) {
      await _mgr.writeCharacteristic(
        peripheral,
        characteristic,
        value: chunk,
        type: GATTCharacteristicWriteType.withResponse,
      );
    }
  }

  void send(Map<String, dynamic> message) {
    if (_state == ClientState.connected) {
      unawaited(_writeMessage(message));
    }
  }

  Future<void> disconnect() async {
    await stopDiscovery();
    final peripheral = _peripheral;
    _peripheral = null;
    _messageCharacteristic = null;
    _assemblyBuffer.clear();
    _serverPlatform = null;

    if (peripheral != null) {
      try {
        await _mgr.disconnect(peripheral);
      } catch (_) {}
    }

    if (_state != ClientState.error) {
      _setState(ClientState.disconnected);
    }
  }

  void _setState(ClientState s) {
    _state = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  void dispose() {
    _discoveredSub?.cancel();
    _connectionSub?.cancel();
    _notifiedSub?.cancel();
    _stateSub?.cancel();
    disconnect();
    _stateController.close();
    _messageController.close();
    _discoveriesController.close();
  }
}
