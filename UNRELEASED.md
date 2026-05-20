## [Unreleased]

### Fixed
- Core: fixed merchant queue replay calling an undefined OnMerchantShow symbol by using proper local forward declarations for merchant handlers.
- Config: replaced invalid LibStub pcall usage with safe library resolution helper, preventing option panel and profile setup failures on load.
- ItemEngine: migrated deprecated spell-known checks to C_SpellBook.IsSpellKnown for current retail API compatibility.

### Changed
- Utils: switched bag flag handling to Enum.BagSlotFlags.ExcludeJunkSell fallback pattern and dynamic equipped bag-slot detection for forward compatibility.
- Item/Utils: migrated deprecated item info calls to C_Item.GetItemInfo in item parsing and equip-slot detection paths.
- Utils: added TableMerge helper used by config fallback initialization path.
- MarketEngine: tightened Auctionator API readiness checks (requires both item-link and item-ID price functions) and Oribos readiness checks via OEMarketInfo(0) so source status only reports available when pricing data is actually loaded.
- MarketEngine: pricing cache now keys by full item link when available to prevent cross-variant price reuse (suffix/item-level/bonus differences).
- MarketEngine: source availability checks are now throttled with a short TTL to reduce repeated external API probes during large sell scans.
- Utils: ScheduleOnce now enforces keyed dedupe by cancelling/replacing prior timers for the same key.
- ItemEngine: sell attempts now require post-use bag-slot state change confirmation before marking an item as sold for the session.
