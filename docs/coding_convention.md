# Code Convention

This document exists because several real bugs have already slipped in from the
same handful of patterns: guessing a dictionary key name, calling an `@rpc`
function directly instead of through `.rpc()`, and writing to another
manager's state from outside it. None of these throw a compile error in
GDScript — they fail silently or at runtime, often only on a second machine.
Read this before touching an autoload manager.

---

## 1. Manager Ownership

Each autoload owns a specific slice of the game. If you need to change
something, find the owner below and call *its* method — don't reach into its
variables directly, even if GDScript lets you.

| Manager | Owns | Does NOT own |
|---|---|---|
| `PlayerManager` | `players_state` (source of truth), all reads/writes to it via setters/getters | Networking, match rules, win conditions |
| `NetworkManager` | Connection lifecycle (host/join), replicating `players_state` to peers, disconnect cleanup | Match state, roles, tasks |
| `ServerManager` | Role assignment, task assignment, task-completion validation | Player state storage, win conditions, sync/broadcast plumbing |
| `TaskManager` | `task_database`, task completion tracking, progress | Which player has which role |
| `GameManager` | The match state machine (`LOBBY → PLAYING → MEETING → VOTING → GAME_OVER`), the single win-condition decision point | Voting logic, task/role assignment |
| `VoteManager` | Meeting/voting flow, tallying | Counting alive players (ask `PlayerManager`), deciding who won (ask `GameManager`) |
| `RoomDiscoveryManager` | LAN room broadcast/search over UDP | The actual ENet game connection |

**Rule of thumb:** if you're about to write `OtherManager.some_dict[key] = value`,
stop — that manager should have a setter. If it doesn't, add one there, don't
bypass it.

---

## 2. State Mutation — Setters Only

`players_state` (and similarly `task_database` / `total_tasks_count`) must
only be written to through `PlayerManager` / `TaskManager` methods. Never
write to the dictionary from another manager.

```gdscript
# ❌ Don't
PlayerManager.players_state[id]["role"] = Enums.Role.IMPOSTOR

# ✅ Do
PlayerManager.set_role(id, Enums.Role.IMPOSTOR)
```

Why this matters in practice: a direct write elsewhere is exactly how a key
gets typo'd or a shape assumption drifts without anyone noticing — see the
`main_game.gd` bug where `data.get("ready", false)` was read from a UI script
that never went through `PlayerManager`, while the actual key was
`"is_ready"`. If every read/write goes through one file, a rename is a
one-line fix instead of a grep-and-pray across the codebase.

If you need a new field on player/task data, add the setter **and** getter to
the owning manager in the same PR that introduces the field.

---

## 3. RPCs — Call Through `.rpc()` / `.rpc_id()`, Never Directly

An `@rpc(...)` annotation does **nothing on its own**. It only marks a
function as callable-over-network; it does not intercept a normal function
call. Calling an `@rpc` function directly just runs it locally — no packet is
sent, no error is raised, and it silently looks like it worked because it
runs the code.

```gdscript
@rpc("authority", "call_local", "reliable")
func _sync_players_state(updated_state: Dictionary) -> void:
    PlayerManager.players_state = updated_state

# ❌ Don't — this ONLY updates state on whichever machine called it.
# Other peers never receive anything, no error is thrown.
_sync_players_state(PlayerManager.players_state)

# ✅ Do — actually sends it over the network (call_local also runs it locally)
_sync_players_state.rpc(PlayerManager.players_state)
```

This exact mistake shipped in `server_manager.gd`'s ready-toggle flow: ready
state updated correctly on the server but never reached other clients.

**Checklist for any function with `@rpc`:**
- [ ] Is it ever invoked with `.rpc()` / `.rpc_id()`? If every call site calls
      it directly, the `@rpc` annotation is dead weight and probably a bug.
- [ ] Does the RPC's own logic re-verify authority (`multiplayer.is_server()`)
	  if it's `any_peer`? Never trust the caller.

### Host-local exception

The host is also a player, but RPCs don't call back to the sender. The
established pattern in this codebase is: **host executes the handler
directly, everyone else gets an RPC.**

```gdscript
if id == Constants.HOST_ID:
	receive_role(assigned_role)          # direct call, host is local
else:
	rpc_id(id, "receive_role", assigned_role)   # network call for real peers
```

Don't replace this with `rpc_id()` looped over every peer including the host,
or with `call_local` + an RPC loop that includes the host's own ID — both
cause the host to process its own data twice / out of order.

