# Hekili Observe

Opt-in session log of what the player cast and what Hekili was showing at that same moment. Recording is off until `/hekobs start`. It does not change recommendations or `HekiliDB`. It does not cast, move, reload, or toggle the combat-log file.

A cast row and a recommendation row are different records. The cast is the action that happened, including a mistake. The recommendation is coaching. Neither is rewritten into the other.

The client file version in use is 1.60.1.70862. API names were chosen from the Forever interface dump 1.60.1.70658. A missing function is stored as `unavailable` and is not called. A secret value is the word `secret`. `loggingCombat = true` does not mean the addon was allowed to read combat-log events. Those events are not registered. `combatLogPermission` is always `not-inferred`.

## Install

1. Back up `Interface\AddOns\Hekili`.
2. Copy this branch's `src/Hekili` over that folder so `Observe\Recommendation.lua` is present. Leave `HekiliDB` on disk alone.
3. Copy `src/Hekili_Observe` to `Interface\AddOns\Hekili_Observe`.
4. Log in. Nothing is recorded yet.

## Arm and stop

- `/hekobs start` or `/hekobs start dungeon-1` (the label is optional, 64 characters, and is only what you typed).
- `/hekobs stop`
- `/reload` or log out to write `WTF\Account\<Account>\SavedVariables\Hekili_Observe.lua`. The global is `HekiliObserveDB`. Stop does not flush. The addon does not reload for you.
- Start again replaces the in-memory session. Reload between sessions if you need to keep the previous file.
- A reload disarms capture. Type start again to record more.
- The combat-log file, if you want it, is still the client's own slash command. This addon only reads `C_ChatInfo.IsLoggingCombat` when that function exists.

The external recorder's one-click start does not arm this addon and does not flush SavedVariables.

## What one session cannot prove

That 70862 still has every 70658 function, that a disk combat log is readable by an addon, or how a different character plays. Spellbook rank evidence remains `/hekili diag`. This log does not repeat that walk.

Learned-versus-shown context in the file is the equipment item ids, the first twelve action-button spells and keys, stance spell ids, integer power changes, and a target-change counter. Names, GUIDs, and chat are not stored.
