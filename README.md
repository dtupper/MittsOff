# Mitts Off!

Mitts Off! is an addon for the WoW Forever client. When you put together a dungeon group, it is hard to keep track of who will roll against whom for gear. The addon does that for you. It warns you when someone in the group finder, or someone who whispers you while you are listed, will or might compete for loot with you or with a member of your party. It never blocks an invite.

By default it only reports conflicts that involve you, your friends, your Battle.net friends or your guildmates.

## Installation

Unzip the addon so that a `MittsOff` folder sits in `_forever_\Interface\AddOns`, then restart the game.

## Where warnings appear

- **Group finder.** A dot appears on the right of a listing's row. Hover over the row and a tooltip lists the conflicts in words, strongest first.
- **Whispers.** While you are listed in the group finder, a whisper from someone who competes with your group prints a warning in chat. Each sender is mentioned at most once every two minutes.
- **Invites.** When you invite someone the addon saw in the group finder or in a whisper, the warning is repeated in chat, and the invite goes out anyway.

<!-- screenshot: group finder row with its tooltip -->

## What the colours mean

| Colour | Meaning | Example for a feral druid |
| --- | --- | --- |
| Red | They roll on your main spec gear with their main spec. | A rogue: "will compete with you for leather physical gear". |
| Orange | They compete through someone's offspec. | A restoration druid: "will compete with you for leather physical gear (their offspec)". |
| Yellow | Their spec is unknown, or only weapons, cloaks and jewelry are at stake. | A shaman healer: "might compete with you for physical gear (weapons, cloaks, jewelry)". |

A mage gets no mark at all, since nothing a mage wears matters to a feral druid.

A protection warrior sees a retribution paladin in orange, because the paladin's tank offspec wants the same plate, and sees a rogue in yellow, because a tank only sometimes picks up damage pieces.

The addon assumes other players roll on anything they can wear and use, because that is how pickup groups behave. Every such assumption is a setting you can change.

## Settings

Type `/mittsoff` to open the panel, or find Mitts Off! under AddOns in the game's settings window.

<!-- screenshot: settings panel -->

The left side holds the options, and the Defaults button restores them all.

- **Your spec.** The addon reads your talents and your party role to decide what you gear for. "Automatic" shows what it detected. Pick a spec from the list to override it for this character.
- **Who rolls on what.**
  - "Hybrids roll for their other specs"
  - "Casters and healers share spell power gear"
  - "Every caster and healer rolls on cloth"
  - "Heavier armor wearers roll on lighter armor" (off by default)
  - "Plate tanks roll on damage gear"
- **What to mention.**
  - "Unknown specs"
  - "Weapons, cloaks and jewelry"
  - "Only you, friends and guildmates"
- **Where to warn.**
  - "Group finder listings"
  - "Whispers while you are listed"
  - "Chat, when you invite someone"

Everything except the lighter armor option is on by default.

The right side, "Who competes with your group", lists every spec of every class as if that player were invited into your current group. Each row has a coloured dot and a few words on what is at stake, and a grey dot means no conflict. Hover over a row to read the full sentence. The list changes as you tick boxes, so you can see the effect of a rule before you rely on it.

## Slash commands

`/mittsoff` and `/mitts` are the same command.

| Command | Effect |
| --- | --- |
| `/mittsoff` | Opens the settings panel. |
| `/mittsoff strangers` | Switches between warning only about you, friends and guildmates, and warning about everyone. |
| `/mittsoff offspec` | Switches offspec rolls on or off. |
| `/mittsoff whispers` | Switches whisper checks on or off. |
| `/mittsoff spec auto` | Detects your spec from your talents and party role. |
| `/mittsoff spec <name>` | Sets your spec by hand, for example `balance`, `cat`, `bear` or `resto` for a druid. `/mittsoff status` lists the names for your class. |
| `/mittsoff check <class> [tank, healer or dps]` | Shows the warnings a hypothetical player of that class would get, for example `/mittsoff check rogue` or `/mittsoff check mage dps`. |
| `/mittsoff status` | Prints your detected spec, your leading talent tree, the current toggles and the spec names for your class. |

## Limits

The addon guesses. For a player in the group finder it knows the class, level and listed role, and for someone listed alone it also reads their comment. For a whisper it knows the class and whatever role or spec words the message contains, such as "enh shaman lfg". It cannot see their talents or what they will actually roll on, so a warning is a reason to ask, and silence is not a promise. Unclear specs show up in yellow, and you can hide them in the settings.

Armor type follows level, with mail and plate arriving at 40. When the addon does not know someone's level, such as in a whisper, it assumes the same level as yours.
