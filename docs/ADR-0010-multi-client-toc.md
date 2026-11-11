# ADR-0010: Multi-client TOC and packaging (Retail + Forever)

- **Status:** Accepted
- **Date:** 2026-11-11
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0002 (local calculation; engine stays frozen).

## Context

WoW: Forever launched 2026-11-04 (patch 1.60.1, game type `camelot`, alias
`forever`; Modern API up to 12.1.5, Midnight secrets active). The addon should
load there in addition to Retail. An audit (2026-11-11) found the addon uses no
client-divergent APIs, no XML templates, and no secret-restricted data, so the
same files can ship to every client unchanged — only the `## Interface:` line
differs per client.

Options considered for the TOC: (a) per-client TOC files
(`MyPrayerTimes_Forever.toc` etc.), (b) one TOC with `AllowLoadGameType`,
(c) one TOC with comma-delimited Interface numbers.

## Decision

1. **One `MyPrayerTimes.toc` with comma-delimited Interface numbers**
   (supported since client 10.2.7): `## Interface: 120105, 20505, 16001`.
   Per-client TOCs would be three drifting copies of the same list, and
   `tools/wow_load_check.lua` parses exactly one TOC. The order of the
   numbers carries no meaning to the client or the packager.
2. **No `AllowLoadGameType` / `ExcludeLoadGameType`.** Those directives gate
   loading; we want the opposite (load everywhere). On clients that do not
   recognise a listed game type the allow-condition counts as satisfied,
   which makes the directive misleading as a targeting tool.
3. **Packaging unchanged.** `.pkgmeta` and the release workflow stay as they
   are; `BigWigsMods/packager@v2` (>= v2.6.0) reads all Interface numbers and
   tags the matching CurseForge game versions (Forever flavor, type 88568)
   from a single zip.
4. **Interface numbers come from in-game `GetBuildInfo`, never from memory
   or a wiki.** Values for this release, read by the PO in-game:
   Retail 120105 (12.1.5), Forever 16001 (1.60.1, build 70888).
5. **TBC Classic remains supported.** "Retail + Forever" names the clients
   *added or re-verified* this release, not the support list: the TOC keeps
   the existing TBC Classic number (20505) and the addon continues to load
   there unchanged.

## Consequences

- One source tree, one TOC, one zip, three CurseForge game-version tags.
- Release scope here is Retail + Forever; smoke tests happen on the working
  copy (Retail symlink, Forever symlink once installed) before any tag.
- Sound: `PlaySoundFile(561542, "Master")` verified present on Forever
  (returned `true`, handle 9646) — no fallback needed.

## Open follow-ups

- **Bump the TBC Classic interface number only after in-game confirmation**
  via `GetBuildInfo` on that client; until then the TOC keeps the existing
  `20505`. (Wiki lists 20506, deliberately not trusted per point 4.)
