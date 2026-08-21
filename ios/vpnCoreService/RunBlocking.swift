import Foundation

/// The Go `PlatformInterface`/`CommandServerHandler` methods libbox calls
/// back into (`experimental/libbox/platform.go`,
/// `experimental/libbox/command_server.go` in the pinned sing-box source)
/// are synchronous from Go's point of view -- gomobile binds them as plain
/// throwing Swift methods, not `async`. Some of them (tunnel setup in
/// particular) can only be done with `NEPacketTunnelProvider`'s async
/// Swift APIs (`setTunnelNetworkSettings(_:) async throws`). This bridges
/// a synchronous callback to an `async` body by blocking the calling
/// thread until the awaited work finishes.
///
/// This mirrors `Extension+RunBlocking.swift` in
/// SagerNet/sing-box-for-apple (verified against its `main` branch, the
/// branch pinned to the same `MARKETING_VERSION = 1.13.19` this project
/// targets) -- not a guess: libbox always invokes `PlatformInterface`
/// methods from its own background goroutine dispatch, never from the
/// extension's main run loop, so blocking here does not deadlock the
/// process.
func runBlocking<T>(_ block: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Task {
        do {
            result = .success(try await block())
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}
