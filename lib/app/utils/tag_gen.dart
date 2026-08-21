// Reconstructed (see docs/FORK_ARCHITECTURE_AUDIT.md, docs/ARCHITECTURE.md).
library;

/// Generates unique tags by appending a numeric suffix when a proposed tag
/// collides with one already seen.
class TagGen {
  TagGen({Map<String, int>? tags}) : _seen = Map<String, int>.from(tags ?? {});

  final Map<String, int> _seen;

  String gen(String tag) {
    if (!_seen.containsKey(tag)) {
      _seen[tag] = 1;
      return tag;
    }
    var index = _seen[tag]!;
    String candidate;
    do {
      index++;
      candidate = '$tag ($index)';
    } while (_seen.containsKey(candidate));
    _seen[tag] = index;
    _seen[candidate] = 1;
    return candidate;
  }
}
