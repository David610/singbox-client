package app.singboxclient.vpn_core

/**
 * Reflection boundary around the pinned sing-box `libbox` Android bindings
 * (Java package `io.nekohasekai.libbox`, produced by
 * `gomobile bind -javapkg=io.nekohasekai` per upstream
 * `cmd/internal/build_libbox/main.go` -- see
 * packages/vpn_core/UPSTREAM_VERSION.md for the exact pinned commit).
 *
 * This module is reached via reflection, not a direct `import
 * io.nekohasekai.libbox.*`, for one reason: `libbox.aar` is a build output
 * (produced locally by native/singbox-go/build_android.sh from Go source),
 * not something committed to this repository -- see
 * docs/ARCHITECTURE.md "Why libbox.aar isn't committed". Reflection lets
 * this whole module, and therefore `flutter pub get` / `flutter analyze` /
 * `flutter test` for the app, keep working even before a developer has run
 * that build step. Once `libbox.aar` is present (declared in
 * android/build.gradle as `implementation(files("libs/libbox.aar"))`),
 * every call below resolves to the real pinned core at runtime.
 *
 * Verified against the pinned sing-box source: [version] maps 1:1 to
 * `libbox.Version() string` (experimental/libbox/setup.go) and [checkConfig]
 * to `libbox.CheckConfig(configContent string) error`
 * (experimental/libbox/config.go).
 *
 * NOT yet wired here: starting/stopping the actual tunnel through
 * `libbox.NewCommandServer` + the `PlatformInterface`/`CommandServerHandler`
 * callback surface (a larger, gRPC-based daemon API). See
 * docs/ARCHITECTURE.md "Remaining incompatibilities" -- this is the single
 * next implementation task after this architectural milestone, tracked
 * there rather than half-implemented here against unverified assumptions
 * about that interface.
 */
internal object LibboxBridge {
    private const val LIBBOX_CLASS = "io.nekohasekai.libbox.Libbox"

    val isAvailable: Boolean by lazy {
        try {
            Class.forName(LIBBOX_CLASS)
            true
        } catch (e: ClassNotFoundException) {
            false
        }
    }

    /** Mirrors `libbox.Version()`. Returns null if libbox.aar is absent. */
    fun version(): String? {
        if (!isAvailable) return null
        return try {
            val libbox = Class.forName(LIBBOX_CLASS)
            libbox.getMethod("version").invoke(null) as? String
        } catch (e: ReflectiveOperationException) {
            null
        }
    }

    /**
     * Mirrors `libbox.CheckConfig(configContent string) error`. Returns
     * null on success, or the error message on failure. Never logs
     * [configJson] itself (it may contain credentials).
     */
    fun checkConfig(configJson: String): String? {
        if (!isAvailable) return "libbox.aar not present (see docs/BUILDING.md)"
        return try {
            val libbox = Class.forName(LIBBOX_CLASS)
            val error = libbox.getMethod("checkConfig", String::class.java)
                .invoke(null, configJson)
            error?.toString()
        } catch (e: ReflectiveOperationException) {
            "libbox.CheckConfig invocation failed: ${e.cause?.javaClass?.simpleName ?: e.javaClass.simpleName}"
        }
    }
}
