# Notes for agents

Mitts Off! is a World of Warcraft addon for the WoW Forever client. It warns, without blocking, when someone you are about to invite will or might compete for loot with you or a party member. `README.md` describes it for players; read that first.

## Layout

| Path | Role |
| --- | --- |
| `Rules.lua` | Pure rules. No game API. Builds per class, armor by level, `compare`, `evaluate`, `describe`, `brief`, whisper `hints`, and `R.DEFAULTS` for every tunable rule. |
| `Core.lua` | Game side. Profiles for the player, party and candidates; friend and guild lookup; group finder hooks; whisper and invite warnings; slash commands; saved settings. |
| `Options.lua` | Settings panel (canvas category). Options on the left, live preview of every class spec on the right. |
| `tests/` | `run.lua` runs `rules_spec.lua` and `addon_spec.lua`. `wow_stub.lua` fakes the game API. `harness.lua` is the tiny test framework. |
| `deploy.ps1` | Copies the TOC and the files it lists into the game's AddOns folder. |
| `.github/workflows/` | `tests.yml` (reusable), `ci.yml` (every push and PR), `release.yml` (tags starting with `v`). |

## Commands

- Tests: `lua tests/run.lua`. Lua comes from scoop; in PowerShell run `$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + $env:Path` first.
- Put a build in the game: `./deploy.ps1`. The game copy at `C:\Games\World of Warcraft\_forever_\Interface\AddOns\MittsOff` is generated. Never edit it.
- Tests run on Lua 5.4 or newer. The game runs Lua 5.1, so the three shipped files must stay 5.1 compatible. CI checks that with `luac5.1 -p`.

## How the rules work

Each build wants gear lanes (`physical`, `spell`, `healing`, `tank`) with a certainty: `MAIN`, `MAYBE` (unclear spec, or a tank picking up damage pieces) or `OFF` (offspec). Each class wears one armor type for its level; mail and plate arrive at 40.

Severity for a pair of players:

- `WILL` (red): main spec against main spec, in the same armor, or over cloth spell power.
- `OFFSPEC` (orange): the same, but one side competes through an offspec.
- `MIGHT` (yellow): an unclear spec, or only weapons, cloaks and jewelry at stake.

Decisions the owner made, in order. Do not reverse them without asking:

1. Assume other players roll on anything they can wear and use.
2. Spell power heals and deals damage alike, so casters and healers are one pool.
3. Offspec rolls are expected, because hybrids rarely group in the spec they level as. They get their own colour.
4. Physical and tank gear goes by armor type. A warrior rolls on mail or plate, not on a druid's leather, so "heavier wearers roll down" is off by default. Cloth is the exception: every caster and healer rolls on it.
5. The player's own offspec is never guessed.
6. By default only conflicts involving the player, friends, Battle.net friends or guildmates count, and only their losses count. A stranger's offspec matters when it takes from them, not the reverse.
7. Every one of these is a setting. A new rule needs a key in `R.DEFAULTS`, a checkbox in `Options.lua` `SECTIONS`, and tests. A test fails if the two lists drift apart.

## The client

WoW Forever is Classic gameplay (nine classes, level 60, three talent trees) on the modern retail API, Interface 16001, `WOW_PROJECT_ID` 18, codename Camelot.

- Blizzard's UI source: the `forever` branch of github.com/Gethe/wow-ui-source. Check it before trusting memory of any Blizzard function.
- The group finder is `Blizzard_GroupFinder_VanillaStyle` (load on demand), with `LFGBrowseFrame` and `LFGListingFrame`. It is not retail Premade Groups: there are no applicants. People list themselves, you browse, then whisper or invite. Hooks used: `LFGBrowseSearchEntry_Update`, `LFGBrowseSearchEntryTooltip_UpdateAndShow`, `C_PartyInfo.InviteUnit`.
- Listing data comes from `C_LFGList.GetSearchResultInfo` and `GetSearchResultPlayerInfo` (class, level, `assignedRole`, `lfgRoles`). There is no talent or spec data for other players.
- Specialization APIs report the whole class as one spec. The player's tree is read from `C_Traits` talent groups, ordered by `orderIndex`.
- Values can be "secret" in restricted contexts. Pass anything read from the game through `plain()` before using it.

## Not yet verified in game

- The settings panel has never been seen rendered. Column widths assume a canvas about 630 wide.
- The orange dot is the yellow indicator texture tinted. It may read too close to yellow.
- The dot sits at the top right of a listing row and may overlap other elements.
- Tree detection once read a feral druid as restoration. It now sorts by `orderIndex`; the owner has not confirmed the fix. `/mittsoff status` prints the tree name the client reports.
- Armor at 40 is confirmed only for warriors; the rest follows Classic.

## Releases

- No version has been tagged. The owner asked to hold the first tag until the addon has been tried in game. Do not tag without being asked.
- The tag flow and the CurseForge upload have never run on GitHub. CurseForge stays off until `CF_API_TOKEN` and the TOC project ID exist; see `CONTRIBUTING.md`.
- The rolling `unstable` tag belongs to CI.

## Conventions

- `README.md` is for players only. CI, releases, CurseForge and anything for developers go in `CONTRIBUTING.md`.
- The README has two screenshot placeholders, marked with HTML comments, waiting on images from the owner. Its installation section has no download link yet.
- Writing, in docs and in the UI: plain and brief, sentence-case headings, no em dashes, no taglines or helper text, no fragment pairs.
- No AI attribution in commits or pull requests. Commit and push only when the owner asks.
- The addon was called Dibs until the name turned out to be taken on CurseForge. Saved variables are `MittsOffDB` and `MittsOffCharDB`.
