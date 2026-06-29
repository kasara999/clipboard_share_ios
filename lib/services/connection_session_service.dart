import 'dart:async';
import 'dart:io' show Platform;

import '../models/ble_connection_result.dart';
import '../models/connection_info.dart';
import 'background_keep_alive_service.dart';
import 'ble_client_service.dart';
import 'websocket_client.dart';

enum SessionTransport { none, lan, ble }

/// WebSocket / Bluetooth 接続の維持・自動再接続を担当する。
class ConnectionSessionService {
  final WebSocketClient _lanClient = WebSocketClient();
  final BleClientService _bleClient = BleClientService();
  final BackgroundKeepAliveService _keepAlive = BackgroundKeepAliveService();

  ConnectionInfo? _savedLanInfo;
  BleConnectionResult? _savedBleInfo;
  SessionTransport _transport = SessionTransport.none;

  bool _userDisconnected = false;
  bool _appInForeground = true;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  StreamSubscription<ClientState>? _lanStateSub;
  StreamSubscription<ClientState>? _bleStateSub;
  final _stateRelay = StreamController<ClientState>.broadcast();
  final _messageRelay = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _lanMessageSub;
  StreamSubscription<Map<String, dynamic>>? _bleMessageSub;

  Stream<ClientState> get stateStream => _stateRelay.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageRelay.stream;
  ClientState get state => _activeClient.state;
  String? get lastError => _activeClient.lastError;
  String? get serverPlatform => _activeClient.serverPlatform;
  ConnectionInfo? get savedInfo => _savedLanInfo;
  BleConnectionResult? get savedBleInfo => _savedBleInfo;
  SessionTransport get transport => _transport;
  BleClientService get bleClient => _bleClient;

  dynamic get _activeClient {
    return switch (_transport) {
      SessionTransport.ble => _bleClient,
      SessionTransport.lan || SessionTransport.none => _lanClient,
    };
  }

  Future<void> connectLan(ConnectionInfo info) async {
    await _switchTransport(SessionTransport.lan);
    _bindStateRelay(_lanClient);
    _userDisconnected = false;
    _reconnectAttempt = 0;
    _savedLanInfo = info;
    _savedBleInfo = null;
    _reconnectTimer?.cancel();
    await _lanClient.connect(info.ip, info.port, info.token);
    if (_lanClient.state == ClientState.connected) {
      await _keepAlive.start();
    }
  }

  Future<void> connectBle(BleConnectionResult result) async {
    await _switchTransport(SessionTransport.ble);
    _bindStateRelay(_bleClient);
    _userDisconnected = false;
    _reconnectAttempt = 0;
    _savedBleInfo = result;
    _savedLanInfo = null;
    _reconnectTimer?.cancel();
    await _bleClient.connect(result.peripheral, result.token);
    if (_bleClient.state == ClientState.connected) {
      await _keepAlive.start();
    }
  }

  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _savedLanInfo = null;
    _savedBleInfo = null;
    await _keepAlive.stop();
    await _lanClient.disconnect();
    await _bleClient.disconnect();
    _transport = SessionTransport.none;
  }

  void send(Map<String, dynamic> message) {
    switch (_transport) {
      case SessionTransport.lan:
        _lanClient.send(message);
      case SessionTransport.ble:
        _bleClient.send(message);
      case SessionTransport.none:
        break;
    }
  }

  void onAppLifecycle(bool inForeground) {
    _appInForeground = inForeground;
    if (inForeground) {
      _reconnectAttempt = 0;
      unawaited(_ensureConnected());
    }
  }

  void onUnexpectedDisconnect() {
    if (_userDisconnected) return;
    if (_savedLanInfo == null && _savedBleInfo == null) return;
    unawaited(_keepAlive.stop());
    _scheduleReconnect();
  }

  Future<void> _ensureConnected() async {
    if (_userDisconnected) return;

    switch (_transport) {
      case SessionTransport.lan:
        final info = _savedLanInfo;
        if (info == null) return;
        if (_lanClient.state == ClientState.connected ||
            _lanClient.state == ClientState.connecting ||
            _lanClient.state == ClientState.authenticating) {
          return;
        }
        await _lanClient.connect(info.ip, info.port, info.token);
        if (_lanClient.state == ClientState.connected) {
          _reconnectAttempt = 0;
          await _keepAlive.start();
        } else if (!_userDisconnected && _savedLanInfo != null) {
          _scheduleReconnect();
        }
      case SessionTransport.ble:
        final info = _savedBleInfo;
        if (info == null) return;
        if (_bleClient.state == ClientState.connected ||
            _bleClient.state == ClientState.connecting ||
            _bleClient.state == ClientState.authenticating) {
          return;
        }
        await _bleClient.connect(info.peripheral, info.token);
        if (_bleClient.state == ClientState.connected) {
          _reconnectAttempt = 0;
          await _keepAlive.start();
        } else if (!_userDisconnected && _savedBleInfo != null) {
          _scheduleReconnect();
        }
      case SessionTransport.none:
        return;
    }
  }

  void _scheduleReconnect() {
    if (_userDisconnected) return;
    if (_savedLanInfo == null && _savedBleInfo == null) return;
    if (!_appInForeground && !Platform.isAndroid) return;

    _reconnectTimer?.cancel();
    final delay = switch (_reconnectAttempt) {
      0 => const Duration(seconds: 2),
      1 => const Duration(seconds: 5),
      _ => const Duration(seconds: 10),
    };
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      unawaited(_ensureConnected());
    });
  }

  Future<void> _switchTransport(SessionTransport next) async {
    if (_transport == next) return;
    await _lanClient.disconnect();
    await _bleClient.disconnect();
    _transport = next;
    await _lanStateSub?.cancel();
    await _bleStateSub?.cancel();
    _lanStateSub = null;
    _bleStateSub = null;
  }

  void _bindStateRelay(dynamic client) {
    unawaited(_lanStateSub?.cancel());
    unawaited(_bleStateSub?.cancel());
    unawaited(_lanMessageSub?.cancel());
    unawaited(_bleMessageSub?.cancel());
    _lanStateSub = null;
    _bleStateSub = null;
    _lanMessageSub = null;
    _bleMessageSub = null;

    if (client == _lanClient) {
      _lanStateSub = _lanClient.stateStream.listen(_emitState);
      _lanMessageSub = _lanClient.messageStream.listen(_emitMessage);
      _emitState(_lanClient.state);
    } else {
      _bleStateSub = _bleClient.stateStream.listen(_emitState);
      _bleMessageSub = _bleClient.messageStream.listen(_emitMessage);
      _emitState(_bleClient.state);
    }
  }

  void _emitState(ClientState state) {
    if (!_stateRelay.isClosed) {
      _stateRelay.add(state);
    }
  }

  void _emitMessage(Map<String, dynamic> message) {
    if (!_messageRelay.isClosed) {
      _messageRelay.add(message);
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _lanStateSub?.cancel();
    _bleStateSub?.cancel();
    _lanClient.dispose();
    _bleClient.dispose();
    _stateRelay.close();
    _messageRelay.close();
  }
}
