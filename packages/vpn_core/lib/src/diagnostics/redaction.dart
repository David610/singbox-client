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

// "key": "value"  or  "key":"value"  (JSON)
final _jsonKeyValuePattern = RegExp(
  r'"(uuid|password|public_key|publicKey|pbk|short_id|shortId|sid|'
  r'obfs.?password|obfsPassword|token|secret|private_key|privateKey|'
  r'subscription.?token|subscriptionToken|auth.?token|authToken)"'
  r'\s*:\s*"([^"]*)"',
  caseSensitive: false,
);

// key=value  (query string / URI, e.g. vless://...&pbk=...&sid=...)
//
// The value class excludes `"` as well as the query-string delimiters --
// this pattern also has to match a key=value pair sitting inside an
// already-JSON-encoded string (e.g. a raw engine-log line smuggled into
// a JSON field), and without excluding `"` a value ending right at the
// JSON string's closing quote greedily consumes that quote into an
// unused capture group, silently dropping it from the (quote-discarding)
// replacement and corrupting the JSON. See redactText's doc comment.
final _queryKeyValuePattern = RegExp(
  r'\b(uuid|password|pbk|sid|obfs-password|token|secret)=([^&\s#"]+)',
  caseSensitive: false,
);

// key: value  (plain log lines)
//
// Same `"`-exclusion reasoning as _queryKeyValuePattern above -- this
// also needs to not swallow a JSON string's closing quote when a raw
// log-line-shaped value happens to sit at the end of one.
final _logLineKeyValuePattern = RegExp(
  r'\b(uuid|password|public_key|pbk|short_id|sid|obfs.?password|token|'
  r'secret|private_key|subscription.?token|auth.?token)\s*:\s*'
  r'([^\s,}"]+)',
  caseSensitive: false,
);

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
  // Each pattern gets its own replacement so the matched shape's
  // delimiters (quotes for JSON, bare `=`/`: ` otherwise) are rebuilt
  // explicitly rather than guessed from the matched text -- a shared
  // guess-the-separator helper here previously dropped the JSON pattern's
  // surrounding quotes entirely, corrupting otherwise-valid JSON while
  // still satisfying `contains([REDACTED])`-only assertions. See
  // diagnostics_exporter_test.dart's "is valid, parseable JSON after
  // redaction" -- the actual regression-catching test for this class of
  // bug, which a `contains` check alone cannot catch.
  out = out.replaceAllMapped(
    _jsonKeyValuePattern,
    (m) => '"${m.group(1)}": "$_redactedPlaceholder"',
  );
  out = out.replaceAllMapped(
    _queryKeyValuePattern,
    (m) => '${m.group(1)}=$_redactedPlaceholder',
  );
  out = out.replaceAllMapped(
    _logLineKeyValuePattern,
    (m) => '${m.group(1)}: $_redactedPlaceholder',
  );
  out = out.replaceAll(_uuidPattern, _redactedPlaceholder);
  out = out.replaceAll(_longTokenPattern, _redactedPlaceholder);
  return out;
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
