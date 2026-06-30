# JustJunk

A World of Warcraft addon that automatically sells everything in your bags that isn't worth keeping - and keeps what is. It auto-repairs, clears junk, and vendors low-value items, using market-price awareness to protect anything worth your time to auction.

## How it decides

JustJunk sells an item only when it can confidently classify it as not worth keeping. It **keeps** anything that is:

- a potential gear **upgrade** - within your gear safety margin of what you have equipped in that slot
- **worth your time to auction** - its AH value clears the per-category keep-above threshold
- worth **saving for an alt** - account-bound (BoA / BoW) items
- a collectible or special item - toys, mounts, pets, currency, housing decor, quest items, unknown recipes, equipment-set pieces, manual keeps, and soulbound crafting materials

When in doubt, it keeps: if there's no price data for an item, or its type can't be classified, it stays in your bags. Grey/Poor items are the one exception - they're treated as junk and sold by default (toggle it off any time).

## Features

### Merchant Automation

- Automatic handling when you open any merchant, with a configurable start delay
- Auto-repair from personal funds, or the guild bank when available and permitted
- Clears grey junk through WoW's native bulk sell - instant, respects bags flagged "exclude from junk sell," and on by default (toggleable)
- Skips repair-only vendors that can't buy junk, and never touches locked or quest items

### Smart Selling Pipeline

- Per-category evaluation for gear, consumables, trade goods, and recipes
- Each category has its own enable toggle, max quality, and "keep if worth more than X gold on the AH" value
- Recipes are only sold once you already know them
- Soulbound, BoA, and BoW protection - account-bound items are kept unless they're grey consumables/trade goods
- Reagents and enchanting materials are evaluated alongside trade goods; soulbound crafting materials are protected
- Collectibles are protected: toys, mounts, companion pets, currency, and housing decor are never sold
- Session sale summary on completion (items sold and total vendor value)

### Market-Aware Protection

- Looks up auction value before selling and keeps anything worth meaningfully more on the AH
- Configurable price-source order, with a no-data cache to avoid repeated lookups
- Falls through to safe grey-item handling when no price data is available

### Item-Level-Aware Gear Evaluation

- A single "gear safety margin" keeps gear within a percentage of the item level equipped in that slot
- Falls back to your average item level when the slot is empty
- Equipment-set protection

### Bag Markers

- Marks sell candidates directly on bag buttons before you ever open a merchant
- Coin, Coin + Glow, and Coin + Dim display styles, or off
- Refreshes in step with Blizzard's own bag updates, so markers stay in sync with low overhead
- Preserves and restores each button's original icon border to coexist with item-overlay addons

### Manual Overrides

- Per-item "always keep" and "always vendor" lists via slash commands
- Overrides take effect immediately and are reflected in bag markers

## Installation

1. Extract to `Interface\AddOns\JustJunk`
2. `/jj` to open options, or just open a merchant - automation runs on its own

## Configuration

Options are organized into tabs:

| Tab | Purpose |
|-----|---------|
| **General** | Master enable, merchant automation toggle, and a Developer & Debug section |
| **Merchant** | Timing, preferred price source, bag markers, item-level evaluation, and per-category sell rules |
| **Profiles** | AceDB profiles |

## Commands

```text
/jj                                - Open options panel
/jj toggle                         - Enable/disable addon
/jj debug                          - Toggle debug mode
/jj keep <itemLink|itemID>         - Always keep an item
/jj junk <itemLink|itemID>         - Always vendor an item
/jj clear <itemLink|itemID>        - Remove a manual override
/jj overrides                      - Show override list counts
/jj inspect modules                - Show addon/module/source status
/jj inspect pricing <itemLink|id>  - Show per-source pricing diagnostics
/jj inspect markers                - Show marker settings/mapping diagnostics
/jj help                           - Show command help
```

## Technical Notes

- **Fail-open safety** - item-protection checks are written so that missing APIs or enum changes keep an item rather than risk selling it; protective enum fields are verified against current game data
- **Session-cached scanning** - sell scans persist scan state and cache merchant/category settings, with locked slots retried on later ticks
- **Reactive settings** - option changes apply immediately to active evaluation state without waiting for the next merchant open
- **Event-driven** - merchant, bag-update, and equipment-change events drive work; price and availability lookups are cached with TTLs

## Acknowledgments & Credits

### Libraries

**[Ace3 Framework](https://www.wowace.com/projects/ace3)** - *WoWAce Community*
AceDB, AceConfig, AceGUI, and AceDBOptions for configuration, profiles, and the options panel.

**[LibStub](https://www.wowace.com/projects/libstub)** - *Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke*
Library versioning. Public domain.

**[CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler)** - *Maintained by Nevcairiel and the Ace3 Team*
Event callback system used by the Ace3 libraries.

### Optional Integrations

JustJunk reads auction-price data from whichever of these you have installed, to protect items worth more on the auction house. They are tried in order, falling through to the next when one has no price for an item:

- **[TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master)** - uses your own scanned auction data (most current for your realm)
- **[Auctionator](https://www.curseforge.com/wow/addons/auctionator)** - uses your own scanned auction data
- **[Oribos Exchange](https://www.curseforge.com/wow/addons/oribos-exchange)** - ships bundled market data and needs **no auction-house scanning**, so it works the moment it's installed

None are required, but installing at least one is recommended: without price data, JustJunk keeps every non-grey item (it won't sell what it can't value) and only sells grey junk. Oribos Exchange is the lowest-effort way to get full price-aware selling, and serves as a reliable fallback behind TSM/Auctionator.

## Development Workflow

- Track pending changes in `UNRELEASED.md` (player-facing notes).
- Cut a release with `.\release.ps1 -Version X.Y.Z` - promotes `UNRELEASED.md` into `CHANGELOG.md` under the new version, bumps the `.toc` version, and resets `UNRELEASED.md`.
- Review the diff, then `git commit` → `git tag vX.Y.Z` → `git push --follow-tags`. The tag push triggers the CurseForge release workflow.
- `.\build.ps1` produces a local ZIP for testing.

## License

GNU General Public License v3.0 or later (GPL-3.0-or-later). See [LICENSE](LICENSE).

The embedded Ace3 libraries retain their original licenses and are marked in `Libs/`.

---

*JustJunk is not affiliated with or endorsed by Blizzard Entertainment.*
