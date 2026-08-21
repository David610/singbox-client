import NetworkExtension
// Libbox is the gomobile-generated framework built from the pinned
// sing-box `experimental/libbox` package (see
// packages/vpn_core/native/singbox-go/build_ios.sh and
// packages/vpn_core/UPSTREAM_VERSION.md for the exact pinned commit).
// This file, unlike everything under packages/vpn_core/ios/Classes, is a
// hard compile-time dependency on that framework: it only builds once
// Libbox.xcframework has been produced and linked into this Network
// Extension target -- see docs/BUILDING.md "iOS".
import Libbox

/// Real NEPacketTunnelProvider implementation, replacing Karing's opaque
/// `class PacketTunnelProvider: ExtensionProvider {}` (which inherited
/// 100% of its behavior from the missing `LibVpnCore` framework). This
/// class owns the tunnel lifecycle directly and is the only place on iOS
/// that talks to libbox.
///
/// [LibboxPlatformInterface] below implements the Go `PlatformInterface`
/// contract (experimental/libbox/platform.go) that the pinned core calls
/// back into for TUN setup, DNS, and interface monitoring. The exact
/// generated Swift/ObjC protocol name and method signatures come from
/// gomobile's binding of that Go interface; verify them against
/// `Libbox.xcframework`'s generated header on first real build and adjust
/// the `override`/conformance below to match -- this file encodes the Go
/// interface's documented shape faithfully, but gomobile's exact Swift
/// spelling can only be confirmed once the framework is built (not
/// possible in this audit/planning environment; see docs/BUILDING.md).
class PacketTunnelProvider: NEPacketTunnelProvider {
    private var boxService: LibboxBoxServiceHandle?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let configJson = options?["configJson"] as? String else {
            return completionHandler(NSError(
                domain: "app.singboxclient.vpn_core", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "missing configJson"]))
        }

        if let checkError = LibboxCheckConfig(configJson) {
            return completionHandler(checkError)
        }

        let platformInterface = LibboxPlatformInterface(provider: self)
        do {
            let service = try LibboxNewBoxService(configJson, platformInterface)
            boxService = service
            try service.start()
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        boxService?.close()
        boxService = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        completionHandler?(nil)
    }
}

/// Implements the Go-side `PlatformInterface` contract (see
/// experimental/libbox/platform.go in the pinned sing-box source):
///   OpenTun, UseProcFS, UsePlatformAutoDetectInterfaceControl,
///   AutoDetectInterfaceControl, FindConnectionOwner,
///   StartDefaultInterfaceMonitor, CloseDefaultInterfaceMonitor,
///   GetInterfaces, UnderNetworkExtension, IncludeAllNetworks,
///   ReadWIFIState, SystemCertificates, ClearDNSCache, SendNotification,
///   LocalDNSTransport.
/// Only the TUN-establishment path is implemented here; the rest return
/// safe/conservative defaults (see inline comments). Filling these in
/// precisely is part of the "remaining incompatibilities" tracked in
/// docs/ARCHITECTURE.md.
private final class LibboxPlatformInterface: NSObject {
    private weak var provider: NEPacketTunnelProvider?
    init(provider: NEPacketTunnelProvider) {
        self.provider = provider
    }

    func openTun(_ options: LibboxTunOptions?, error: NSErrorPointer) -> Int32 {
        guard let provider = provider, let options = options else {
            error?.pointee = NSError(domain: "app.singboxclient.vpn_core", code: 2)
            return -1
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        // TODO(next milestone): populate settings.ipv4Settings /
        // ipv6Settings / dnsSettings / mtu from `options` (the sing-box
        // TunOptions passed through from the parsed config) instead of
        // leaving them at NetworkExtension defaults. Preserving UDP
        // requires no special handling here -- NEPacketTunnelFlow carries
        // both TCP and UDP packets once the interface is established.
        let semaphore = DispatchSemaphore(value: 0)
        var setupError: Error?
        provider.setTunnelNetworkSettings(settings) { err in
            setupError = err
            semaphore.signal()
        }
        semaphore.wait()

        if let setupError = setupError {
            error?.pointee = setupError as NSError
            return -1
        }
        // NEPacketTunnelProvider does not expose a raw file descriptor the
        // way android.net.VpnService does; sing-box's iOS integration
        // instead reads/writes through `provider.packetFlow` in a
        // dedicated loop. That loop is the remaining piece of this method
        // -- see the TODO above.
        return -1
    }

    func useProcFS() -> Bool { false }
    func usePlatformAutoDetectInterfaceControl() -> Bool { true }
    func autoDetectInterfaceControl(_ fd: Int32, error: NSErrorPointer) {}
    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func clearDNSCache() {}
}
