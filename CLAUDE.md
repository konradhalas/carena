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
- Headless check / import: `godot --headless --import`.
