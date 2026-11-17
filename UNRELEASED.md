## [Unreleased]

### Added

- Optional bag-item tooltips show the keep/sell decision, its reason, and vendor/auction value for the current stack. Tooltips can be disabled independently of bag markers.
- Browse and remove individual keep/vendor overrides without clearing the entire list.
- Buying an item back pauses automatic selling until you close the merchant.
- Full-bag loot replacement and low-value non-stackable cleanup preserve protected items and require one confirmation click per deletion.
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
