# JustJunk

A World of Warcraft addon for intelligent merchant automation: auto-repair, sell junk, and selectively vendor low-value items using market price awareness.

## Features

- Automatic merchant handling with configurable delay
- Auto-repair support (personal funds or guild bank when available)
- Smart selling pipeline for gear, consumables, trade goods, and recipes
- Market-aware protection using TSM, Auctionator, or Oribos Exchange pricing
- Item-level-aware gear evaluation (slot comparison, average ilvl, and fallback threshold)
- Equipment-set protection and soulbound checks
- Configurable thresholds and per-category AH-vs-vendor multipliers
- AceConfig options panel and slash command controls

## Commands

```text
/jj                  - Toggle addon enabled state
/jj config           - Open/close options
/jj status           - Show module and pricing source status
/jj help             - Show command help
/jj debug            - Toggle debug mode
```

## Development Workflow

- Track pending changes in UNRELEASED.md
- Promote release notes into CHANGELOG.md when versioning
- Build distributable ZIP with .\build.ps1
- Tag with v<version> to trigger CurseForge release workflow

## License

GNU General Public License v3.0 or later (GPL-3.0-or-later). See LICENSE.
