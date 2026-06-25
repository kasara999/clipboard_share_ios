import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ConnectionInfo {
  final String ip;
  final int port;
  final String token;
  const ConnectionInfo({required this.ip, required this.port, required this.token});
}

ConnectionInfo? parseQrData(String raw) {
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme != 'clipsync') return null;
    final ip = uri.host;
    final port = uri.port > 0 ? uri.port : 8765;
    final token = uri.queryParameters['token'];
    if (ip.isEmpty || token == null || token.isEmpty) return null;
    if (!_isValidLanIp(ip)) return null;
    return ConnectionInfo(ip: ip, port: port, token: token);
  } catch (_) {
    return null;
  }
}

bool _isValidLanIp(String ip) {
  if (ip == '0.0.0.0' || ip == '127.0.0.1') return false;
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

/// QRコードスキャン画面。手動入力タブも備える。
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _scanned = false;
  final _controller = MobileScannerController();

  // 手動入力フォーム
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8765');
  final _tokenCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('接続'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QRスキャン'),
            Tab(icon: Icon(Icons.keyboard), text: '手動入力'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildScanTab(),
          _buildManualTab(),
        ],
      ),
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
            const Text('PCアプリのQR画面に表示された情報を入力してください。',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
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
