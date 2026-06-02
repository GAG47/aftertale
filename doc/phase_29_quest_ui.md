# Phase 29 Quest UI

Phase 29 gives quests a dedicated journal screen opened with `J`.

The screen follows the agreed two-column structure:

- Left column: scrollable quest list.
- Each quest list item shows only the quest name and quest summary.
- Right column: scrollable quest details for the selected quest.
- Clicking a quest item updates the right-side detail view.

The quest journal is implemented as `QuestPanel` under `UIRoot`. It reads quest state from `QuestSystem` and quest descriptions from loaded quest definitions. It does not accept quests, complete quests, grant rewards, or mutate world facts.

`InputManager` registers `J` as `quest_toggle`, and `UIRoot` handles opening and closing the panel using the same menu-mode rules as the backpack.

This pass intentionally avoids character/source grouping, publisher labels, reward blocks, or extra list metadata. The left list remains strictly quest name plus quest summary.
