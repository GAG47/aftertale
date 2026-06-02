# Phase 33 Battle Turn Order And Presentation

This phase improves party battle readability and player control without adding a full formation or animation system yet.

Implemented scope:

- Battle summaries now include an upcoming turn order list.
- The battle HUD shows a left-side action order panel.
- When multiple player-side units are contiguous in the current turn order, the player can choose which of those units acts first.
- Choosing a later player unit promotes it to the current slot while preserving the rest of the contiguous player block behind it.
- Battle actions now have a short presentation delay before turn advancement.
- Character movement is slower in battle so movement can be seen.
- Skill use, damage, healing, and status application trigger simple code-drawn pulse effects on character tokens.

Deferred scope:

- Dedicated animation assets.
- Per-skill visual effect definitions.
- Full initiative manipulation or formation systems.
