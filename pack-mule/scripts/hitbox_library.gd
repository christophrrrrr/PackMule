class_name HitboxLibrary
extends Resource

## Baked convex-decomposition hitboxes, keyed by .glb path. V-HACD is far
## too slow to run at spawn time (the tub alone is ~3.6 s), so it is
## precomputed once by tools/bake_hitboxes.gd and loaded instantly here.
## Each value is an Array of PackedVector3Array — the convex parts in raw
## model space (StackableObject normalizes them per object size).

@export var entries: Dictionary = {}