---

## 4. Signals — Match the Signature, Don't Assume It

Before connecting a signal to a function, check the signal's declared
parameters. A mismatch compiles fine and fails at runtime with a type error
the first time the signal actually fires.

```gdscript
# network_manager.gd
signal player_disconnected(peer_id: int)

# ❌ Don't — this function expects a Dictionary, the signal emits an int
NetworkManager.player_disconnected.connect(_sync_players_state)

# ✅ Do — connect to a handler with a matching signature,
# or wrap it: .connect(func(id): _handle_disconnect(id))
```

If a signal is added for future UI use and nothing connects to it yet, mark
it explicitly so the "unused signal" warning doesn't get treated as noise to
ignore:

```gdscript
@warning_ignore("UNUSED_SIGNAL")
signal role_assigned(role: Enums.Role)
```

---

## 5. Reset Discipline — Full Reset vs. Round Reset

There are two different kinds of "reset" and they are **not** interchangeable:

| | Clears roster? | When to use |
|---|---|---|
| `PlayerManager.reset_manager()` | Yes — wipes `players_state` entirely | Leaving a game / returning to main menu |
| `PlayerManager.reset_players_for_new_round()` | No — keeps connected players, resets only `is_alive`/`assigned_tasks`/`done_tasks` | Starting a new match while players are still connected |

Calling the full reset at match start deletes every connected player right
before role/task assignment needs them — this was a real crash bug in
`ServerManager.start_match()`. If you're resetting state and players are
still supposed to be in the game afterward, you want the round reset, not the
full one.

---

## 6. Win Conditions — One Resolution Point

`GameManager.end_match(result: Enums.GameResult)` is the **only** place a
match outcome gets decided. Don't resolve win/lose logic inline in
`VoteManager`, a kill ability, a sabotage timer, or a disconnect handler —
call `end_match()` (or the shared elimination-check helper on `GameManager`)
from there instead.

This also means alive/role counting should not be duplicated per-manager.
Use `PlayerManager.get_alive_player_ids()` / `PlayerManager.count_alive_by_role(role)`
rather than writing a local `_count_alive_impostors()` in whatever manager
needs it — a vote-caused death and a disconnect-caused death should be
judged by the exact same parity check.

---

## 7. Comments & Documentation Style

- Code comments are written in **English**, even if discussion in Slack/PRs
  is in Vietnamese.
- Use section-banner comments to divide a file into logical regions, matching
  the existing style in `constants.gd` / `game_manager.gd`:

```gdscript
# ==========================================
# --- SECTION NAME ---
# ==========================================
```

- Every public function that isn't self-explanatory gets a `##` doc comment
  above it explaining *why*, not just *what* — especially for anything
  server-authoritative, since "why does only the server run this" is the
  question that trips people up most.
- If a function exists to work around an engine quirk or a past bug (like the
  host-local RPC pattern above), say so in the comment. Someone will
  "simplify" it back into the bug otherwise.

---

## 8. Naming

- Enums over raw strings — `Enums.Role.IMPOSTOR`, not `"impostor"`. Same for
  `Enums.GameState`, `Enums.GameResult`.
- Private/internal functions and signals prefixed `_` (`_apply_ready`,
  `_resolve_votes`) — anything callable from outside the manager has no
  prefix.
- Dictionary keys used across manager boundaries (`"is_ready"`, `"is_alive"`,
  `"assigned_tasks"`, `"done_tasks"`, `"role"`) are defined once, in
  `PlayerManager`'s default data shape (`local_player_data`). If you need a
  new key, add it there first, then use it everywhere else exactly as
  spelled — don't invent a shorthand (`"ready"`) in a UI script.

---

## 9. Before Opening a PR

- [ ] Any new/changed field on `players_state` or task data has a setter +
      getter on the owning manager — no direct dict access elsewhere.
- [ ] Any new `@rpc` function is actually invoked via `.rpc()`/`.rpc_id()`
      somewhere, and re-checks authority if `any_peer`.
- [ ] Any new signal connection has a handler whose signature matches the
	  signal's declared parameters.
- [ ] If you reset state, confirm which reset you mean (round vs. full) and
	  that it doesn't clear something the next step needs.
- [ ] Win/lose logic funnels through `GameManager.end_match()`, not resolved
      inline.
- [ ] Repeated broadcast loops (`for id in players_state: skip host: rpc_id(...)`)
      should use the shared helper once it exists, instead of a new copy.
