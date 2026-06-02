# Phase 30 Character UI

This phase adds a dedicated character screen opened with `C`.

The first pass supports the current single-player party while keeping the layout ready for future party members:

- Left rail: selected party member plus locked placeholder slots.
- Left main panel: character portrait area and basic profile card.
- Right panels: base attributes, equipment, and skills.
- Skill rows can be clicked to update the skill detail card.

The character UI is implemented as `CharacterPanel` under `UIRoot`. It reads the controlled character through `UIRoot` and `CharacterEntity.get_summary()`. It does not mutate attributes, equipment, skills, inventory, battle state, or world facts.

`InputManager` registers `C` as `character_toggle`, and `UIRoot` handles opening and closing the panel with the same menu-mode rules as the backpack and quest journal.

The portrait is currently a styled placeholder drawn by the UI script. Later art can replace that drawing without changing the data path or menu routing.
