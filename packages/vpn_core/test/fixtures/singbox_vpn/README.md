# singbox-vpn fixtures

Sanitized, deterministic fixtures tracing the *exact* output shapes of
[David610/singbox-vpn](https://github.com/David610/singbox-vpn) at commit
`644adbf4bb87be02dce1ecb1cf6c311032e53408`, read directly from:

- `crates/compat-config/src/render.rs` — `render_vless_reality_uri`,
  `render_hysteria2_uri`, `render_singbox_client_subscription_with_options`,
  `standard_endpoints`
- `crates/compat-config/src/server.rs` — `render_singbox_server_config`
  (used only to build the reference/interop test server — this project
  never runs or modifies singbox-vpn's own Rust server)
- `docs/COMPATIBILITY_VERSIONS.md` — confirms singbox-vpn pins the exact
  same sing-box release this client pins (`1.13.19`) — see
  `packages/vpn_core/UPSTREAM_VERSION.md`

**No credential in this directory is real.** Every UUID/key/password below
was generated fresh in this session for this purpose only, using the
pinned `sing-box generate reality-keypair`/`generate uuid` commands (real
key material, so it is cryptographically valid and usable in the interop
test in `../interop/`), never the user's real subscription or any value
from a live deployment. These are the same values `test/interop/`'s
ephemeral server actually runs against, so a fixture assertion and the
interop test are checking one shared, coherent set of test data rather
than two independent guesses.

| Field | Test value |
|---|---|
| host | `vpn.singboxvpn.test.invalid` (fixtures) / `127.0.0.1` (interop test) |
| VLESS UUID | `9c7e12d1-64c3-46f2-9e21-d707f05c88d9` |
| REALITY public key | `anIGqfcDa8ypMGtP6lcoc3Fu54p3gOWMl9LKvIjRx3w` |
| REALITY short_id | `580686c710f58181` |
| REALITY fingerprint | `chrome` (singbox-vpn's `standard_endpoints` default) |
| SNI / server_name (fixtures) | `www.microsoft.com` (a plausible decoy target; not sensitive) |
| SNI / server_name (interop test) | `localhost` (must be a real dialable local hostname — see `test/interop/README.md`) |
| VLESS flow | `xtls-rprx-vision` |
| Hysteria2 password | `test-h2-fake-password-000` |
| Salamander obfs password | `test-salamander-fake-000` |
| REALITY port | `8443` (fixtures) |
| Hysteria2 port | `8444` (fixtures) |

## Files

| File | Traces |
|---|---|
| `vless_reality_uri.txt` | `render_vless_reality_uri` |
| `vless_reality_uri_vision_off.txt` | `render_vless_reality_uri_vision_off` (`?compat=vision-off`) — requirement 2, "xtls-rprx-vision where supplied": this fixture is the case where it is NOT supplied |
| `hysteria2_uri.txt` | `render_hysteria2_uri`, with `obfs=salamander` |
| `hysteria2_uri_no_obfs.txt` | `render_hysteria2_uri`, endpoint with no salamander configured |
| `subscription_singbox.json` | `render_singbox_client_subscription_with_options` (`format=singbox`, default `SelectionProfile::Reliability`) — full two-outbound sing-box client subscription document, as returned by `GET /sub/{token}` (default format) |
| `server_config_reference.json` | `render_singbox_server_config`'s shape — reference only, used to build `test/interop/`'s ephemeral local server; never executed against or copied from a real singbox-vpn deployment |
