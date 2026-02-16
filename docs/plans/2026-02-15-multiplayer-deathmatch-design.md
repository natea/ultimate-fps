# Multiplayer FFA Deathmatch Design

## Summary

Add Free-For-All deathmatch multiplayer to the existing single-player FPS game. 2-4 players connect via direct IP to a listen server. Matches end on kill limit or time limit, whichever comes first. Players respawn after a 4-second delay.

## Design Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Mode | FFA Deathmatch | Simple, no team logic needed |
| Architecture | Listen Server | No infrastructure, host plays too |
| Players | 2-4 | Fits existing map sizes |
| Win condition | Kill limit OR time limit | Flexible, guarantees match ends |
| Matchmaking | Direct IP connect + lobby | No external services needed |
| Respawn | 4-second timed respawn | Adds death penalty without frustration |

---

## 1. Network Architecture & Connection Flow

Uses Godot's **ENetMultiplayerPeer** with a listen server. One player hosts (server + player), others connect as clients via IP:port 7777.

### Connection Flow

```
Main Menu -> "Multiplayer" button -> Multiplayer Menu
  +- "Host Game" -> enters lobby as host (creates ENet server on port 7777)
  +- "Join Game" -> enter IP address -> connects as client -> enters lobby
```

### Lobby

- Shows connected players (names + ping)
- Map selector (host only): Arena, Ruins (expandable later)
- Match settings (host only): kill limit (default 20), time limit (default 10 min)
- Host clicks "Start Match" when ready

### New Scripts

- `multiplayer/network_manager.gd` -- Autoload singleton managing ENetMultiplayerPeer, peer tracking, connection signals. Persists across scene changes.
- `multiplayer/lobby.gd` + `lobby.tscn` -- Lobby UI
- `ui/multiplayer_menu.gd` + `multiplayer_menu.tscn` -- Host/Join screen

### Player Identification

Each peer gets a unique ID from Godot's multiplayer API. Players enter a display name in the multiplayer menu, synced to all peers via RPC.

---

## 2. Player Spawning & Synchronization

### Multiplayer Player Adaptation

The existing `player.tscn` is adapted for multiplayer. Only the local player processes input and owns the camera. Remote players are "puppets" receiving synced updates.

Each player node uses `set_multiplayer_authority()` so the owning peer is authoritative.

### Spawn Flow

1. Host starts match -> all peers load the level scene
2. Level has predefined `SpawnPoint` markers (Node3D) scattered across the map
3. `NetworkManager` assigns each peer a spawn point (random, avoiding clustering)
4. Each peer spawns all player instances; only the local one gets input enabled

### Synchronized Properties (via MultiplayerSynchronizer)

- Position and rotation (interpolated on remote peers)
- Current weapon index
- Is crouching / is sprinting (for animation state)
- Health (server-authoritative)

### Local-Only Properties

- Camera and input processing
- HUD updates
- Audio listener
- Recoil / screen shake

### Player Script Changes

- Guard `_input()` and `_unhandled_input()` with `is_multiplayer_authority()`
- Disable camera/audio listener for non-local players
- Shooting triggers an RPC to server for validation

### New Nodes on player.tscn

- `MultiplayerSynchronizer` -- syncs position, rotation, weapon, crouch state
- `MultiplayerSpawner` on the level scene -- handles player instance lifecycle

---

## 3. Combat & Damage

### Authority Model

The host (server) is authoritative for all damage. Clients cannot directly modify another player's health.

### Shot Flow

```
Shooter fires weapon
  -> Local: muzzle flash, sound, recoil (instant feedback)
  -> RPC to server: request_shot(origin, direction, weapon_id)
  -> Server: validates with raycast from reported position/direction
  -> Server: if hit, applies damage to victim
  -> Server -> All peers: apply_hit(victim_id, damage, hit_position, hit_normal)
  -> All peers: play impact effect, update victim health
```

Server re-does the raycast to confirm hits, with small tolerance for latency (~200ms).

### Required RPCs

| RPC | Direction | Purpose |
|-----|-----------|---------|
| `request_shot(origin, direction, weapon_id)` | Client -> Server | Report a shot fired |
| `apply_hit(victim_id, damage, hit_pos, hit_normal)` | Server -> All | Show impact, update health |
| `player_died(victim_id, killer_id)` | Server -> All | Kill feed, scoring |

