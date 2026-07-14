## [Unreleased]

### Fixed
- Pulling junk from the bank no longer spams "Item is locked" errors or leaves some items behind. When several stacks of the same item were pulled, each move could land on a bag stack that was still settling from the previous one, so the game rejected it. The pull now waits for each move to finish resolving before starting the next.
