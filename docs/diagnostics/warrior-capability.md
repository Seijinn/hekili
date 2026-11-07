# Warrior capability diagnostic

This is a one-shot, opt-in read inside Hekili Forever. It does not change recommendations, toggles, or `HekiliDB`. It does not cast, move, click, or send addon messages. It does not record video, keyboard, or mouse input.

It is the evidence step for a later leveling feature. It is not that feature. The leveling mode, when it exists, stays off unless a profile turns it on, and off must keep today's priorities. This command does not add that mode.

Hekili's job here is still coaching: a later level-aware suggestion would say what the register considers worth pressing. That suggestion is not a record of how anyone actually played, including mistakes. A separate imitation model, if one is built later from video and input logs, has to follow the demonstrated actions. Do not relabel a Hekili priority as that play.

## What was verified before this command existed

| Source | Build | Role |
|---|---|---|
| Machine metadata for `Wow.exe` | 1.60.1.70862, product `wowf` | File version only. This repository has not launched that client. |
| Installed addon | Hekili Forever v0.6.1, Interface 16001 | Same TOC line this branch still uses |
| [reckhou/WoWBlzCode](https://github.com/reckhou/WoWBlzCode) `7245053a` | Forever 1.60.1.70658, exported 2026-10-28 | API names and restriction flags used to choose what to call. Older than 70862. Not proof the live functions match. |
| `src/Hekili_Warrior/Warrior.lua` | register in this repo | The only spell and talent ids the diagnostic asks about |

Lua 5.1 is the syntax the headless tests parse. The client's `_VERSION` is recorded only when `issecretvalue` exists and says the global is not secret. It has not been observed in game.

## Run it

1. Back up the installed `Interface\AddOns\Hekili` folder.
2. From this branch, copy `src/Hekili` over that folder. Leave `HekiliDB` in SavedVariables alone. The other `Hekili_*` class folders can stay as they are; this change is in the core addon.
3. Start WoW Forever and log in on a character. The diagnostic does nothing on login.
4. Type `/hekili diag` (or `/hek diag`). One chat line confirms the capture. Recommendations are not refreshed.
5. Write the file to disk with `/reload` or by logging out. The game does not flush SavedVariables at the moment the slash command returns. A crash before reload drops the capture.
6. Open:

`World of Warcraft\_forever_\WTF\Account\<Account>\SavedVariables\Hekili.lua`

The new global is `HekiliDiagnosticDB`. `HekiliDB` is the existing profile and is not written by this command.

Run it again later and the global is replaced. It is not an append-only log.

## How to read a spell row

Each row is one id from `Warrior.lua` (`RegisterAbilities`, `tactical_mastery`, or `RegisterTalents`).

| Field | Meaning |
|---|---|
| `levelLearned` | `C_Spell.GetSpellLevelLearned(id)` when that return is a plain number. A Level Link can change it. It is not proof the spell was bought from a trainer. |
| `isKnown` | `C_SpellBook.IsSpellKnown(id)`. Can be true for a temporary grant that is not in the spellbook. |
| `isInSpellBook` | `C_SpellBook.IsSpellInSpellBook(id)`, documented defaults (spell bank Player, includeOverrides true). Can be true for an override that is not known. |
| `isUsable`, `insufficientPower` | `C_Spell.IsSpellUsable(id)` right now. Stance, rage, cooldown, equipment, and target all affect this. It is not "learned" and not "available at this level". |

`unavailable` means the function was missing, or values were withheld because `issecretvalue` was missing. `unknown` means the function was called and returned nil or a non-scalar. `secret` means `issecretvalue` was true; the raw value is not in the file. A real `false` or `0` is stored as `false` or `0`.

`presence` records whether each named function existed. That map is filled even when values are withheld.

`combatLog` is `omitted`. The 70658 dump marks `COMBAT_LOG_EVENT` as `HasRestrictions` and `C_CombatLogSecure.GetCurrentEventInfo` as `Environment=SecureOnly`. This command does not call them and does not turn on `loadDeprecationFallbacks`.

## What one character cannot tell you

- The trainer level, quest source, or racial list for a different character.
- Whether `levelLearned` is the unlinked trainer level. The API documents a Level Link exception.
- Whether a talent rank other than the one definition spell in `RegisterTalents` exists. Higher rank ids are not in that register.
- Quest rewards and racials. They are not in the Warrior register. The 2026-10-16 protection note names Devastate `403196` and Commanding Shout `403215` as not registered; they are not queried.
- That 70862 matches the 70658 API dump. Compare `build.version`, `build.build`, and `build.interface` in the capture with file version 1.60.1.70862.
- How the player plays. Nothing in this file is a demonstrated action.

`classFile` comes from `UnitClassBase("player")`. If it is not `WARRIOR`, the spell rows are still the warrior register on that character.

## Headless checks

From the repository root, after Lua 5.1 and busted are installed:

```
luac5.1 -p src/Hekili/Diagnostics/WarriorCapability.lua src/Hekili/Options/ChatCommands.lua
busted tests/Forever/warrior_capability_diagnostic_spec.lua
busted tests/Forever/warrior_spec.lua
```

Those tests do not launch WoW. A passing run is not in-game validation.
