import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/ble_connection_result.dart';
import '../models/connection_info.dart';
import '../services/ble_client_service.dart';

export '../models/ble_connection_result.dart';
export '../models/connection_info.dart';

/// QR / 手動入力 / Bluetooth スキャン画面。
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _ble = BleClientService();

  bool _scanned = false;
  final _controller = MobileScannerController();
  StreamSubscription<List<DiscoveredPc>>? _bleSub;
  List<DiscoveredPc> _bleDevices = [];
  bool _bleScanning = false;
  String? _bleError;
  String? _connectingId;

  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8765');
  final _tokenCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _bleSub = _ble.discoveriesStream.listen((devices) {
      if (!mounted) return;
      setState(() => _bleDevices = devices);
    });
    _startBleScan();
  }

  void _onTabChanged() {
    if (_tabController.index == 0 && !_bleScanning) {
      unawaited(_startBleScan());
    } else if (_tabController.index != 0 && _bleScanning) {
      unawaited(_ble.stopDiscovery());
      setState(() => _bleScanning = false);
    }
  }

  Future<void> _startBleScan() async {
    setState(() {
      _bleError = null;
      _bleScanning = true;
    });
    try {
      await _ble.startDiscovery();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bleError = 'Bluetooth を開始できません: $e';
        _bleScanning = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _controller.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    _bleSub?.cancel();
    _ble.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final info = parseQrData(raw);
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QRコードの形式が正しくないか、IPアドレスが無効です'),
          backgroundColor: Colors.red,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () => _scanned = false);
      return;
    }
    _scanned = true;
    Navigator.of(context).pop(info);
  }

  void _connectManually() {
    if (!_formKey.currentState!.validate()) return;
    final info = ConnectionInfo(
      ip: _ipCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 8765,
      token: _tokenCtrl.text.trim(),
    );
    Navigator.of(context).pop(info);
  }

  Future<void> _connectBle(DiscoveredPc pc) async {
    final id = pc.peripheral.uuid.toString();
    setState(() {
      _connectingId = id;
      _bleError = null;
    });
    try {
      final token = await _ble.readDeviceToken(pc.peripheral);
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        setState(() => _bleError = 'PC からトークンを取得できませんでした');
        return;
      }
      await _ble.stopDiscovery();
      if (!mounted) return;
      Navigator.of(context).pop(
        BleConnectionResult(
          peripheral: pc.peripheral,
          token: token,
          displayName: pc.displayName,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _bleError = '接続準備に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('接続'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'Bluetooth'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QRスキャン'),
            Tab(icon: Icon(Icons.keyboard), text: '手動入力'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBluetoothTab(),
          _buildScanTab(),
          _buildManualTab(),
        ],
      ),
    );
  }

  Widget _buildBluetoothTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'PC の ClipSync を起動し、Bluetooth 待ち受け中にしてください。\n'
            '同じマンション Wi-Fi でも Bluetooth なら接続できます。',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ),
        if (_bleError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_bleError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (_bleScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.bluetooth_searching, size: 18),
              const SizedBox(width: 8),
              Text(_bleScanning ? 'PC を検索中...' : 'スキャン停止中'),
              const Spacer(),
              TextButton.icon(
                onPressed: _bleScanning ? null : _startBleScan,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('再スキャン'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _bleDevices.isEmpty
              ? const Center(
                  child: Text('ClipSync が見つかりません', style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  itemCount: _bleDevices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final pc = _bleDevices[i];
                    final id = pc.peripheral.uuid.toString();
                    final connecting = _connectingId == id;
                    return ListTile(
                      leading: const Icon(Icons.computer),
                      title: Text(pc.displayName),
                      subtitle: Text('信号強度: ${pc.rssi} dBm'),
                      trailing: connecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: connecting ? null : () => _connectBle(pc),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildScanTab() {
    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ),
        const Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Text(
            'PCアプリのQRコードを枠内に合わせてください',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 13, shadows: [
              Shadow(blurRadius: 4, color: Colors.black),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildManualTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'PCアプリのQR画面に表示された情報を入力してください。',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _ipCtrl,
              decoration: const InputDecoration(
                labelText: 'IPアドレス',
                hintText: '192.168.1.10',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
              keyboardType: TextInputType.number,
              validator: (v) => (v == null || v.trim().isEmpty) ? '必須項目です' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: 'ポート番号',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '必須項目です';
                if (int.tryParse(v.trim()) == null) return '数値を入力してください';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'トークン',
                hintText: 'QR画面下部のトークン文字列',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? '必須項目です' : null,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('接続'),
              onPressed: _connectManually,
            ),
          ],
        ),
      ),
    );
  }
}
