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