### Special Weapons

- **Rocket launcher** -- Projectile spawned on server, position synced to all peers. Explosion damage calculated server-side with existing radius/falloff.
- **Grenades** -- Same as rockets: server-spawned RigidBody3D, synced position, server-side explosion.
- **Shotgun** -- Multiple pellet raycasts, all validated server-side.

### Score Tracking

Server maintains `scores: Dictionary` mapping peer IDs to kill counts. Broadcasted on each kill.

---

## 4. Respawning, Scoring & Match Flow

### Death & Respawn

1. Server detects health <= 0 -> broadcasts `player_died(victim_id, killer_id)`
2. Victim enters death state: input disabled, death animation plays, 4-second timer starts
3. During death: "Killed by [PlayerName]" overlay, camera stays on body
4. After timer: server assigns new spawn point (avoiding nearby players), broadcasts respawn
5. Player teleports to spawn, health resets to 100, keeps weapon loadout

### Scoring

- Per-player tracking: kills, deaths
- Kill feed (top-right): "[Killer] killed [Victim]"
- Scoreboard on Tab key: all players sorted by kills, deaths column, ping

### Match Settings

- Kill limit: default 20 (range 5-50)
- Time limit: default 10 minutes (range 3-30 min)

### Match Flow

```
Lobby -> Host clicks Start
  -> All peers load level
  -> 3-second countdown ("Match starts in 3... 2... 1...")
  -> Match active: timer counts down, kills tracked
  -> End condition hit (kill limit OR time expires)
  -> Server broadcasts match_over(winner_id, final_scores)
  -> Results screen (scoreboard + "Player X wins!")
  -> 10-second timer -> return all peers to lobby
```

### Weapon Pickups

No AI kill-based drops. Instead, weapons spawn at fixed map points every 30 seconds, managed by server via `MultiplayerSpawner`.

---

## 5. Maps & UI

### Spawn Points

Each level needs 4-6 `SpawnPoint` nodes (Node3D markers) at spread-out locations. Simple position markers read by `NetworkManager`.

### Initial Maps

- **Arena** -- Enclosed, well-suited for tight FFA
- **Ruins** -- Enclosed with cover, good for deathmatch

Other maps can be added later by placing spawn points.

### New UI Screens

| Screen | File | Purpose |
|--------|------|---------|
| Multiplayer Menu | `multiplayer_menu.tscn` | Host/Join buttons, name entry, IP input |
| Lobby | `lobby.tscn` | Player list, map select, settings, Start button |
| Scoreboard | `scoreboard.tscn` | Tab-toggled overlay: names, kills, deaths, ping |
| Death Screen | `death_screen.tscn` | "Killed by X" during respawn timer |
| Match Results | `match_results.tscn` | Final standings, winner announcement |

### HUD Additions

- Match timer (top center) counting down
- Kill feed with player names
- Scoreboard overlay on Tab

### Main Menu Change

Add "Multiplayer" button alongside "Play" and "Events". Single-player unchanged.

### New File Structure

```
multiplayer/
  network_manager.gd    # Autoload singleton
  match_manager.gd      # Scores, timer, win conditions
  spawn_point.gd        # Simple marker (class_name only)
  lobby.gd + lobby.tscn
  multiplayer_menu.gd + multiplayer_menu.tscn
  scoreboard.gd + scoreboard.tscn
  death_screen.gd + death_screen.tscn
  match_results.gd + match_results.tscn
```

---

## Implementation Order

1. **NetworkManager autoload** -- ENet server/client creation, peer tracking, connection signals
2. **Multiplayer menu + lobby UI** -- Host/Join flow, player list, settings
3. **Player multiplayer adaptation** -- Authority checks, MultiplayerSynchronizer, input guards, remote puppet rendering
4. **Spawn system** -- SpawnPoint nodes on Arena/Ruins, spawn assignment logic
5. **Combat RPCs** -- Server-validated shooting, damage application, hit effects
6. **Match manager** -- Score tracking, kill/time limits, match flow (countdown -> play -> results -> lobby)
7. **Respawn system** -- Death state, timer, respawn assignment
8. **UI overlays** -- Scoreboard, death screen, match results, kill feed updates
9. **Weapon pickups** -- Timed server-spawned pickups on map
10. **Polish** -- Name tags above players, interpolation tuning, disconnect handling
