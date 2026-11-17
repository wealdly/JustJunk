## [Unreleased]

### Added

- Optional bag-item tooltips show the keep/sell decision, its reason, and vendor/auction value for the current stack. Tooltips can be disabled independently of bag markers.
- Browse and remove individual keep/vendor overrides without clearing the entire list.
- Buying an item back pauses automatic selling until you close the merchant.
- Full-bag loot replacement and low-value non-stackable cleanup preserve protected items and require one confirmation click per deletion.
- Make Room works with native auto-loot and with several items in the loot window: it offers the swap for the most valuable remaining item, and checks again once the loot window opens and item data arrives. It still only acts when no general-purpose bag slot is free.
- Optional handoff from JustLoot: Make Room waits while JustLoot is auto-looting and takes over once its retry loop stops.
- When Make Room cannot help, a single chat line says why and confirms nothing was destroyed.
- WoW Forever support, with default keep-above values suited to its economy: gear 10g, consumables 2g, trade goods 3g and recipes 5g. Existing custom values are preserved.
- Added "Keep Equipment Set Items" under Gear, enabled by default. Disable it to evaluate saved-set gear by the normal item-level, auction-value and manual-keep rules.

### Removed

- Removed "Keep Uncollected Transmog": vendoring collects appearances, so this gear now follows the normal item-level, auction-value and manual-keep rules.

### Fixed

- Repair requests check actual guild funds, handle unlimited guild allowances, and fall back to sufficient personal funds when needed. Failed requests are reported rather than logged as completed repairs.
- Auto-repair runs when a merchant opens rather than waiting for the sell pass, so brief merchant interactions still request repairs.
- Gear with an unavailable item level is kept rather than treated as low-level gear.
- Refundable purchases and loot still tradeable with the group are kept, avoiding unsupported sale confirmations and preserving those windows.
- Selling is skipped at vendors that cannot buy items, including repair-only NPCs and token quartermasters.
- Selling stops after repeated vendor rejections instead of continuing through every bag slot and producing repeated errors.
- Grey items are valued at vendor price only. Auction House listings for greys are asking prices, not resale value, so they no longer protect carried greys or inflate incoming grey loot.
- A Make Room confirmation stays valid when loot slots are renumbered, and is cleaned up if the dialog is hidden before you confirm.
