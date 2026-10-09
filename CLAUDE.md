# Carena

Multiplayer 3D car arena combat game (shooting + traps) in Godot 4.7, GDScript.

## Key decisions

- **3D, arcade physics on `RigidBody3D` with raycast suspension** (`scripts/car.gd`), not `VehicleBody3D`. Jolt physics engine.
  - Each wheel = ray + spring-damper + per-wheel grip/drive forces. Grip/drive applied at axle height so cornering doesn't roll the car; flips come from terrain.
  - Body is vertically symmetric around the axle line and wheels stick out both sides → an upside-down car keeps driving (rays flip side).
  - Network: server simulates the rigid body; clients interpolate. Client-side prediction for rigid bodies is a later, separate problem.
- **Internet multiplayer, up to ~50 players per match.** Target: dedicated headless server, server-authoritative.
  - Clients send only input (`CarInput`); server simulates physics, hits, damage, traps.
  - Never let client code decide game outcomes (HP, kills, pickups).
- **Input is decoupled from simulation.** `Car` consumes a `CarInput` each tick; locally controlled cars fill it from devices, remote/server cars will fill it from the network. Keep this separation for any new controllable entity.

## Conventions

- Scenes in `scenes/`, scripts in `scripts/`. Typed GDScript (`:=`, typed args/returns), tabs for indentation.
- Car front faces `-Z`.
- Input actions are prefixed `car_` (defined in `project.godot`).

## Running

- Play: `godot --path .` (or open in editor, F5).
- Import: `godot --headless --import`.
- Project check (all scripts compile, all scenes load without engine errors): `godot --headless --script res://tools/check_project.gd`.
- Tests (gdUnit4, vendored in `addons/gdUnit4`): `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh --headless --ignoreHeadlessMode -a tests`.
- Lint/format (gdtoolkit): `uvx --from gdtoolkit==4.5.0 gdlint scripts tests tools` and `... gdformat scripts tests tools`.
- CI (`.github/workflows/ci.yml`) runs all of the above on push to main and on PRs. Keep it green: run tests + lint before committing.

## Testing

- Tests live in `tests/`, named `*_test.gd`, extend `GdUnitTestSuite`.
- Car physics tests drive the real `scenes/main.tscn` by setting `car.input` and stepping physics frames; they depend on the arena layout (spawn point, ramp position). If you move the ramp or spawn, update the tests.
- When changing driving feel, keep the behavioural guarantees covered by tests (settles at rest, jumps ramp and lands, no roll when cornering on flat, drives on roof, tips off its side, reset).
