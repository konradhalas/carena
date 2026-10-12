# Carena

Multiplayer 3D car arena combat game (shooting + traps) in Godot 4.7, GDScript.

## Key decisions

- **3D, arcade physics on `RigidBody3D` with raycast suspension** (`scripts/car.gd`), not `VehicleBody3D`. Jolt physics engine.
  - Each wheel = ray + spring-damper + per-wheel grip/drive forces. Grip/drive applied at axle height so cornering doesn't roll the car; flips come from terrain.
  - Handling: ~40 m/s top speed, rear wheels counter-steer at low speed (fading out by ~12 m/s). Stability comes from the grip balance: rear tyres hold `rear_grip_bias` × the fronts, so an over-ambitious turn pushes the nose wide (understeer) instead of spinning. `max_cornering_accel` is only a loose safety net on steering angle (lifted while drifting) — an earlier version capped it at real-tyre levels and made the car nearly unsteerable at speed; a test now requires a <18 m radius at 25 m/s. An ESP-like yaw limiter (`_assist_stability`) damps yaw beyond what the steering asks for, outside drifts. Drift model (`_update_drift`): handbrake locks only the rear wheels and breaks their grip (+ a yaw kick into the turn); a slide held on throttle above `drift_hold_slip` keeps an existing drift going (it must never start one — ordinary fast corners keep grip, there is a test); grip recovers otherwise; yaw is damped beyond `spin_out_slip` so drifts don't become spins. Tests cover top speed, tight turns and drift entry/hold/recovery.
  - Body is vertically symmetric around the axle line and wheels stick out both sides → an upside-down car keeps driving (rays flip side).
  - Network: server simulates the rigid body; clients interpolate. Client-side prediction for rigid bodies is a later, separate problem.
- **Internet multiplayer, up to ~50 players per match.** Target: dedicated headless server, server-authoritative.
  - Clients send only input (`CarInput`); server simulates physics, hits, damage, traps.
  - Never let client code decide game outcomes (HP, kills, pickups).
- **Networking** (`scripts/network.gd` autoload `Network`, `scripts/game.gd`, `scenes/game.tscn`):
  - ENet (UDP), port 7777. Transport is created only in `Network.open_connection()` — a web build would swap ENet for WebSocket/WebRTC there.
  - Modes: host (listen server, plays too), client, dedicated server (`--server`, headless). Menu (`scenes/menu.tscn`) is the main scene; `scenes/sandbox.tscn` is offline driving (also used by tests).
  - The game scene opens the connection itself (after its `MultiplayerSpawner` exists), so replicated spawns always have a target node.
  - Server spawns one car per peer via `PlayerSpawner` (`spawn_function` runs on every peer); car node name = peer id.
  - Car: server is authoritative. State replicates through the car's `Sync` node (`net_*`, ~30 Hz) tagged with the server physics tick (`net_tick`) and the last owner input the server applied (`net_input_seq`).
  - Own car on a client = **client-side prediction** (`scripts/net/prediction_reconciler.gd`): the client simulates it immediately with its own input, sends numbered inputs (each packet repeats the previous 2, `_submit_inputs`, sender validated against `owner_peer_id`), and reconciles against server state for the same input seq: small errors blend in, large ones (> 4 m, e.g. respawn) snap. No rewind/replay — history is shifted instead.
  - Server consumes exactly one queued input per physics tick (`_consume_queued_input`) so its steps line up with the client's; it skips ahead if the queue grows past 4. Don't go back to "apply latest input" — that made predictions disagree by one tick whenever packets bunched up.
  - Remote cars on a client = **snapshot interpolation** (`scripts/net/snapshot_buffer.gd`): frozen kinematic bodies rendered ~6 ticks in the past (`NetClock.render_tick()`), interpolating between snapshots; brief extrapolation only when snapshots run out.
  - `NetClock` (static, not the autoload) estimates the server tick, so `Car` doesn't depend on the `Network` autoload (scripts run via `--script`, including gdUnit, have no autoloads).
  - **Physics interpolation is on** (project setting). Anything moved in `_physics_process` renders smoothly; after teleporting or spawning a node at a position, call `reset_physics_interpolation()` or it streaks.
  - Offline, Godot's default OfflineMultiplayerPeer makes the local peer the server, so the same car code runs unchanged in sandbox/tests.
