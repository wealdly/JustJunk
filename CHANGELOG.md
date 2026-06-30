# Changelog

## [Unreleased]

## [1.0.0] - 2026-06-30

### Added
- Optional "Auto-sort Bags" (off by default): runs WoW's own inventory sort - never the bank or warband - when you open your bags and again right after the addon sells at a merchant. Skips during combat and while a bank is open; the open trigger also defers while a merchant is open so it never races the sell pass.
- Automatic merchant selling with a configurable start delay, plus auto-repair from personal or guild funds.
- Auto-sell of grey/Poor junk via WoW's native bulk sell - instant, honors the bag "exclude from junk sell" flag, and gated by an "Auto-sell Grey Junk" toggle (on by default) that also governs the per-item pass and bag markers. Skipped automatically when a grey item is manually kept.
- Market-aware protection using TSM, Auctionator, or Oribos Exchange, tried in a configurable order with fallthrough; keeps anything worth your time to auction. (Oribos needs no AH scanning, so it works as an out-of-the-box price source.)
- Item-level gear protection, equipment-set protection, soulbound/BoA/BoW protection, and collectible protection (toys, mounts, companion pets, currency, housing decor, quest items).
- Reagents and enchanting materials are evaluated alongside trade goods; soulbound crafting materials are protected.
- Bag markers that flag sell candidates on bag buttons before you open a merchant, with display styles: Coin, Coin + Glow, Coin + Dim, or off.
- Manual per-item overrides via slash commands: `/jj keep`, `/jj junk`, `/jj clear`, `/jj overrides`.
- Session sale summary (items sold and total vendor value) printed on completion or merchant close.
- AceConfig options panel and a structured slash-command surface (`/jj` opens options, subcommands, and an `inspect` diagnostics namespace with usage/help output).

### Changed
- Simplified sell settings: each category now has just enable, max quality, and a single "keep if AH value above X gold" threshold (the per-category safety multiplier was removed). Gear item-level protection collapses to one "Gear Safety Margin (%)" knob. All category and item-level defaults now live in a single source of truth.
- Bag markers refresh directly off Blizzard's item-button update cycle and the bag-open event instead of a polled bag-update timer, keeping markers in sync with less overhead and removing a load-order gap. Per-button state is held in a single weak-keyed table, and each button's original `IconBorder` alpha is preserved to coexist with item-overlay addons.
- Merchant setting changes apply immediately to active evaluation through a settings-change listener.
- Performance: session-persistent scan state and cached merchant/category settings cut per-item overhead; price lookups use full-item-link cache keys with no-data TTL caching.

### Fixed
- Ghost sell markers under combined bags: each button is now evaluated against its own bag/slot rather than the parent frame's bag ID with the button's slot.
- Sale summary counted an item's maximum stack size instead of the actual stack in the slot, inflating the reported item count and value.
- Locked slots are retried on later sell ticks instead of being skipped after the first full pass.
- Recipe known-spell checks use `C_SpellBook.IsSpellKnown` for current retail compatibility.
- Options/profile init reliability: safe LibStub resolution and embedded Ace dependencies (`CallbackHandler-1.0`, `AceGUI-3.0`) with corrected TOC load order.
- Merchant queue replay no longer references undefined handlers.
- Hardened the internal bag/slot key so it cannot collide on very large bags; removed an accidental duplicate engine source file and a dead durability scan in auto-repair.
