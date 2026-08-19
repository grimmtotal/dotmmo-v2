# CLAUDE.md

Godot 4.7 falling-sand simulation (GDScript). Simulation core lives in
`Scripts/Singletons/SimulationGlobal.gd`, particle definitions in
`Scripts/Singletons/Particles.gd`, rendering in `Scripts/WorldRenderer.gd` +
`Shaders/WorldCells.gdshader`.

## Git workflow

- **Always branch off `main`. Never branch off another feature branch.** The
  owner merges PRs one at a time and expects every PR to be based on and
  targeted at `main` — stacked PRs cause merges to land on the wrong branch.
- If work depends on an unmerged PR, wait for it to merge into `main` first
  (or say so), rather than stacking on its branch.