- **Combat** (`scripts/projectiles.gd`, `scripts/effects.gd`, combat section of `scripts/car.gd`): a slow heavy cannon — 25 damage (4 hits kill), ~2 shots/s, 60 m/s shells with slight drop, big shove on hit, recoil, gyro-stabilised elevation (barrel pitch low-pass-follows body pitch, so squat/dive/bumps don't send shells into the dirt; `aim_direction()`); 12-round magazine (`ammo`, replicated) refilled on respawn. Pickups (`scenes/pickup.tscn`, `scripts/match/pickup.gd`, placed under `Arena/Pickups`): repair kit (+40 HP) and ammo crate (+6), server hands them only to cars that need them, back after 15 s; `active` replicates, collection announced by RPC.
  - Weapon fires from the `Muzzle` marker on the front bumper at axle height — the car's centre of symmetry — along the car's forward axis, so it works identically on wheels or roof. Keep any future weapon/trap attachment points symmetric for the same reason.
  - Server simulates projectiles as data (ray segment per tick) and alone applies damage (`Car.apply_damage`) and kill credit. Clients get an unreliable "shot fired" RPC and animate visual-only tracers.
  - `health`, `kills`, `is_destroyed` replicate on change; `is_destroyed` setter drives wreck visuals/explosion on every peer. Wrecks ignore input and respawn at `spawn_transform` after `respawn_delay`.
  - `Effects` are visual only and no-op on headless servers — never put gameplay logic in them.
  - `--bot` uses `BotDriver` (chase nearest car, shoot when lined up, back out when stuck).
- **Arena look** (monster-truck show in a plain indoor hall): the dirt floor is a deterministic heightmap (`scripts/arena/arena_terrain.gd`, `ArenaTerrain`: bumps, wall berms, mounds, jump kicker; flat under containers) — collision is built on every peer incl. the server, use `height_at()` for spawn heights. Procedural materials in `materials/`. Obstacles are shipping containers (`scenes/shipping_container.tscn`). Hall shell, concrete floor strips around the arena, roof-hung floodlights and the jumbotron come from `scripts/arena/arena_dressing.gd` (`@tool`, visual only, skipped on headless). No stands or truss — the user preferred a plain hall, and truss shadows on the dirt read as noise.
- **Arena look** (monster-truck stadium): procedural materials in `materials/` (noise/gradient textures, triplanar — no imported image assets yet). Obstacles are shipping containers (`scenes/shipping_container.tscn`, colour via `color` export) grouped in the arena scene. Stands, wall caps and floodlights come from `scripts/arena/arena_dressing.gd` (`@tool`, visual only, skipped on headless servers).
- **Rendering** (Forward+, desktop only for now): indoor hall lit by truss floodlights through volumetric fog, AgX tonemapping, SSAO + SSIL, SSR, a box-projected reflection probe, debanding. SDFGI was tried and dropped: ~35% of frame time and artifacts after fast camera moves, with little visible gain over SSIL here. The hall shell (roof, outer walls) casts no shadows so the overhead fill light reaches inside. Measured ~145 fps at 1600×900 on the dev Mac. A web build would need the Compatibility renderer, which has none of this.
- When judging visuals from screenshots, look at full-resolution frames: ImageMagick montages quantize dark gradients and show banding that isn't in the game.
- **Car look**: narrow chamfered chassis (`MeshBuilder`) painted by `shaders/car_paint.gdshader` (livery from local position; colours picked from `Car.LIVERIES` by hashing the node name = peer id, so all peers agree without network traffic), rounded lathe tyres, buggy-style visual suspension (`scripts/car_suspension.gd`: double wishbones + coil-over per wheel following wheel travel; sprung chassis lean/squat/dive/sag from acceleration). Everything on the car — body, lights, muzzle, suspension — must stay mirror-symmetric top/bottom about the axle line, because the car drives on its roof too.
- **Feel / juice**: `Car.damaged` fires on every peer when health drops (health replicates). The follow camera shakes from target acceleration spikes (landings, crashes, explosions) and damage, and widens FOV with speed; the HUD flashes red on damage. `Effects` has muzzle flash, impact sparks (along the hit normal) and explosion fireball + debris + smoke — all visual only, skipped on headless.
- **Audio**: all sounds are synthesised by `tools/audio/generate_sounds.py` (`uv run tools/audio/generate_sounds.py` → `assets/audio/*.wav`; tweak there, not in an editor). Loops (engine, skid) have `edit/loop_mode=2` in their `.import` files — after changing import params, delete the matching `.godot/imported/*` files or Godot won't reimport. `Sfx.play_at()` for one-shot 3D sounds; `CarAudio` for engine pitch/volume, tyre scrub and landing thumps. Everything plays on the "World" bus (hall reverb); Master has a limiter. Visual/audio code is skipped on headless servers.
- To hear changes without playing: record with Movie Maker, e.g. `godot --path . --write-movie out.avi --fixed-fps 60 --script res://<scenario>.gd`.
- **Ground effects** (`scripts/effects/`): `CarEffects` (created by `Car`, not on headless) gets per-wheel contact data from the wheel probes on every peer and lays tyre marks into the level's `TireTracks` (group `tire_tracks`, chunked MultiMesh ring buffer in the arena scene; marks fade out in `shaders/tire_tracks.gdshader` after `lifetime`) and drives rear-wheel dust particles from speed and sideways slip. Visual only — no network traffic.
- **Match loop** (`scripts/match/match_state.gd`, node `MatchState` in `scenes/game.tscn`): server-authoritative players/names, kills/deaths, clock and cycle (play until `time_limit` or `kill_limit` → results for `results_duration` → reset and respawn everyone). Replicated via its `Sync` child (reassign `scores` to replicate — in-place edits aren't detected); kills announced by RPC for the kill feed. Clients send their nickname with `_register_name` right after connecting. Cars in a match get `spawn_protection` (2 s, blinking); the sandbox leaves it at 0 so tests and target practice work. Server overrides: `--match-time=`, `--kill-limit=`. Effects/sounds must never be parented under `Players` (spawner-managed, cars only) — use the scene root.
- **Input is decoupled from simulation.** `Car` consumes a `CarInput` each tick; locally controlled cars fill it from devices, remote/server cars will fill it from the network. Keep this separation for any new controllable entity.
- **Website** (`web/`): static landing page (plain HTML, no build) for https://carena.konradhalas.pl/, deployed by Vercel with Root Directory = `web`. Screenshots in `web/img/` come from `tools/capture_screenshots.gd` (two bots in the sandbox; needs `--bot`, see the script header) — pick the good frames and convert to JPEG.

## Conventions

- Scenes in `scenes/`, scripts in `scripts/`. Typed GDScript (`:=`, typed args/returns), tabs for indentation.
- Car front faces `-Z`.
- Input actions are prefixed `car_` (defined in `project.godot`). Fire: left mouse / K / Ctrl; handbrake: Space; reset: R.

## Running

- Play: `godot --path .` (or open in editor, F5).
- Multiplayer locally: `godot --path . -- --host` and `godot --path . -- --join=127.0.0.1`; dedicated server: `godot --headless -- --server [--port=N]`.
- Unattended clients: add `--bot` (auto-driving) and `--net-log` (prints every car's position every 2 s) — used to verify replication across processes.
- Netcode smoothness: `tools/net/measure.sh [ONE_WAY_DELAY_MS JITTER_MS]` (e.g. `50 10` ≈ 100 ms RTT, via `tools/net/lag_proxy.py`) prints on-screen jitter for own/remote/offline cars and prediction correction size. Run it before/after touching netcode; smooth ≈ 1–2 % jitter.
- Import: `godot --headless --import`.
- Project check (all scripts compile, all scenes load without engine errors): `godot --headless --script res://tools/check_project.gd`.
- Tests (gdUnit4, vendored in `addons/gdUnit4`): `GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh --headless --ignoreHeadlessMode -a tests`.
- Lint/format (gdtoolkit): `uvx --from gdtoolkit==4.5.0 gdlint scripts tests tools` and `... gdformat scripts tests tools`.
- Release builds: `export_presets.cfg` has Linux, Windows and macOS (universal, ad-hoc signed, not notarized) presets; tests, tools, web and gdUnit4 are excluded. Locally: `godot --headless --export-release "macOS" build/macos/carena-macos.zip` (needs 4.7.2 export templates). Pushing a `v*` tag runs `.github/workflows/release.yml`, which exports all three and publishes a GitHub release (the website's Download button points at the latest one); running it manually only builds artifacts.
- CI (`.github/workflows/ci.yml`) runs all of the above on push to main and on PRs. Keep it green: run tests + lint before committing.

## Testing

- Tests live in `tests/`, named `*_test.gd`, extend `GdUnitTestSuite`.
- Car physics tests drive the real `scenes/main.tscn` by setting `car.input` and stepping physics frames; they depend on the arena layout (spawn point, ramp position). If you move the ramp or spawn, update the tests.
- When changing driving feel, keep the behavioural guarantees covered by tests (settles at rest, jumps ramp and lands, no roll when cornering on flat, drives on roof, tips off its side, reset).
