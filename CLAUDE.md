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
- **Assume every earlier PR is already merged.** The owner merges fast, so
  follow-up work — including fixes to something just shipped — goes on a
  fresh branch off the latest `origin/main` as its own new PR. Never push
  another commit to a branch whose PR is open or merged and expect it to be
  picked up.

## Verifying changes

Godot is not installed here, so nothing is verified by reading it. Download a
headless binary and boot the project before pushing — shader and script errors
are invisible otherwise, and a shader that fails to compile silently falls back
to drawing the raw cell buffer (a solid black world):

```
curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64
./Godot_v4.3-stable_linux.x86_64 --headless --path <copy-of-project> --quit-after 400
```

Work on a copy: 4.3 cannot resolve this project's 4.7 `uid://` autoload
references, so rewrite those to `res://` paths in the copy's `project.godot`
first. Shader errors surface as `SHADER ERROR:` on boot even under the dummy
renderer.
