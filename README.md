# Grain Rot — Enemy Pattern Drops

**v0.1.2-5pct (test build).** UE4SS 3.x Lua mod for `Helden` / Grain Rot.

## v0.1.2 drop chance (2026-11-20)

- Changed per-enemy chance from 100% to **5%**.
- Moved chance roll before the costly player controller / ownership lookups; unsuccessful rolls avoid native cosmetic and profile work.
- Added deterministic probability boundary tests (roll = 0.05 is rejected, roll = 0.0499 is accepted).
- Kept v0.1.1 FPS optimizations and native unlock behavior.

## v0.1.1 FPS hotfix (2026-11-20)

**Player report:** cosmetics do unlock, but a freeze/hitch occurs when an enemy dies. There is no UE4SS.log attached to the report; the exact hotspot is not yet proven. Do **not** infer that a successful mock implies hitch elimination.

- `OnCharacterDeath` now only validates/snapshots the enemy (type, key, world, position) and queues an event. No `FindAllOf("HeldenPlayerController")`, profile search, DataTable scan, Blueprint lookup, actor spawn, or native interaction inside the death callback.
- Cache the authoritative `GameMode`, the local `GameInstance`, the cosmetic DataTable candidate list, and the cosmetic loot Blueprint after first discovery.
- Prewarm assets **during idle game-thread timer ticks**, before the first kill when possible. Cache lookup retries are throttled when assets are not loaded.
- Build a set of owned cosmetic IDs **once per award**, rather than rescanning native TArrays for every candidate.
- Process at most **one cosmetic pickup per timer tick** and require **two 350ms timer ticks between award attempts**. A multi-kill queue is not granted all at once. Since v0.1.2 the chance is 5%.
- Emit `PERF SpawnActor`, `PERF OnRep_CosmeticID`, `PERF NativeInteract`, `PERF PrewarmDataTable`, and `PERF DeathCallback` entries only for operations over ~18ms of Lua/engine CPU time. `os.clock` is used **only** for diagnostic durations, not for delays/scheduling.
- The test suite includes checks that kill callbacks do no global registry, DataTable or Blueprint lookup, plus a four-enemy burst test.

**If freezing persists:** submit `UE4SS.log` from a kill; look for `PERF NativeInteract cpu_ms` and `PERF SpawnActor cpu_ms`. A main-thread stall inside native pickup is still possible and requires a separate change to the award mechanism.

## Requested behavior

- **5%** independent chance per killed enemy (`Chance=0.05` in `main.lua`). A pattern is granted only on a successful roll; each success selects one not-yet-owned pattern.
- Choose **one random pattern texture/color** not yet owned by the receiving player.
- Applies to **Story Mode and Expedition Mode**; no forced Expedition-only check.
- Award via the game's **native `HeldenCosmeticLoot:Interact(InCharacter)`**. This is a transient pickup, not a permanent physics drop on the floor.
- The closest player-character to the defeated enemy receives the attempted pickup. Host authority only; the client need not install this script.
- Duplicate kill callbacks do not multiply rewards; a respawned enemy with the same name may reward again.
- If all candidate patterns are owned, nothing is awarded. Hats, badges, and Steam inventory rewards are excluded.

## Install

1. **Back up the game profile and saves.** This alpha changes permanent cosmetics.
2. Download `GrainRotEnemyPatternDrops-v0.1.2-5pct` artifact from the successful [GitHub Actions test/package run](../../actions/workflows/ci.yml); open the artifact and extract the enclosed ZIP.
3. Unzip the installation ZIP into `Grain Rot/Helden/Binaries/Win64/`, leaving the existing UE4SS installation untouched.
4. Check files: `ue4ss/Mods/GrainRotEnemyPatternDrops/Scripts/main.lua` and `ue4ss/Mods/GrainRotEnemyPatternDrops/enabled.txt`.
5. **Host only** in multiplayer. On an expendable profile, defeat multiple enemies and inspect `UE4SS.log` for `[GrainRotEnemyPatternDrops]` records.
6. Open cosmetic customization: verify each unlocked texture/color is selectable. Save, quit, restart, and confirm unlocks remain. Repeat with a client and both gameplay modes.

