import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ClientState { disconnected, connecting, authenticating, connected, error }

class WebSocketClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _stateController = StreamController<ClientState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<ClientState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  ClientState _state = ClientState.disconnected;
  ClientState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  Future<void> connect(String ip, int port, String token) async {
    _setState(ClientState.connecting);
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://$ip:$port'),
        connectTimeout: const Duration(seconds: 5),
      );

      _setState(ClientState.authenticating);

      // Send auth immediately
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));

      _sub = _channel!.stream.listen(
        (data) => _onData(data as String),
        onDone: () {
          _setState(ClientState.disconnected);
        },
        onError: (e) {
          _lastError = e.toString();
          _setState(ClientState.error);
        },
        cancelOnError: false,
      );
    } catch (e) {
      _lastError = e.toString();
      _setState(ClientState.error);
    }
  }

  void _onData(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      if (type == 'auth_ok') {
        _setState(ClientState.connected);
        return;
      }
      if (type == 'auth_error') {
        _lastError = 'トークンが一致しません';
        _setState(ClientState.error);
        disconnect();
        return;
      }

      if (_state == ClientState.connected) {
        _messageController.add(msg);
      }
    } catch (_) {}
  }

  void send(Map<String, dynamic> message) {
    if (_state == ClientState.connected) {
      _channel?.sink.add(jsonEncode(message));
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(ClientState.disconnected);
  }

  void _setState(ClientState s) {
    _state = s;
    _stateController.add(s);
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
  }
}
