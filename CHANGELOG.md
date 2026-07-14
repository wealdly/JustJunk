# Changelog

## [Unreleased]

## [1.1.0] - 2026-07-14

### Added
- Uncollected transmog is now protected everywhere JustJunk sells (bags, bank, and warband bank): any gear, weapon, or appearance-teaching item whose look you haven't collected yet is kept, so you can wear or use it to learn the appearance before selling. Already-collected looks and items you can never learn are still sold as normal. On by default; toggle under the Gear section ("Keep Uncollected Transmog").
- Bank cleanup: while your bank is open, a small "Pull Junk" button (a coin icon that attaches to the top of the bank window) moves sell-worthy items out of your bank and warband bank into your bags, ready to vendor on your next merchant visit. It uses the same rules as merchant selling, so anything protected there stays put. The warband bank is treated more cautiously still: equippable gear (Common quality or better) and containers are always left alone, since they may be an upgrade for an alt at another level or hold collectibles - only trade goods, consumables, and grey junk are pulled from it. Drag the button to reposition it, or hide it under General options. There is also a minimap button and a /jj bank command that trigger the same cleanup, so it works no matter which bag addon you use (the minimap button can be hidden under General options). An "Include Warband Bank" option (on by default) lets you limit the cleanup to this character's bank if you keep another character's materials or storage in the warband bank.
- Armor of a type your class can never wear (e.g. cloth or mail on a rogue) is now sold whatever its item level, since it can never be an upgrade. This works on its own and does not require Pawn. Soulbound (bind-on-pickup) off-type pieces you can't use, sell, or pass to an alt are cleared out; valuable bind-on-equip pieces worth more than your keep-above threshold are still kept for the auction house.
- Pawn integration: when Pawn is installed with an active scale, gear inside the item-level safety margin is also sold if Pawn says it is not a stat upgrade for anything you have equipped, even when it is a higher item level. Trinkets and artifacts are always kept (their effects can't be judged by stats), and gear worth more than your keep-above threshold on the auction house stays protected. On by default; toggle under the Gear section ("Sell Non-upgrades (Pawn)"). No effect without Pawn.

### Fixed
- Turning off a per-category enable toggle (Gear, Consumables, Trade Goods, Recipes), Merchant Automation, or Auto-sell Grey Junk had no effect: the "off" state was not saved and the setting reverted to its default. All on/off options now save and apply correctly.
- Off-armor-type gear (cloth/mail on a leather class, etc.) was only sold when Pawn was installed with an active scale; it is now sold on its own, so bind-on-pickup off-type pieces no longer pile up when Pawn is absent or has no scale for the character.
- Bag sell-markers now refresh right away when you change a selling setting in the options, instead of waiting for the next bag update.
- Auto-sort Bags now works when a custom bag addon has replaced the default bag UI. The sort previously relied on an event those addons suppress, so opening your bags never triggered it.
- Tradeable gear of an armor type your class can't use is no longer vendored when it has no auction-house price. Without price data its value is unknown, so it is now kept (it may still have transmog or auction value); soulbound off-type pieces are still cleared, and off-type gear with a known price below your threshold is still sold. This mainly affects players without an auction price addon, who previously saw all such pieces sold.
- Collectible protection (mounts, pets, toys) is hardened against a future game data change, and a couple of edge cases in the sell loop (a briefly locked item, a stuck retry) are handled more gracefully.

### Changed
- Options panel reorganized. General now holds the main switches (enable, merchant automation, merchant delay) plus an Interface section for where things show up (minimap button, bank cleanup button, warband bank, auto-sort, and the bag-marker style). A renamed Selling Rules tab holds the sell decisions, with every gear setting (item level, quality, keep-value, Pawn non-upgrades, uncollected transmog) merged into one Gear section instead of two separate boxes. Same settings and saved profiles, clearer layout.
- Options panel: added a Manual Overrides summary that shows how many items are on your always-keep and always-vendor lists, with a button to clear each. Merchant settings (and bag markers) stay usable even when merchant automation is turned off. The keep-value sliders now reach 10000g, and for trade goods and consumables the slider is labelled "Keep if Stack Value Above" to reflect that it measures a stack's value rather than a single item.
- Trade goods and consumables are now judged by the value of the bag slot they occupy, not the price of a single item. A consumable is judged by the stack you actually carry. A trade good you can gather or craft with a profession you have is judged as a full stack, since a partial stack will build back up through normal play and is worth the slot; a trade good tied to no profession you have is judged only by the units you carry, so a leftover handful that would sit unused for months gets sold. Trade goods and consumables with no auction-house price at all are sold (soulbound crafting materials are still protected).
- Poor (grey) items are now always treated as junk and sold, so the bag markers, WoW's bulk junk sale, and the item-by-item pass all agree on them (a manual keep or turning off Auto-sell Grey Junk still spares them).
- The default "keep gear worth more than" threshold is now 750 gold (was 500), selling a little more low-value gear by default. As always, you can change it under the Gear options.

## [1.0.0] - 2026-06-30

### Added
- A quick inventory sort (WoW's own sort, never the bank or warband) runs automatically right after the addon auto-sells at a merchant, compacting the emptied slots. An optional "Auto-sort Bags" toggle (off by default) additionally sorts whenever you open your bags. Both skip combat and banking; the on-open sort defers while a merchant is open so it never races the sell pass.
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
