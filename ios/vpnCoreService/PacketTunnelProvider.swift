import Foundation
import NetworkExtension
// Libbox is the gomobile-generated framework built from the pinned
// sing-box `experimental/libbox` package (see
// packages/vpn_core/native/singbox-go/build_ios.sh for the exact pinned
// commit and packages/vpn_core/ios/Frameworks/ for the build output this
// target links). This file is a hard compile-time dependency on that
// framework: it does not build until Libbox.xcframework has been
// produced -- see docs/BUILDING.md "iOS".
import Libbox

/// Real `NEPacketTunnelProvider` implementation for the pinned sing-box
/// v1.13.19 core, replacing both Karing's opaque
/// `class PacketTunnelProvider: ExtensionProvider {}` (which inherited
/// 100% of its behavior from the never-checked-in `LibVpnCore` framework)
/// and this file's own earlier `LibboxNewBoxService`-based stub, which
/// called a Go constructor (`LibboxNewBoxService`) that does not exist in
/// the pinned v1.13.19 source.
///
/// Architecture verified against SagerNet/sing-box-for-apple at its
/// `main` branch (`MARKETING_VERSION = 1.13.19`, the same pin this app
/// tracks -- confirmed by cloning that branch directly and cross-checking
/// every libbox call below, plus the Go interface declarations in
/// `experimental/libbox/{command_server,setup,tun,platform}.go` at the
/// resolved `github.com/sagernet/sing-box@v1.13.19` module, both read in
/// full rather than guessed). Deliberately simplified relative to that
/// reference: no macOS/tvOS/system-extension branches, no
/// `ExtensionStartOptions` persistence layer (this app's
/// `VpnCorePlugin.swift` always passes `configJson` explicitly on every
/// `startVPNTunnel(options:)` call -- there is no persisted-profile store
/// to fall back to, unlike SFI's multi-profile app), no WidgetKit/
/// ControlCenter integration (this app has no widget).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private(set) var commandServer: LibboxCommandServer?
    private lazy var platformInterface = ExtensionPlatformInterface(self)
    private var currentConfigJson: String?

    /// Shared container both the host app and this extension can read/
    /// write. Matches the `group.com.david610.singboxclient` app-group entitlement
    /// already present on both `Runner/Runner.entitlements` and
    /// `PacketTunnel.entitlements` -- required because an app extension's
    /// own container is sandboxed separately from the host app's.
    private static let appGroupID = "group.com.david610.singboxclient"

    private func requireGroupContainer() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            throw ExtensionStartupError("(packet-tunnel) error: no container for app group \(Self.appGroupID) -- check the com.apple.security.application-groups entitlement on both targets")
        }
        return url
    }

    override func startTunnel(options startOptions: [String: NSObject]?) async throws {
        guard let configJson = startOptions?["configJson"] as? String, !configJson.isEmpty else {
            // No persisted-profile fallback by design: VpnCorePlugin.swift
            // always supplies configJson explicitly. A start with no
            // config is a caller bug, not something to paper over with an
            // implicit "last known config" guess.
            throw ExtensionStartupError("(packet-tunnel) error: missing configJson in tunnel start options")
        }
        currentConfigJson = configJson

        let containerURL = try requireGroupContainer()
        let basePath = containerURL.path
        let workingPath = containerURL.appendingPathComponent("Working", isDirectory: true).path
        let tempPath = containerURL.appendingPathComponent("Temp", isDirectory: true).path

        let setupOptions = LibboxSetupOptions()
        setupOptions.basePath = basePath
        setupOptions.workingPath = workingPath
        setupOptions.tempPath = tempPath
        setupOptions.logMaxLines = 3000

        var setupError: NSError?
        LibboxSetup(setupOptions, &setupError)
        if let setupError {
            throw ExtensionStartupError("(packet-tunnel) error: setup: \(setupError.localizedDescription)")
        }

        let stderrPath = URL(fileURLWithPath: tempPath, isDirectory: true).appendingPathComponent("stderr.log").path
        var stderrError: NSError?
        LibboxRedirectStderr(stderrPath, &stderrError)
        if let stderrError {
            throw ExtensionStartupError("(packet-tunnel) error: redirect stderr: \(stderrError.localizedDescription)")
        }

        // NEPacketTunnelProvider extensions run under a strict jetsam
        // memory limit (historically ~50MB on iOS); always enable libbox's
        // own memory-limit enforcement rather than exposing a toggle this
        // app's UI has no use for.
        LibboxSetMemoryLimit(true)

        var newServerError: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &newServerError)
        if let newServerError {
            throw ExtensionStartupError("(packet-tunnel) error: create command server: \(newServerError.localizedDescription)")
        }
        do {
            try commandServer!.start()
        } catch {
            throw ExtensionStartupError("(packet-tunnel) error: start command server: \(error.localizedDescription)")
        }

        writeMessage("(packet-tunnel): Here I stand")

        // startService() drives platformInterface.openTun(), which calls
        // setTunnelNetworkSettings(_:) and only returns once the OS has
        // actually established the tunnel interface -- so by the time this
        // function returns without throwing, the tunnel is genuinely
        // usable, not just "core object created".
        try await startService(configJson)
    }

    private func startService(_ configJson: String) async throws {
        let options = LibboxOverrideOptions()
        do {
            try commandServer!.startOrReloadService(configJson, options: options)
        } catch {
            throw ExtensionStartupError("(packet-tunnel) error: start service: \(error.localizedDescription)")
        }
    }

    func stopService() {
        do {
            try commandServer?.closeService()
        } catch {
            writeMessage("(packet-tunnel) error: stop service: \(error.localizedDescription)")
        }
        platformInterface.reset()
    }

    func reloadService() async throws {
        guard let configJson = currentConfigJson else {
            throw ExtensionStartupError("(packet-tunnel) error: reload requested before first start")
        }
        writeMessage("(packet-tunnel) reloading service")
        reasserting = true
        defer { reasserting = false }
        try await startService(configJson)
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        writeMessage("(packet-tunnel) stopping, reason: \(reason)")
        stopService()
        if let server = commandServer {
            // Matches upstream: give in-flight log/status writes a moment
            // to flush over the command-server pipe before tearing it down.
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            server.close()
            commandServer = nil
        }
        currentConfigJson = nil
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        // VpnCorePlugin.swift does not currently call
        // sendProviderMessage(_:) (its "restart" verb goes through
        // stopVPNTunnel + startVPNTunnel(options:) instead), so this path
        // is unused by the app today. Implemented for completeness and
        // future use: a UTF-8 message body is treated as a replacement
        // configJson and triggers a reload, matching the shape of
        // startTunnel's own options.
        guard let newConfigJson = String(data: messageData, encoding: .utf8), !newConfigJson.isEmpty else {
            return "missing configJson".data(using: .utf8)
        }
        currentConfigJson = newConfigJson
        do {
            try await reloadService()
            return nil
        } catch {
            return error.localizedDescription.data(using: .utf8)
        }
    }

    override func sleep() async {
        commandServer?.pause()
    }

    override func wake() {
        commandServer?.wake()
    }

    func writeMessage(_ message: String) {
        commandServer?.writeMessage(2, message: message)
    }
}

/// Thrown for any condition that must prevent `startTunnel` from
/// completing successfully -- NEPacketTunnelProvider treats a thrown
/// error from `startTunnel(options:)` as a failed connection attempt, so
/// this is the mechanism (not a completion handler flag) that guarantees
/// start failure can never surface as `.connected`.
struct ExtensionStartupError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
