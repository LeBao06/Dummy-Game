class_name Constants
extends Node

# ==========================================
# GLOBAL CONSTANTS
# Central place for values shared across multiple managers, so they can't
# drift out of sync (e.g. HOST_ID previously existed separately in both
# server_manager.gd and vote_manager.gd).
# ==========================================

# --- NETWORK / CONNECTION ---

## Peer ID always assigned to the host by ENet. Used to skip RPCs back to
## self and to identify the host in player_state lookups.
const HOST_ID: int = 1

## Port the host binds to when creating a game server.
const PORT: int = 7000

## Fallback server IP used when no address is supplied (IPv4 localhost,
## for same-machine testing).
const DEFAULT_SERVER_IP: String = "127.0.0.1"

## Max simultaneous peer connections allowed on the host's server.
const MAX_CONNECTIONS: int = 32

# --- LAN ROOM DISCOVERY ---
# Separate from PORT above — discovery runs over raw UDP broadcast,
# independent of the actual ENet game connection.

## Port used for LAN broadcast/response during room discovery.
const DISCOVERY_PORT: int = 7001

## Ping payload clients broadcast to find hosts on the LAN. Hosts listening
## on DISCOVERY_PORT reply only when they receive exactly this string.
const DISCOVERY_PING: String = "ROOM_DISCOVERY_PING"

# --- VOTING ---

## Sentinel value used in place of a peer ID to represent an explicit
## "skip" vote during meetings, instead of casting for a player.
const SKIP_VOTE: int = -1

# --- SCENES --- 
## Scene paths so we don't have to change every code once we named scenes
const WAITING_ROOM = "res://scenes/waiting_room/lobby_scene.tscn"


const GAMEPLAY_SCENE = "res://scenes/gameplay_room/gameplay.tscn"

const SEARCH_LOBBY = "res://scenes/lobby_menu/lobby_menu.tscn"
const MAIN_MENU = "res://scenes/main_menu/main_menu.tscn"
