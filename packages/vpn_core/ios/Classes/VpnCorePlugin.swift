import Flutter
import NetworkExtension
import UIKit

/// App-target side of vpn_core on iOS. Talks to `NETunnelProviderManager`
/// (the public NetworkExtension API for driving a packet-tunnel provider
/// extension) -- it does NOT link libbox directly. The actual sing-box core
/// only runs inside the extension process, implemented by
/// PacketTunnelProvider.swift.
public class VpnCorePlugin: NSObject, FlutterPlugin {
    private static let tunnelBundleIdentifierSuffix = ".PacketTunnel"

    private var statusObserver: NSObjectProtocol?
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = VpnCorePlugin()
        let methodChannel = FlutterMethodChannel(
            name: "vpn_core/methods", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "vpn_core/status", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(VpnCoreStreamHandler(plugin: instance))
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            loadOrCreateManager { managerResult in
                switch managerResult {
                case .success: result(nil)
                case .failure(let error):
                    result(FlutterError(code: "initialize_failed", message: error.localizedDescription, details: nil))
                }
            }

        case "start":
            guard let args = call.arguments as? [String: Any],
                  let tag = args["tag"] as? String,
                  let configJson = args["configJson"] as? String
            else {
                return result(FlutterError(code: "bad_args", message: "tag and configJson are required", details: nil))
            }
            start(tag: tag, configJson: configJson, result: result)

        case "stop":
            loadOrCreateManager { managerResult in
                switch managerResult {
                case .success(let manager):
                    manager.connection.stopVPNTunnel()
                    result(nil)
                case .failure(let error):
                    result(FlutterError(code: "stop_failed", message: error.localizedDescription, details: nil))
                }
            }

        case "restart":
            // NETunnelProviderManager has no atomic "replace config" call;
            // stop, then start with the new provider configuration.
            //
            // stopVPNTunnel() has no completion handler -- calling
            // startVPNTunnel() again immediately (the old behavior here)
            // raced the extension's own teardown: NEPacketTunnelProvider's
            // stopTunnel()->startTunnel() on the same extension instance is
            // not guaranteed atomic, so a fast restart could hit
            // NEVPNErrorConfigurationDisabled or start against a tunnel
            // that hasn't actually torn down yet. Wait for a real
            // .disconnected status (or a bounded timeout, so a stuck
            // extension can't hang the user's reconnect forever) before
            // starting again -- the same "don't start until the previous
            // instance is confirmed gone" guarantee SingBoxVpnService
            // already gives on Android.
            guard let args = call.arguments as? [String: Any],
                  let tag = args["tag"] as? String,
                  let configJson = args["configJson"] as? String
            else {
                return result(FlutterError(code: "bad_args", message: "tag and configJson are required", details: nil))
            }
            loadOrCreateManager { managerResult in
                switch managerResult {
                case .failure(let error):
                    return result(FlutterError(code: "restart_failed", message: error.localizedDescription, details: nil))
                case .success(let manager):
                    let connection = manager.connection
                    if connection.status == .disconnected || connection.status == .invalid {
                        self.start(tag: tag, configJson: configJson, result: result)
                        return
                    }
                    self.waitForDisconnect(of: connection) {
                        self.start(tag: tag, configJson: configJson, result: result)
                    }
                    connection.stopVPNTunnel()
                }
            }

        case "status":
            loadOrCreateManager { managerResult in
                switch managerResult {
                case .success(let manager):
                    result(VpnCorePlugin.statusWire(for: manager.connection.status, tag: manager.localizedDescription))
                case .failure:
                    result(VpnCorePlugin.statusWire(for: .disconnected, tag: nil))
                }
            }

        case "coreVersion":
            // The app-side extension host cannot call into libbox directly
            // (it only runs inside the extension process); this is
            // reported by the extension over the same IPC channel sing-box
            // uses for its command protocol. Not yet wired -- see
            // docs/ARCHITECTURE.md "Remaining incompatibilities".
            result("unavailable (query not yet wired through the extension)")

        case "getSanitizedLogs":
            result([String]())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func start(tag: String, configJson: String, result: @escaping FlutterResult) {
        loadOrCreateManager { managerResult in
            switch managerResult {
            case .failure(let error):
                return result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
            case .success(let manager):
                manager.localizedDescription = tag
                manager.isEnabled = true
                manager.saveToPreferences { saveError in
                    if let saveError = saveError {
                        return result(FlutterError(code: "save_failed", message: saveError.localizedDescription, details: nil))
                    }
                    do {
                        // configJson never crosses as a launch argument or
                        // gets logged: NETunnelProviderManager's
                        // `options` dictionary is the documented, private
                        // channel Apple provides for exactly this.
                        try manager.connection.startVPNTunnel(options: [
                            "configJson": configJson as NSObject
                        ])
                        result(nil)
                    } catch {
                        result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    /// Resolves once `connection.status` actually reaches `.disconnected`,
    /// or after `timeout` seconds if it never does (a stuck extension must
    /// not hang the caller forever -- the subsequent `startVPNTunnel` is
    /// still safe to attempt either way, since NetworkExtension itself
    /// will surface a real error if the previous instance genuinely never
    /// tore down).
    private func waitForDisconnect(
        of connection: NEVPNConnection, timeout: TimeInterval = 5, completion: @escaping () -> Void
    ) {
        var observer: NSObjectProtocol?
        var didComplete = false
        let finish = {
            if didComplete { return }
            didComplete = true
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
            completion()
        }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { _ in
            if connection.status == .disconnected {
                finish()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
    }

    private func loadOrCreateManager(_ completion: @escaping (Result<NETunnelProviderManager, Error>) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                return completion(.failure(error))
            }
            if let existing = managers?.first {
                return completion(.success(existing))
            }
            let manager = NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            // Must match the Network Extension target's bundle identifier,
            // configured as <app bundle id> + tunnelBundleIdentifierSuffix
            // in the Xcode project -- see docs/BUILDING.md "iOS".
            proto.providerBundleIdentifier =
                (Bundle.main.bundleIdentifier ?? "") + VpnCorePlugin.tunnelBundleIdentifierSuffix
            proto.serverAddress = "vpn_core"
            manager.protocolConfiguration = proto
            completion(.success(manager))
        }
    }

    fileprivate static func statusWire(for status: NEVPNStatus, tag: String?) -> [String: Any?] {
        let state: String
        switch status {
        case .connecting: state = "connecting"
        case .connected: state = "connected"
        case .reasserting: state = "reasserting"
        case .disconnecting: state = "disconnecting"
        case .disconnected: state = "disconnected"
        case .invalid: state = "invalid"
        @unknown default: state = "invalid"
        }
        return ["state": state, "activeTag": tag, "uplinkBytes": 0, "downlinkBytes": 0]
    }

    fileprivate func observeStatus(_ sink: @escaping FlutterEventSink) {
        eventSink = sink
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            self?.eventSink?(VpnCorePlugin.statusWire(for: connection.status, tag: nil))
        }
    }

    fileprivate func stopObservingStatus() {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObserver = nil
        eventSink = nil
    }
}

private class VpnCoreStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: VpnCorePlugin?
    init(plugin: VpnCorePlugin) { self.plugin = plugin }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.observeStatus(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.stopObservingStatus()
        return nil
    }
}
