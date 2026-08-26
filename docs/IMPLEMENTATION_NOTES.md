# Implementation Notes

## 2026-08-26 scaffold rebuild
The earlier package contained mostly prose despite describing code/data that were not present. This rebuild adds actual Godot project files, JSON content and validators. Python content validation is clean; Godot parser/runtime validation is still required on a machine with Godot installed.

Known graybox limitations to address first:
- `move_unit` spell effect currently emits an event but does not choose a direction; movement UX belongs in Milestone 1.
- Explicit direct Heart attack needs a clearer action than stepping onto the Sanctuary tile.
- Commander passives are intentionally generic and simple; mastery sidegrades are content-only for now.
- AI only plays/shapes/passes; creature movement/Commander use should be added after core boot is stable.
- Board visuals are generated UI buttons, not final pixel scenes.
