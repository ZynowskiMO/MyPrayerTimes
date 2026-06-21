# ADR-0007: Bundled per-prayer icons

- **Status:** Accepted
- **Date:** 2026-06-21
- **Decision makers:** Muhamed Bašić (PO), Claude (advisory)
- **Relates to:** ADR-0005 (settings redesign — deferred bundled art to the PO).
  This is the first bundled-art decision; it follows ADR-0005's intent.

## Context

The display is currently text-only: each prayer row shows a name, a time and
the gold "active" bar. The PO wants small icons per prayer (a crescent for
Fajr/Isha, sunrise for Shurūq, sun for Dhuhr/Asr, sunset for Maghrib) in the
clean cream/gold line style of a reference app, shown in a rounded slot at the
left of each row.

WoW can draw an icon two ways: a **bundled texture file** shipped with the
addon, or a **built-in client texture** referenced by path. The default game
font does not render Unicode symbol glyphs (they appear as empty boxes — the
reason the dropdown arrow and the selection check are already textures), so an
icon must be a texture, not a font glyph.

To match the reference look we need our own line-art icons. That means shipping
image files, which is a new class of asset for this repo (until now: code +
data only) and carries a licensing obligation, exactly like the adhan-js MIT
text we already keep.

## Decision

1. **Per-prayer icons in the main window rows.** Each of the six rows (Fajr,
   Shurūq/Sunrise, Dhuhr, Asr, Maghrib, Isha) gets an icon in a rounded slot at
   its left. The existing gold active-bar and row highlight stay as they are.

2. **An `Icons` registry with a safe fallback.** A small `ui/Icons.lua` maps
   each prayer key to a texture path under `Media/icons/`. A helper applies the
   texture to a row's icon `Texture`. If a file is missing or fails to load, the
   helper falls back to a neutral built-in texture (or a plain tinted square) so
   a missing asset never breaks a row. This keeps art swappable from one place.

3. **Bundled assets live in `Media/`.** Icons are small power-of-two textures
   (e.g. 64×64) in `.tga` or `.blp`, the formats WoW loads. No code change is
   needed to swap a placeholder for final art — only the file is replaced.

4. **Licensing is mandatory before an icon ships.** Only icons under a license
   that permits redistribution may be bundled: the PO's own art, or a
   permissive third-party set (CC0 / MIT / similar). Each third-party source and
   its licence is recorded in `THIRD_PARTY_LICENSES.md` and credited where the
   licence requires. No icon is committed without a cleared licence.

5. **Cross-client constraint holds.** `Texture:SetTexture(path)` by file path is
   stable on Retail and Classic. No new API or dependency.

6. **Placeholder-first.** The icon slots + registry are built now with
   placeholders (built-in textures or simple shapes) so the layout is verifiable
   in-game immediately. The PO's final art drops into `Media/icons/` and replaces
   the placeholders 1:1, with no code change.

## Checkpoint plan (governed by this ADR)

- **3I-1** Icon slot + `ui/Icons.lua` registry with fallback, wired into the
  main window rows, using placeholders. Runner covers the registry + fallback.
- **3I-2** Drop in the final (PO-supplied or licence-cleared) art and record its
  licence in `THIRD_PARTY_LICENSES.md` + README/CurseForge credit.
- *(later, optional)* the same icons in the wizard/settings if wanted.

Each checkpoint keeps a working, runner-green build and is verified in-game.

## Consequences

Positive:
- The display matches the intended polished look; rows are scannable at a glance.
- Art is swappable from one folder; placeholders unblock layout work now.
- Repo stays small (a handful of tiny textures).

Negative / trade-offs:
- First bundled binary assets — a licence must be cleared and recorded for any
  third-party icon, and binary files are less reviewable than code.
- Placeholders are visible until final art is supplied.

## Revisit when

- The set of displayed prayers/rows changes, or
- The PO wants icons elsewhere (wizard, settings, minimised view), or
- A chosen icon set's licence terms change.
