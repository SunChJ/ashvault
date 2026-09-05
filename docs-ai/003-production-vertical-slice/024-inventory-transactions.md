# 003.024 — Inventory, stash, and vendor transactions

## Context and plan

M3-05 extends bounded pickup bags into a single simulation-owned location
ledger. Independent inventory/equipment/vendor ownership would allow the same
UID to appear twice. Keep immutable ItemWorld records and reuse EquipmentState
for slot legality and stat resolution.

Implement fixed indexed bag/stash/vendor slots, ground reservations, bounded
integer currency, authoritative per-definition buy/sell prices, and UID-checked
moves. Occupied move destinations reject rather than implicitly swap. Buy/sell
check source UID, destination, price and currency before committing. Equipment
transactions stage incoming/displaced bag items before running the existing
atomic resolver; no fallible work follows successful equipment publication.

LootState delegates ownership to InventoryState, with optional injection for
shared composition. Retain its pickup convenience APIs and occurrence receipts.
GLoot receives detached display items through a presentation adapter; mutations
of those items cannot affect simulation. Reviewed installed GLoot inventory and
InventoryItem APIs and the previously evaluated Asset Library component; reuse
its view data types, not its mutable Node storage as authoritative state.

Stash is per registered owner for this slice. Vendors have finite stock slots,
unlimited treasury, and frozen nonnegative integer buy/sell prices (sell <=
buy); buying transfers an existing UID. Save import, crafting, vendor refresh,
account-wide sharing and shop screen assembly remain downstream.

## Validation plan

Focused headless tests cover full containers, invalid slots, stale/repeated
UIDs, foreign owners, insufficient currency, overflow, buy/sell conservation,
loot integration, equipment displacement and stat failure rollback, and GLoot
view isolation. Follow with the full local suite and Windows/macOS CI.

## Outcome and validation

Implemented the shared location ledger, indexed bag/stash/vendor commands,
owned equipment wrapper, and detached GLoot display adapter. Loot snapshot
schema 2 embeds inventory ownership; current contracts and deferred save import
are documented in [INVENTORY.md](../../project-ashvault/game/simulation/items/INVENTORY.md).

Passed focused `test_inventory.gd` and `test_loot.gd` headless fixtures and the
complete `python3 tools/ci/run_tests.py` suite (49 Python tests, all Godot
contracts, replay/performance gates, and scene smoke). The existing 200-drop
fixture retained its pinned item hash. Full local output is available at
`.artifacts/inventory-validation.log` (ignored local evidence).

No scope deviations. Documentation now directs composed gameplay through the
owned equipment wrapper rather than claiming inventory ownership is deferred.
