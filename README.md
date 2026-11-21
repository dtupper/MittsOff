# Mitts Off!

Mitts Off! is an addon for the WoW Forever client. When you put together a dungeon group, it is hard to keep track of who will roll against whom for gear. The addon does that for you. It warns you when someone in the group finder, or someone who whispers you while you are recruiting, will or might compete for loot with you or with a member of your party. It never blocks an invite.

By default it only reports conflicts that involve you, your friends, your Battle.net friends or your guildmates.

## Installation

Unzip the addon so that a `MittsOff` folder sits in `_forever_\Interface\AddOns`, then restart the game.

## Where warnings appear

- **Group finder.** A compact badge (`MS`, `OS`, or `?`) appears on the right of a listing's row. Hover over the row for a tooltip listing the conflicts with the gear reason highlighted. A quick dropdown along the bottom of the Group Finder window lets you override your spec, adjust party members, and flip common toggles without leaving the finder.
- **Whispers.** While you are listed in the group finder, or leading a non-full party, an incoming whisper or Battle.net whisper from someone who competes with your group prints a warning in chat. Each sender is mentioned at most once every two minutes unless new information raises the severity.
- **Invites.** When you invite someone the addon saw in the group finder, in a whisper, on your target, in your guild, or on your friend list, the warning is repeated in chat, and the invite goes out anyway.

<!-- screenshot: group finder row with its tooltip -->

## What the badges mean

| Badge | Colour | Meaning | Example for a feral druid |
| --- | --- | --- | --- |
| `MS` | Red | They roll on your main spec gear with their main spec. | `[MS] Stab vs you: leather physical`. |
| `OS` | Orange | They compete through someone's offspec. | `[OS] Tree vs you: leather physical (their offspec)`. |
| `?` | Yellow | Their spec is unknown, a tank wants damage pieces, or only weapons, cloaks and jewelry are at stake. | `[?] Sham vs you: weapons, cloaks, jewelry (their offspec)`. |

A mage gets no badge at all, since nothing a mage wears matters to a feral druid.

A protection warrior sees a retribution paladin as `OS`, because the paladin's tank offspec wants the same plate, and sees a rogue as `?` (`physical (tank damage)`), because a tank only sometimes picks up damage pieces.

The addon assumes other players roll on anything they can wear and use, because that is how pickup groups behave. Every such assumption is a setting you can change.

## Settings

Type `/mittsoff` to open the panel, or find Mitts Off! under AddOns in the game's settings window.

<!-- screenshot: settings panel -->

The left side holds the options, with brief hover tooltips, and the Defaults button restores them all.

- **Your spec.** The addon reads your talents and your party role to decide what you gear for. "Automatic" shows what it detected, and the line below names your leading talent tree. Pick a spec from the list to override it for this character.
- **Who rolls on what.**
  - "Hybrids roll for other specs"
  - "Casters and healers share spell power"
  - "All casters and healers roll on cloth"
  - "Heavier wearers roll on lighter armor" (off by default)
  - "Plate tanks roll on damage gear"
- **What to mention.**
  - "Unknown specs"
  - "Weapons, cloaks and jewelry"
  - "Only you, friends and guildmates"
- **Where to warn.**
  - "Group Finder listings"
  - "Whispers while listed"
  - "Whispers while leading an open group"
  - "Chat, when you invite someone"

Everything except the lighter armor option is on by default.

The right side, "Who competes with your group", lists every spec of every class as if that player were invited into your current group. Each row has a badge and a few words on what is at stake, and a grey box means no conflict. Hover over a row to read every conflict for that spec. Below the list, "Your group" shows current party members and lets you click a member's spec to override it or toggle loot protection for the session.

"Check a player", under Mitts Off! in the AddOns list, checks a class, spec, level range, or your current target and lists every warning that player would get.

## Slash commands

`/mittsoff` and `/mitts` are the same command.

| Command | Effect |
| --- | --- |
| `/mittsoff` | Opens the settings panel. |
| `/mittsoff strangers` | Switches between warning only about you, friends and guildmates, and warning about everyone. |
| `/mittsoff offspec` | Switches offspec rolls on or off. |
| `/mittsoff whispers` | Switches whisper checks while listed on or off. |
| `/mittsoff groupwhispers` | Switches whisper checks while leading an open group on or off. |
| `/mittsoff spec auto` | Detects your spec from your talents and party role. |
| `/mittsoff spec <name>` | Sets your spec by hand, for example `balance`, `cat`, `bear` or `resto` for a druid. `/mittsoff status` lists the names for your class. |
| `/mittsoff check` | Opens the "Check a player" page. |
| `/mittsoff check target` | Checks your current target against your group. |
| `/mittsoff check <class> [role or spec] [level]` | Shows the warnings a hypothetical player of that class would get, for example `/mittsoff check rogue`, `/mittsoff check druid cat` or `/mittsoff check sham enh 35`. |
| `/mittsoff status` | Prints your detected spec, your leading talent tree, your party members, the current toggles and the spec names for your class. |

## Limits

The addon guesses. For a player in the group finder it knows the class, level and listed role, and for someone listed alone it also reads their comment. For a whisper it knows the class and whatever role or spec words the message contains, such as "enh shaman lfg", and carries learned specs into your party while they remain unflagged. It cannot see their talents or what they will actually roll on, so a warning is a reason to ask, and silence is not a promise. Unclear specs show up as `?`, and you can hide them in the settings.

Armor type follows level, with mail and plate arriving at 40. When the addon does not know someone's level, such as in a whisper, it assumes the same level as yours.
