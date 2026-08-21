/// Central redaction. Every code path that can end up showing text to a
/// user or exporting it (the diagnostics screen, "Export diagnostics",
/// and the sanitized engine log line surfaced on the diagnostics
/// snapshot) MUST go through [redactText] before display/export. This is
/// deliberately the only redaction implementation in the diagnostics
/// module -- see redaction_test.dart, which is the actual enforcement
/// mechanism (a regression here is a security regression, not a style
/// nit).
///
/// Two layers, both always applied:
///   1. Key-aware: `"password": "..."`, `password=...`, `pbk=...` etc --
///      recognizes the exact field names singbox-vpn and this project's
///      own SingBoxConfigBuilder use (uuid, password, public_key, pbk,
///      short_id, sid, obfs-password, token, secret, private_key,
///      subscription, authtoken) in JSON, query-string, and `key: value`
///      log-line shapes, and masks the value.
///   2. Shape-aware, defense in depth for anything the key-aware pass
///      missed (an unfamiliar log format, a future field): a standalone
///      UUID, or a long base64url/hex run (REALITY keys and Hysteria2
///      passwords are both this shape), gets masked wherever it appears.
library;

final _keyValuePatterns = <RegExp>[
  // "key": "value"  or  "key":"value"  (JSON)
  RegExp(
    r'"(uuid|password|public_key|publicKey|pbk|short_id|shortId|sid|'
    r'obfs.?password|obfsPassword|token|secret|private_key|privateKey|'
    r'subscription.?token|subscriptionToken|auth.?token|authToken)"'
    r'\s*:\s*"([^"]*)"',
    caseSensitive: false,
  ),
  // key=value  (query string / URI, e.g. vless://...&pbk=...&sid=...)
  RegExp(
    r'\b(uuid|password|pbk|sid|obfs-password|token|secret)=([^&\s#]+)',
    caseSensitive: false,
  ),
  // key: value  (plain log lines)
  RegExp(
    r'\b(uuid|password|public_key|pbk|short_id|sid|obfs.?password|token|'
    r'secret|private_key|subscription.?token|auth.?token)\s*:\s*'
    r'([^\s,}]+)',
    caseSensitive: false,
  ),
];

/// Standalone UUID (e.g. a VLESS UUID appearing with no surrounding
/// "uuid=" context that pattern (1) above would have caught).
final _uuidPattern = RegExp(
  r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
);

/// A long run of base64url/hex-shaped characters -- REALITY public keys
/// (43-44 chars, base64url) and typical Hysteria2/Salamander passwords
/// both fall in this shape. 24 chars is a deliberately conservative
/// floor: short enough to catch a trimmed/shortened credential, long
/// enough that ordinary diagnostic text (hostnames, version strings,
/// short hashes) essentially never matches it by accident -- see
/// redaction_test.dart's "does not over-redact ordinary diagnostic
/// text" cases.
///
/// Consequence, by design: a FULL 40-char git SHA would also match this
/// and get masked. [DiagnosticsSnapshot.appBuildSha] is documented to
/// use a short SHA (<=12 chars, the conventional `git rev-parse --short
/// HEAD` form) specifically so it survives this pass -- see that class's
/// doc comment. This redaction module never carries a per-field exemption
/// list; keeping every field's own construction safe-by-default was
/// judged a stronger guarantee than trusting an exemption list to stay
/// correct as fields are added later.
final _longTokenPattern = RegExp(r'\b[A-Za-z0-9_-]{24,}\b');

const _redactedPlaceholder = '[REDACTED]';

/// Redacts [input] in place (returns a new string; never mutates).
/// Idempotent: `redactText(redactText(x)) == redactText(x)`.
String redactText(String input) {
  var out = input;
  for (final pattern in _keyValuePatterns) {
    out = out.replaceAllMapped(
      pattern,
      (m) => '${m.group(1)}${_separatorFor(m.group(0)!)}$_redactedPlaceholder',
    );
  }
  out = out.replaceAll(_uuidPattern, _redactedPlaceholder);
  out = out.replaceAll(_longTokenPattern, _redactedPlaceholder);
  return out;
}

String _separatorFor(String matchedText) {
  if (matchedText.contains('":')) return '": "';
  if (matchedText.contains('=')) return '=';
  return ': ';
}

/// Shows only the last [visible] characters of a credential, for cases
/// where a stable, low-entropy correlation handle is useful (e.g. "which
/// profile is this diagnostics bundle about") without exposing the
/// credential itself. Never call this on a value you then also pass
/// through [redactText] expecting it to look untouched -- masked output
/// like `****d8d9` will NOT trip the long-token heuristic (too short),
/// which is intentional: this IS the redacted form.
String redactKeepingSuffix(String credential, {int visible = 4}) {
  if (credential.length <= visible) return '*' * credential.length;
  final suffix = credential.substring(credential.length - visible);
  return '${'*' * 4}$suffix';
}
