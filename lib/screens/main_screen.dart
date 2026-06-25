import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../constants/platform_labels.dart';
import '../services/clipboard_service.dart';
import '../services/websocket_client.dart';
import 'scanner_screen.dart';

enum _Source { local, remote }

class _HistoryEntry {
  final ClipboardItem item;
  final _Source source;
  final String? remoteLabel;
  _HistoryEntry(this.item, this.source, {this.remoteLabel});
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final _client = WebSocketClient();
  final _clipService = ClipboardService();

  ConnectionInfo? _connInfo;
  ClientState _connState = ClientState.disconnected;
  String? _connError;

  final List<_HistoryEntry> _history = [];
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupStreams();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _clipService.startPolling();
    } else {
      _clipService.stopPolling();
    }
  }

  void _setupStreams() {
    _subs.add(_client.stateStream.listen((s) {
      setState(() {
        _connState = s;
        if (s == ClientState.error) {
          _connError = _client.lastError;
        } else {
          _connError = null;
        }
      });

      // 接続確立時にクリップボード監視を開始
      if (s == ClientState.connected) {
        _clipService.startPolling();
      } else if (s == ClientState.disconnected || s == ClientState.error) {
        _clipService.stopPolling();
      }
    }));

    _subs.add(_client.messageStream.listen((msg) async {
      _addRemoteToHistory(msg);
    }));

    _subs.add(_clipService.itemStream.listen((item) {
      _onLocalClipboard(item);
    }));
  }

  String _remotePlatformLabel([Map<String, dynamic>? message]) {
    final platform = message?['origin'] as String? ?? _client.serverPlatform;
    return PlatformLabels.desktop(platform);
  }

  String get _localMobileLabel => PlatformLabels.localMobile();

  bool _sameClipboardContent(ClipboardItem a, ClipboardItem b) {
    if (a.type != b.type) return false;
    if (a.type == ClipboardItemType.text) {
      return a.text == b.text;
    }
    final aBytes = a.imageBytes;
    final bBytes = b.imageBytes;
    if (aBytes == null || bBytes == null) return false;
    if (aBytes.length != bBytes.length) return false;
    final n = aBytes.length.clamp(0, 64);
    for (var i = 0; i < n; i++) {
      if (aBytes[i] != bBytes[i]) return false;
    }
    return true;
  }

  void _onLocalClipboard(ClipboardItem item) {
    if (_history.isNotEmpty &&
        _history.first.source == _Source.remote &&
        _sameClipboardContent(_history.first.item, item)) {
      return;
    }
    _addEntry(_HistoryEntry(item, _Source.local));
    _sendToServer(item);
  }

  void _sendToServer(ClipboardItem item) {
    final origin = Platform.operatingSystem;
    if (item.type == ClipboardItemType.text && item.text != null) {
      _client.send({
        'type': 'clipboard',
        'content_type': 'text',
        'content': item.text,
        'origin': origin,
      });
    } else if (item.type == ClipboardItemType.image && item.imageBytes != null) {
      _client.send({
        'type': 'clipboard',
        'content_type': 'image',
        'content': base64Encode(item.imageBytes!),
        'origin': origin,
      });
    }
  }

  void _addRemoteToHistory(Map<String, dynamic> msg) {
    final type = msg['content_type'] as String?;
    ClipboardItem? item;
    if (type == 'text') {
      item = ClipboardItem.text(msg['content'] as String?);
    } else if (type == 'image') {
      item = ClipboardItem.image(base64Decode(msg['content'] as String));
    }
    if (item == null) return;
    final remoteItem = item;

    _clipService.noteRemoteContent(remoteItem);
    final label = _remotePlatformLabel(msg);

    if (_history.isNotEmpty &&
        _history.first.source == _Source.local &&
        _sameClipboardContent(_history.first.item, remoteItem)) {
      setState(() => _history[0] = _HistoryEntry(remoteItem, _Source.remote, remoteLabel: label));
      return;
    }
    _addEntry(_HistoryEntry(remoteItem, _Source.remote, remoteLabel: label));
  }

  void _addEntry(_HistoryEntry e) {
    setState(() {
      _history.insert(0, e);
      if (_history.length > 50) _history.removeLast();
    });
  }

  Future<void> _startScan() async {
    final info = await Navigator.of(context).push<ConnectionInfo>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (info == null) return;
    setState(() => _connInfo = info);
    await _client.connect(info.ip, info.port, info.token);
  }

  Future<void> _disconnect() async {
    await _client.disconnect();
    setState(() => _connInfo = null);
  }

  Future<void> _copyItem(ClipboardItem item) async {
    if (item.type == ClipboardItemType.text && item.text != null) {
      await _clipService.applyRemote({
        'content_type': 'text',
        'content': item.text,
      });
    } else if (item.type == ClipboardItemType.image && item.imageBytes != null) {
      await _clipService.applyRemote({
        'content_type': 'image',
        'content': base64Encode(item.imageBytes!),
      });
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クリップボードにコピーしました'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _client.dispose();
    _clipService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClipSync'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '履歴をクリア',
              onPressed: () => setState(() => _history.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildConnectionCard(),
          const Divider(height: 1),
          Expanded(child: _buildHistory()),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    final isConnected = _connState == ClientState.connected;
    final isLoading = _connState == ClientState.connecting ||
        _connState == ClientState.authenticating;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (_connState) {
      case ClientState.connected:
        statusColor = Colors.green;
        statusIcon = Icons.wifi;
        statusText = '接続中: ${_connInfo?.ip}:${_connInfo?.port}';
      case ClientState.connecting:
        statusColor = Colors.orange;
        statusIcon = Icons.wifi_find;
        statusText = '接続中...';
      case ClientState.authenticating:
        statusColor = Colors.orange;
        statusIcon = Icons.lock_open;
        statusText = '認証中...';
      case ClientState.error:
        statusColor = Colors.red;
        statusIcon = Icons.wifi_off;
        statusText = _connError ?? '接続エラー';
      case ClientState.disconnected:
        statusColor = Colors.grey;
        statusIcon = Icons.wifi_off;
        statusText = '未接続';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w500),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isLoading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),
          if (!isConnected && !isLoading)
            FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QRコードをスキャンして接続'),
              onPressed: _startScan,
            )
          else if (isConnected)
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('切断'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _disconnect,
            ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_paste_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('クリップボード履歴なし', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '履歴 (${_history.length}件)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _buildItem(_history[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(_HistoryEntry entry) {
    final item = entry.item;
    final isRemote = entry.source == _Source.remote;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isRemote ? Colors.blue[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isRemote ? (entry.remoteLabel ?? _remotePlatformLabel()) : _localMobileLabel,
        style: TextStyle(
          fontSize: 10,
          color: isRemote ? Colors.blue[700] : Colors.green[700],
        ),
      ),
    );

    final subtitle = Row(
      children: [
        badge,
        const SizedBox(width: 6),
        Text(_fmt(item.timestamp), style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );

    if (item.type == ClipboardItemType.text) {
      return ListTile(
        leading: const Icon(Icons.text_fields, size: 20),
        title: Text(item.text ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle,
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () => _copyItem(item),
        ),
        onTap: () => _copyItem(item),
      );
    } else {
      return ListTile(
        leading: const Icon(Icons.image, size: 20),
        title: item.imageBytes != null
            ? Image.memory(item.imageBytes!, height: 60, fit: BoxFit.contain, alignment: Alignment.centerLeft)
            : const Text('画像'),
        subtitle: subtitle,
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () => _copyItem(item),
        ),
        onTap: () => _copyItem(item),
      );
    }
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
}
