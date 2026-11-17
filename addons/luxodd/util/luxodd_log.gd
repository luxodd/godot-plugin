class_name LuxoddLog
extends RefCounted

## Plugin logging. Off unless LuxoddConfig.logs_enabled is set.
## Callers pass lengths, types and status codes, never message or response bodies: those can
## carry the player's email, name, saved data, PIN hashes and the session token.

static var enabled: bool = false


static func info(message: String) -> void:
	if enabled:
		print("[Luxodd] " + message)


## Warnings print even with logs off, so keep them free of payload data.
static func warn(message: String) -> void:
	push_warning("[Luxodd] " + message)
