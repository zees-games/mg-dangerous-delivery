extends RefCounted

## Where this game's own files are, wherever this copy of it happens to live.
## A delivered pack mounts at `res://dot_cloud/<id>/<version>/`, so an absolute `res://` path to its own files would resolve against the host project; see docs/design.md.
## Built in, [method rebase] returns what it was passed. Anything holding one of these paths is a `static var`, not a `const`, since [method root] is not knowable at parse time.

## This game's content root: `res://` built in, the mount prefix delivered.
static func root() -> String:
	# new().get_script(), not a self-preload: a script holding itself is never freed at exit.
	var here: Resource = new().get_script()
	return here.resource_path.get_base_dir().get_base_dir()


## Moves one `res://` path onto [method root]. Anything else comes back untouched, and format specifiers survive:
## only the prefix is replaced, so `rebase("res://textures/%s.png") % name` works as before.
static func rebase(path: String) -> String:
	return rebase_onto(path, root())


## [method rebase], against a root given rather than discovered, so the mounted case can be TESTED from a build.
## Built in, every `res://` path is already under [method root], so a suite on rebase alone would pass whatever the body says.
static func rebase_onto(path: String, here: String) -> String:
	if not path.begins_with("res://"):
		return path

	# Idempotent: the publisher rewrites `res://` strings in scenes and resources but not in scripts, so a path may already be under the mount.
	# Rebasing it again doubles the prefix and fails to load; see docs/design.md.
	# Built in, [param here] is `res://` and every path is already under it, so this returns its argument unchanged.
	if path.begins_with(here):
		return path

	return here.path_join(path.substr(6))
