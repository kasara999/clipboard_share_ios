[日本語版はこちら](README.ja.md)

# ClipSync for iPhone

The iPhone companion app for [ClipSync](https://github.com/kasara999/clipboard_share) — real-time clipboard sync between iPhone and Windows over the local network.

## Installation

Install via [TestFlight](https://testflight.apple.com/join/1mxzWq51). No App Store required.

## Requirements

- **iPhone**: iOS 16 or later
- **Windows app**: [clipboard_share](https://github.com/kasara999/clipboard_share)
- **Network**: Both devices must be on the same Wi-Fi network

## How to Use

1. Launch ClipSync on Windows and click **Show QR**
2. Open ClipSync on iPhone and tap **Scan QR Code**
3. Once connected, anything copied on either device is automatically synced to the other

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── screens/
│   ├── scanner_screen.dart      # QR code scanner for pairing
│   └── main_screen.dart         # Main screen and clipboard history
└── services/
    ├── websocket_client.dart    # WebSocket client for Windows communication
    └── clipboard_service.dart   # Clipboard monitoring and writing
```

## Technical Details

- **Transport**: WebSocket client connecting to the Windows app (port 8765)
- **Authentication**: Token extracted from QR code, sent on connect
- **Data format**: JSON; images are Base64-encoded
- **Clipboard detection**: 500 ms polling (paused when app is backgrounded)
