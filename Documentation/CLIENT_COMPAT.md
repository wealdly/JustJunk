# Client compatibility: Retail and WoW Forever in one addon

One branch, one release, both clients (the JustAC model). Most of JustJunk is shared; what differs is
default thresholds and a short list of client behaviours.

## Rules

1. **One client predicate.** `JustJunk.IS_FOREVER`, set once in `Config_Data.lua` from
   `WOW_PROJECT_CAMELOT` (only defined by the Forever client). Nothing else tests the client.
2. **Gate where everything routes through.** Prefer one guard at the function every caller reaches.
3. **Retail behaviour stays as it is unless a change is meant for both.** Universal changes are
   deliberate and listed below; client-specific changes are gated.
4. **Every test runs as both clients.** `python tools/run_lua_tests.py` runs `Tests/*.lua` under Lua
   5.1 once as Retail and once as Forever (`NewEnvironment()` takes its default client from the
   `forever` argument; tests that loop over both clients pin it explicitly).

## Current client differences

| Where | Forever behaviour |
|---|---|
| `Config_Data.lua` defaults | Keep-above thresholds: gear 10g, consumables 2g, trade goods 3g, recipes 5g (Retail 750g / 20g / 50g / 500g). |
| `Config_UI.lua` | Shows the Forever threshold controls and hides the Retail-only ones. |
| `Config_Core.lua`, `ItemEngine.lua` | Forever-specific item checks and gear-scoring events. |

## Retail/Forever merge (2026-11-17)

The Forever copy was developed from the Retail working tree (`pre-merge/retail-wip`) and imported as
`pre-merge/forever` on branch `merge/forever`. Every change it adds is client-agnostic and was accepted
for both clients:

- Grey items are never valued by Auction House listings, for carried junk or incoming loot.
- Make Room finds loot by scanning loot slots instead of hooking `LootSlot`, so it works with native
  auto-loot and picks the most valuable remaining item that can be swapped.
- Make Room also checks shortly after the loot window opens and when item data arrives. It still needs
  zero free general-purpose bag slots.
- JustLoot handoff: `JustJunk.OnLootStalled()` and `JustJunk.SetAutoLootActive(active)`. Make Room
  waits while JustLoot is auto-looting.
- Pending confirmations survive loot-slot renumbering.
- A one-time chat line explains why Make Room skipped, plus debug output for unreadable loot.

No client gate was needed.

## JustLoot handoff tests

`Tests/JunkDisposal.lua` loads `..\JustLoot\JustLoot.lua` for the handoff cases, so a JustLoot
checkout must sit next to this one. JustLoot was brought in line with these tests on 2026-11-17;
all 40 cases pass on both clients.

## Versions

Every merge into `main` is released with a version bump: `.\release.ps1 -Version <x.y.z>` moves
`UNRELEASED.md` into `CHANGELOG.md` and bumps the TOC. The Retail/Forever merge is 1.2.0.