## Technical research (grounded, but NOT live-confirmed)

Read `SirRosa/Grain-Rot-Mod-Data-Base` (current USMAP + 32MB ObjectDump, build `Helden-5.7.4`):

- `HeldenDungeonEnemyManager.OnCharacterDeath(InCharacter)` and `OnCharacterSpawned(InCharacter, InEntryIdx)` are real reflected functions.
- `HeldenCharacter.AppliedCharacterPreset.CharacterType=4` identifies an enemy (1 = player).
- `HeldenDataSingleton.CosmeticDataTable` has rows `HeldenCosmeticData` (`UniqueID`, `DataName`, `Category`, `SteamInventoryID`).
- `HeldenProfileSaveGame.UnlockedCosmetics`, `HeldenGameInstance.ProfileSaveGame`, and `HeldenPlayerState.NewCosmeticUnlocks` exist.
- `HeldenCosmeticLoot` has `CosmeticID`, `bPickedUp`, and `OnRep_CosmeticID`. Verified loaded Blueprint name: `BP_HeldenCosmeticLoot_TexturePattern_01_C`.
- `HeldenInteractableObject.Interact(InCharacter)` is reflected on the cosmetic loot parent; **`Interact_Auth` is not**. The mod calls only the reflected method, not the visual-only `PickedUpBy_Multicast`.

**The reflected function exists, but we do not yet know if calling it on a newly spawned cosmetic actor unlocks the desired pattern in the real game.** The alpha therefore checks `bPickedUp` and the host's local profile / player's `NewCosmeticUnlocks`. If no proof after eight game-thread timer ticks, it removes the transient actor and logs `PICKUP NOT CONFIRMED`. False success is not reported.

## Real-game log interpretation

- `HOOK registered`: registration **only**, not proof that death callback fired.
- `pattern table loaded: N candidate pattern IDs`: filtering worked; inspect count against expected cosmetic list (there are 25 Expedition-exclusive pattern textures/colors).
- `PICKUP ATTEMPT`: the native `Interact` call was made, **not yet proof of unlock**.
- `PICKUP CONFIRMED ... proof=profile/state`: runtime profile or player-state list reflects new ID (persistence after reload still requires testing).
- `PICKUP CONFIRMED ... proof=native bPickedUp`: native pickup flag set, **not yet proof of profile persistence**.
- `GRANT FAILED` / `PICKUP NOT CONFIRMED`: bug, share the full UE4SS log and game build.

## Known limitations

- **Player confirmed cosmetic drops work in a live session**, but also reported a freeze on enemy death using v0.1.0. The FPS hotfix is not yet validated in-game. Actions test syntax and Lua mocks only.
- Killer is not exposed by the reflected `OnCharacterDeath` argument. This alpha picks the nearest living/player character; kills by traps can also count.
- Remote players' saved profiles are not accessible through the host's local `ProfileSaveGame`. Native pickup and replicated `NewCosmeticUnlocks` need a two-player session and reload verification, especially for already owned remote cosmetics.
- Candidate discovery relies on the real runtime CosmeticDataTable and identifying pattern texture/color rows. If the table uses different category names, the log will expose the failure and the filter must be refined.
- The native pickup could enforce an additional Expedition-only or character interaction condition; the version is an intentionally instrumented alpha, not a confirmed stable release.
- No permanent world item is left; the actor is destroyed after success/failure or a bounded verification period.
- Do not enable unrelated cosmetic-drop mods until this build is tested.

## Maintenance

- Edit `CFG.Chance` to change probability (`0.05` = 5%, `1.0` = 100%).
- Run the `test-package` workflow for syntax, mock tests and installation ZIP.
- `inspect-reflection.yml` independently audits actual user-provided mapping and ObjectDump from [Grain-Rot-Mod-Data-Base](https://github.com/SirRosa/Grain-Rot-Mod-Data-Base).
