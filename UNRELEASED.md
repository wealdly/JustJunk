## [Unreleased]

### Fixed
- Pulling junk from the bank no longer spams "Item is locked" errors or leaves some items behind. When several stacks of the same item were pulled, each move could land on a bag stack that was still settling from the previous one, so the game rejected it. The pull now waits for each move to finish resolving before starting the next.

- Items that belong to an equipment set are never sold, never marked as junk, and never pulled out of the bank, whatever their quality. The previous check only looked at your bags and only applied to items that reached the gear rules, so a set piece stored in the bank or warband bank could be pulled out to be vendored. Spare copies of a set item are protected too, erring on the side of keeping.

### Changed
- Automatic merchant selling paces itself a little more conservatively, staying well within the game's action limits so selling a large number of items can't trip a rare disconnect. Grey junk is unaffected (it still sells in one instant batch).
