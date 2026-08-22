# Licensing audit

Facts only. No legal conclusions are drawn here — see "Recommended path" at
the end for the actual decision this blocks.

## Known facts

**Root `/LICENSE`**: full, unmodified Apache License 2.0 boilerplate,
including the unfilled `Copyright [yyyy] [name of copyright owner]`
template placeholder in its appendix. No project-specific copyright line
was ever supplied.

**Root `/LICENSE.md`**: GPL-3.0 text (abbreviated, not the full canonical
GPL block), opening `Copyright (C) 2024 by nebula`, and closing with a
clause that is **not** part of stock GPL-3.0: *"In addition, no derivative
work may use the name or imply association with this application without
prior consent."*

**These two root files directly contradict each other**: one claims
Apache-2.0 (permissive), the other claims GPL-3.0 plus an extra
naming/non-endorsement restriction, attributed to a "nebula" copyright
holder who is not this project's author. `git log` shows `LICENSE` arrived
in the initial commit and `LICENSE.md` arrived later when the Karing source
was added as this project's base — i.e. the conflict predates this
project's own work and was never resolved by it.

**No `NOTICE`, `COPYING`, or `THIRD_PARTY_NOTICES` file exists anywhere in
the repository.**

**Source file headers**: essentially no file in `lib/`, `packages/vpn_core/`,
`android/app/src/main/kotlin/`, or `ios/` carries an SPDX identifier or
copyright header. The one exception is `lib/screens/widgets/fab2.dart`,
which carries its own standalone `Copyright 2020 Chaobin Wu`, Apache-2.0
header — a third-party widget with its own attribution, unrelated to either
root license file. Prior sessions' own reconstructed files (e.g.
`lib/app/utils/log.dart`, `app_utils.dart`, `crypto_utils.dart`) carry
provenance comments ("Reconstructed (see docs/...)") but no license/SPDX
tag either. Original-Karing files are unmarked.

**`packages/vpn_core`**: declares no license of its own anywhere (no
`license:` field in `pubspec.yaml`, no LICENSE file in the directory). It
neither matches nor contradicts the root files — it is simply silent.

**sing-box / libbox** (`packages/vpn_core/native/singbox-go`, pinned via
`UPSTREAM_VERSION.md` at `github.com/sagernet/sing-box` tag `v1.13.19`):
confirmed **GPL-3.0**, per that upstream project and per this repo's own
`UPSTREAM_VERSION.md`, which already flags it explicitly: *"License |
GPL-3.0 (upstream project's own license; unrelated to this repo's
LICENSE.md)"* — i.e. a prior session already noted this tension without
resolving it.

**Dependency skim**: `pubspec.yaml` carries no per-dependency license
annotations. `packages/vpn_core/native/singbox-go/go.mod`'s sole direct
requirement is sing-box (GPL-3.0, above); its ~100 indirect modules are the
usual sagernet/tailscale/golang.org ecosystem, none independently
identified as GPL/AGPL, but `docs/CI.md`'s own "License inventory scope"
section states plainly that per-package license *text* has never been
fetched or verified for the ~150 Dart or ~150 Go dependencies — only a
resolved-version manifest is generated, deliberately, as a documented gap.

**Existing prior documentation**: `docs/FORK_ARCHITECTURE_AUDIT.md` §10
already discusses this exact tension (GPL-3.0 + the non-endorsement clause
in `LICENSE.md`) and flags it (its own priority marking) as a risk to
resolve before any independent-brand publish — but its characterization of
root `LICENSE` as GPL-3.0 does not match that file's actual current content
(Apache-2.0), suggesting it was written describing only `LICENSE.md`,
without reconciling it against `LICENSE`.

## Unknowns

- Which license actually governs this repository as distributed —
  Apache-2.0, GPL-3.0 (plus the added naming restriction), or something
  the project has never formally declared — is genuinely undetermined from
  the repository's own contents. The two root files were never reconciled
  by anyone, including this pass.
- Whether Karing's original upstream project holder ("nebula") actually
  holds enforceable rights over the naming/non-endorsement clause, and
  whether that clause is even valid to attach to a GPL-3.0 work (GPL-3.0
  itself does not straightforwardly support additional restrictions of
  that shape — this is a genuine open legal question, not a formatting
  one).
- Whether any GPL/AGPL-licensed Go module beyond sing-box itself is present
  transitively — not individually checked module-by-module.
- Whether "no derivative work may use the name or imply association...
  without prior consent" (from LICENSE.md) is compatible with this
  project's own intent to ship as a distinctly-branded, independent app
  ("singbox-client") built partly from Karing's source.

## Potential blocker

**P0 RELEASE BLOCKER — LEGAL REVIEW REQUIRED.**

Distributing an app that:
1. bundles GPL-3.0 code (sing-box, statically/dynamically linked into the
   mobile binary) alongside a root license file claiming Apache-2.0, with
   no reconciliation of which governs the combined work, and
2. is built substantially from a fork whose own LICENSE.md asserts a
   naming/non-endorsement restriction of unclear legal force under GPL-3.0,

is not a defensible position to submit to the Apple App Store or Google
Play Store without an actual answer to "what license governs this
repository, and does GPL-3.0's copyleft obligations (source availability,
etc.) actually apply to the shipped binary." This is not resolved by the
app compiling, by CI being green, or by this pass's identity/permission
hardening work — those are orthogonal to the licensing question.

## Recommended path

This audit does not relicense anything, does not remove upstream copyright
notices, and does not fabricate a resolution. The concrete next step is a
human legal decision, not further code archaeology:

1. Determine authoritatively which license the combined work (this
   repository's own original code + Karing-derived code + statically
   included GPL-3.0 sing-box) must be distributed under, and reconcile or
   remove one of the two contradictory root license files accordingly.
2. If GPL-3.0 governs (likely, given sing-box's inclusion), confirm the
   project can meet GPL-3.0's obligations for App Store distribution
   specifically (source availability, license text bundled with the app,
   etc. — Apple's terms and GPL-3.0 have a documented history of friction
   here that needs a real answer, not an assumption).
3. Separately resolve whether the "no derivative work may use the name...
   without prior consent" clause in `LICENSE.md` applies to this project
   at all, and if so, get that consent or drop the Karing-derived name
   dependency entirely (this pass's identity rebrand, see
   `docs/CLIENT_PRODUCTION_BASELINE.md`, is a step in that direction but
   does not itself resolve the licensing question).

Until 1–3 are actually decided by someone with the authority and standing
to decide them, this item stays open. No further engineering work in this
repository should be read as having resolved it.
