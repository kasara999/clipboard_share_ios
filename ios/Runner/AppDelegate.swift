import Flutter
import Network
import UIKit

/// UIPasteboard.changedNotification を EventChannel 経由で Dart に送る。
final class ClipboardEventsHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observer = NotificationCenter.default.addObserver(
      forName: UIPasteboard.changedNotification,
      object: nil,
      queue: .main
    ) { _ in
      events(nil)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
    return nil
  }
}

private func isLocalNetworkDeniedError(_ error: NWError) -> Bool {
  let description = error.debugDescription.lowercased()
  return description.contains("local network") || description.contains("localnetwork")
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var networkPrepConnection: NWConnection?
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private let clipboardEventsHandler = ClipboardEventsHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let pasteboardChannel = FlutterMethodChannel(name: "clipsync/pasteboard", binaryMessenger: messenger)
    pasteboardChannel.setMethodCallHandler { call, result in
      let pasteboard = UIPasteboard.general
      switch call.method {
      case "hasStrings":
        result(pasteboard.hasStrings)
      case "hasImages":
        result(pasteboard.hasImages)
      case "getText":
        result(pasteboard.string)
      case "getImage":
        if let data = pasteboard.image?.pngData() {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(nil)
        }
      case "setText":
        if let text = call.arguments as? String {
          pasteboard.string = text
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "setText expects String", details: nil))
        }
      case "setImage":
        if let data = call.arguments as? FlutterStandardTypedData,
           let image = UIImage(data: data.data) {
          pasteboard.image = image
          result(nil)
        } else {
          result(FlutterError(code: "bad_args", message: "setImage expects PNG bytes", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let networkChannel = FlutterMethodChannel(name: "clipsync/network", binaryMessenger: messenger)
    networkChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "prepareAccess" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let host = args["host"] as? String,
            let port = args["port"] as? Int,
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
        result(FlutterError(code: "bad_args", message: "prepareAccess expects host and port", details: nil))
        return
      }
      self?.prepareLocalNetwork(host: host, port: nwPort, result: result)
    }

    let backgroundChannel = FlutterMethodChannel(name: "clipsync/background", binaryMessenger: messenger)
    backgroundChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        self?.beginBackgroundKeepAlive()
        result(nil)
      case "stop":
        self?.endBackgroundKeepAlive()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let clipboardEvents = FlutterEventChannel(
      name: "clipsync/clipboard_events",
      binaryMessenger: messenger
    )
    clipboardEvents.setStreamHandler(clipboardEventsHandler)
  }

  private func prepareLocalNetwork(host: String, port: NWEndpoint.Port, result: @escaping FlutterResult) {
    networkPrepConnection?.cancel()
    networkPrepConnection = nil

    let connection = NWConnection(
      host: NWEndpoint.Host(host),
      port: port,
      using: .tcp
    )
    networkPrepConnection = connection

    var finished = false
    var timeout: DispatchWorkItem!
    func finish(_ respond: () -> Any?) {
      guard !finished else { return }
      finished = true
      timeout.cancel()
      connection.cancel()
      if networkPrepConnection === connection {
        networkPrepConnection = nil
      }
      let value = respond()
      if let error = value as? FlutterError {
        result(error)
      } else {
        result(nil)
      }
    }

    timeout = DispatchWorkItem {
      finish {
        FlutterError(
          code: "timeout",
          message: "ネットワークの準備がタイムアウトしました",
          details: nil
        )
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)

    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        finish { nil }
      case .waiting(let error):
        if isLocalNetworkDeniedError(error) {
          finish {
            FlutterError(
              code: "local_network_denied",
              message: "ローカルネットワークへのアクセスが拒否されています",
              details: nil
            )
          }
        }
      case .failed(let error):
        if case NWError.posix(let code) = error, code == POSIXErrorCode.ECONNREFUSED {
          // 到達はできたがサーバー未起動 — 許可ダイアログは通過済みのはず
          finish { nil }
        } else if case NWError.posix(let code) = error, code == POSIXErrorCode.ENETUNREACH {
          finish {
            FlutterError(
              code: "unreachable",
              message: "PCに到達できません",
              details: nil
            )
          }
        } else {
          finish { nil }
        }
      case .cancelled:
        // 新しい接続準備で cancel された場合も Dart 側に必ず応答する
        if !finished {
          finish {
            FlutterError(
              code: "cancelled",
              message: "ネットワークの準備が中断されました",
              details: nil
            )
          }
        }
      default:
        break
      }
    }

    connection.start(queue: .main)
  }

  private func beginBackgroundKeepAlive() {
    if backgroundTaskId != .invalid { return }
    backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
      self?.endBackgroundKeepAlive()
    }
  }

  private func endBackgroundKeepAlive() {
    guard backgroundTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTaskId)
    backgroundTaskId = .invalid
  }
}
