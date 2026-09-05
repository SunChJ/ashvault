# Inventory, stash, and vendor transactions

`InventoryState` owns the location of every claimed UID across reserved ground,
owner bag/stash/equipment, and vendor stock. Compose one state per ItemWorld and
inject it into LootState. ItemWorld remains the immutable item record/UID ledger;
neither inventory transactions nor GLoot presentation rewrite its records.

## Containers and commands

Register owners with bag/stash capacities (0–10000) and initial integer currency
(0–2147483647). Stash belongs to the registered owner in this slice. Containers
are fixed indexed arrays of UID strings; `""` is empty. Shrinking a bag rejects
any occupied slot outside the new bounds, preserving layout rather than silently
compacting. `container_slots`, `location`, and `snapshot` return defensive copies.

All mutations require the configured creator ID. These are trusted simulation
inputs; network authentication and actor/source-event validation belong to the
future authority adapter. Registration and `place_item` are trusted setup/reward
operations. Placement accepts only known, previously unlocated UIDs. Ground
reservation claims a fresh UID for its registered owner; pickup uses the first
empty bag slot and changes its location exactly once.

`move` accepts an owner, source/destination bag or stash, both slot indices, and
the expected source UID. It rejects stale UIDs, foreign ownership, invalid slots,
and occupied destinations. Same-slot moves reject as occupied. Automatic swaps,
stacks, account-shared stash, and cross-owner gifts are not defined yet.

## Vendor transactions

Register finite vendor stock capacity and per-definition `{buy, sell}` prices.
Registration validates known item definitions, exact fields, bounded nonnegative
integers, and `sell <= buy`; it stores normalized copies. Prices cannot change
through caller dictionaries. Missing definitions are not tradable.

`buy` and `sell` transfer an existing UID between stock and the owner's bag.
Commands carry the expected UID and both slots, never a caller-supplied price.
They validate price, currency, source, and destination before publishing item
location and balance together. Insufficient currency, overflow, full stock/bag,
and stale commands preserve both containers and currency. Sold items become
ordinary vendor stock at that definition's registered buy price. Vendors have
unlimited treasury but finite stock; stock refresh is not implemented.

## Equipment integration

`configure_equipment` creates an internally owned EquipmentState using existing
registry/base/set inputs. `equip` accepts its usual changes/tick/conditions and
requires incoming UIDs to be in this owner's bag. It stages incoming removals and
places displaced equipment into the first empty slots in stable equipment-slot
order, then invokes the existing atomic legality/stat resolver. After success,
bag and location publication cannot fail. Full displacement capacity, invalid
slots, stale ticks, and stat errors leave both ownership and stats unchanged.
Use `equipment_stats` for the immutable resolved snapshot; callers do not receive
the mutable EquipmentState. Inventory snapshots include equipment slot DTOs.

## Loot and presentation

LootState retains occurrence receipts and a UID-to-occurrence provenance index.
Its ground view is derived from InventoryState locations, not an independent
ownership store. Default standalone LootState creates its own inventory; composed
gameplay must inject the shared instance. Existing register/resize/pickup helpers
delegate to it. Loot observation schema 2 embeds the inventory snapshot instead
of the former compact bags dictionary. There are no shipped saves using the old
observation schema; validated import and migration remain SaveGameV1 work.

`GlootInventoryView.items(slots, world)` creates detached GLoot InventoryItem
values with UID, slot index, name, definition, rarity, and stack limit one. UI
must send expected UID/slot commands through the simulation and refresh views
from committed snapshots. Editing or discarding these values cannot move items,
change currency, or grant ownership. Shop/inventory screen assembly is downstream.

## Reproduction

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project-ashvault --script res://tests/production/test_inventory.gd
python3 tools/ci/run_tests.py
```

Tests exercise exact-balance buy/sell, frozen prices, full containers, invalid
slots, stale/duplicate UIDs, foreign ownership, insufficient currency and
overflow, two-hand displacement, stat failure rollback, loot-to-stash transfer,
immutable item records, defensive observations, and detached GLoot mutation.
