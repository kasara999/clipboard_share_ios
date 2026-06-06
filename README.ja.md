[English version](README.md)

# ClipSync for iPhone

[ClipSync](https://github.com/kasara999/clipboard_share)（Windows側アプリ）と連携し、iPhoneとWindowsの間でクリップボードをリアルタイムに同期するiPhoneアプリです。

## インストール

[TestFlight](https://testflight.apple.com/join/1mxzWq51) からインストールできます。

## 動作環境

- **iPhone**: iOS 16以降
- **Windowsアプリ**: [clipboard_share](https://github.com/kasara999/clipboard_share)
- **ネットワーク**: WindowsとiPhoneが同じWi-Fiに接続していること

## 使い方

1. WindowsでClipSyncを起動して「QR表示」をクリック
2. iPhoneのClipSyncで「QRコードをスキャンして接続」をタップ
3. 接続完了後、どちらでコピーしてももう一方に自動で同期される

## ファイル構成

```
lib/
├── main.dart                    # アプリの入口
├── screens/
│   ├── scanner_screen.dart      # ペアリング用QRコードスキャナー
│   └── main_screen.dart         # メイン画面・クリップボード履歴
└── services/
    ├── websocket_client.dart    # Windowsとの通信WebSocketクライアント
    └── clipboard_service.dart   # クリップボードの監視と書き込み
```

## 技術仕様

- **通信**: WindowsアプリへのWebSocketクライアント（ポート8765）
- **認証**: QRコードから取得したトークンを接続時に送信
- **データ形式**: JSON（画像はBase64エンコード）
- **クリップボード検知**: 500msポーリング（バックグラウンド時は停止）
