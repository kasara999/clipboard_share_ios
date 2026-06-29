import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'local_network_service.dart';

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

  String? _serverPlatform;
  String? get serverPlatform => _serverPlatform;

  final _localNetwork = LocalNetworkService();

  Future<void> connect(String ip, int port, String token) async {
    await disconnect();

    if (!_isValidLanIp(ip)) {
      _lastError = 'QRコードのIPアドレスが無効です（$ip）。\n'
          'PCアプリで正しいIPが表示されているか確認してください。';
      _setState(ClientState.error);
      return;
    }

    _setState(ClientState.connecting);
    Completer<void>? authCompleter;

    try {
      await _localNetwork
          .prepareAccess(host: ip, port: port)
          .timeout(const Duration(seconds: 12));

      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://$ip:$port'),
        connectTimeout: const Duration(seconds: 10),
        pingInterval: const Duration(seconds: 25),
      );
      await _channel!.ready.timeout(const Duration(seconds: 10));

      authCompleter = Completer<void>();
      _sub = _channel!.stream.listen(
        (data) => _onData(data as String, authCompleter: authCompleter),
        onDone: () {
          if (_state != ClientState.error) {
            _setState(ClientState.disconnected);
          }
        },
        onError: (_) {
          _lastError = '接続が切断されました';
          _setState(ClientState.error);
        },
        cancelOnError: false,
      );

      _setState(ClientState.authenticating);
      _channel!.sink.add(jsonEncode({
        'type': 'auth',
        'token': token,
        'platform': Platform.operatingSystem,
      }));

      await authCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('認証がタイムアウトしました'),
      );
      if (_state != ClientState.connected) {
        throw TimeoutException('認証がタイムアウトしました');
      }
    } on PlatformException catch (e) {
      _lastError = LocalNetworkService.messageFor(e);
      _setState(ClientState.error);
      await disconnect();
    } on TimeoutException catch (e) {
      _lastError = e.message ?? '接続がタイムアウトしました';
      _setState(ClientState.error);
      await disconnect();
    } catch (e) {
      _lastError = _connectionErrorMessage(e, ip, port);
      _setState(ClientState.error);
      await disconnect();
    }
  }

  void _onData(String raw, {Completer<void>? authCompleter}) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      if (type == 'auth_ok') {
        _serverPlatform = msg['platform'] as String?;
        _setState(ClientState.connected);
        if (authCompleter != null && !authCompleter.isCompleted) {
          authCompleter.complete();
        }
        return;
      }
      if (type == 'auth_error') {
        _lastError = 'トークンが一致しません';
        _setState(ClientState.error);
        if (authCompleter != null && !authCompleter.isCompleted) {
          authCompleter.complete();
        }
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
    _sub = null;
    _serverPlatform = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
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

  bool _isValidLanIp(String ip) {
    if (ip.isEmpty || ip == '0.0.0.0') return false;
    if (ip == '127.0.0.1') return true;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return false;
    final a = nums[0]!;
    final b = nums[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  String _connectionErrorMessage(Object e, String ip, int port) {
    final msg = e.toString();
    if (msg.contains('Connection refused') || msg.contains('ECONNREFUSED')) {
      return 'PCのClipSyncに接続できません（$ip:$port）。\n'
          'PCアプリが起動しているか、ファイアウォールで許可されているか確認してください。';
    }
    if (msg.contains('No route to host') ||
        msg.contains('EHOSTUNREACH') ||
        msg.contains('Network is unreachable') ||
        msg.contains('ENETUNREACH')) {
      return 'PCに到達できません（$ip:$port）。\n'
          '・スマホとPCが同じWi-Fiか（モバイルデータOFF）\n'
          '・PCアプリに表示されたIPが ipconfig と一致するか\n'
          '・Windowsファイアウォールで ClipSync を許可しているか\n'
          '・ゲストWi-FiやVPNを使っていないか';
    }
    if (msg.contains('Future not completed') ||
        msg.contains('future not complete')) {
      return '接続処理が完了しませんでした。\n'
          'もう一度 QR を読み直すか、アプリを再起動してください。';
    }
    return '接続に失敗しました: $msg';
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!_stateController.isClosed) _stateController.close();
    if (!_messageController.isClosed) _messageController.close();
  }
}
