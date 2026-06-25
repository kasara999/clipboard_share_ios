import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipboard_share_ios/services/websocket_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _testPort = 28765;

/// テスト用の最小WebSocketサーバー（認証のみ）
Future<HttpServer> startTestServer({required String validToken}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _testPort);
  server.listen((request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      if (msg['type'] == 'auth' && msg['token'] == validToken) {
        socket.add(jsonEncode({'type': 'auth_ok'}));
      } else {
        socket.add(jsonEncode({'type': 'auth_error'}));
        socket.close();
      }
    });
  });
  return server;
}

void mockLocalNetworkChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('clipsync/network'), (call) async {
    if (call.method == 'prepareAccess') return null;
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;

  setUp(() async {
    mockLocalNetworkChannel();
    server = await startTestServer(validToken: 'test-token');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('clipsync/network'), null);
    await server.close(force: true);
  });

  test('正しいトークンで接続できる', () async {
    final client = WebSocketClient();
    final states = <ClientState>[];
    final sub = client.stateStream.listen(states.add);

    await client.connect('127.0.0.1', _testPort, 'test-token');

    expect(states, contains(ClientState.connected));
    expect(client.state, ClientState.connected);

    await client.disconnect();
    await sub.cancel();
    client.dispose();
  });

  test('無効IPは接続しない', () async {
    final client = WebSocketClient();
    await client.connect('8.8.8.8', _testPort, 'test-token');

    expect(client.state, ClientState.error);
    expect(client.lastError, isNotNull);
    client.dispose();
  });
}
