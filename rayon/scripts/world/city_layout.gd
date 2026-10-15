class_name CityLayout
extends RefCounted
## Street plan of the fictional district (about 600 × 600 m).
##
## A grid of streets: lines at XS (running north–south) and ZS (east–west).
## The east–west line at z = 0 is the wide avenue. A couple of segments are
## removed so some blocks merge (the big courtyard and the drift pad).
## North is -Z. Traffic drives on the right.

const XS: Array[float] = [-260.0, -130.0, 0.0, 130.0, 260.0]
const ZS: Array[float] = [-260.0, -130.0, 0.0, 130.0, 260.0]
const AVENUE_ROW := 2
const ROAD_W := 12.0
const AVENUE_W := 20.0
const SIDEWALK := 4.0
const CURB_H := 0.12
const HALF := 300.0

## Removed street segments, as pairs of grid coordinates.
const REMOVED := [[Vector2i(2, 3), Vector2i(2, 4)], [Vector2i(3, 1), Vector2i(4, 1)]]

const GARAGE_POS := Vector3(-95.0, CURB_H, 30.0)
const GARAGE_APRON := Vector3(-95.0, CURB_H, 18.0)

var nodes: Array[Vector3] = []
var edges: Array[Dictionary] = []          # {a, b, w}
var adj: Array = []                        # node -> Array[int] neighbour ids


func _init() -> void:
	for iz in ZS.size():
		for ix in XS.size():
			nodes.append(Vector3(XS[ix], 0.0, ZS[iz]))
			adj.append([])
	for iz in ZS.size():
		for ix in XS.size():
			if ix + 1 < XS.size() and not _removed(Vector2i(ix, iz), Vector2i(ix + 1, iz)):
				_add_edge(id(ix, iz), id(ix + 1, iz), AVENUE_W if iz == AVENUE_ROW else ROAD_W)
			if iz + 1 < ZS.size() and not _removed(Vector2i(ix, iz), Vector2i(ix, iz + 1)):
				_add_edge(id(ix, iz), id(ix, iz + 1), ROAD_W)


static func id(ix: int, iz: int) -> int:
	return iz * XS.size() + ix


static func grid_of(node_id: int) -> Vector2i:
	return Vector2i(node_id % XS.size(), node_id / XS.size())


func _removed(a: Vector2i, b: Vector2i) -> bool:
	for r in REMOVED:
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return true
	return false


func _add_edge(a: int, b: int, w: float) -> void:
	edges.append({"a": a, "b": b, "w": w})
	adj[a].append(b)
	adj[b].append(a)


func edge_width(a: int, b: int) -> float:
	var ga := grid_of(a)
	var gb := grid_of(b)
	if ga.y == gb.y and ga.y == AVENUE_ROW:
		return AVENUE_W
	return ROAD_W


## Half width of the widest road meeting at a node (for intersection boxes).
func node_half_width(n: int) -> float:
	var g := grid_of(n)
	var hw := ROAD_W * 0.5
	if g.y == AVENUE_ROW:
		hw = AVENUE_W * 0.5
	return hw


## Half width of the road running along a given axis through the node.
func half_width_along(n: int, horizontal: bool) -> float:
	if horizontal:
		return (AVENUE_W if grid_of(n).y == AVENUE_ROW else ROAD_W) * 0.5
	return ROAD_W * 0.5


static func lane_offset(width: float) -> float:
	return 6.0 if width > 15.0 else 3.0


## Lane polyline for driving from node a to node b (right-hand traffic).
func lane_points(a: int, b: int) -> Array[Vector3]:
	var pa := nodes[a]
	var pb := nodes[b]
	var d := (pb - pa).normalized()
	var right := Vector3(-d.z, 0, d.x)
	var off := lane_offset(edge_width(a, b))
	var horizontal := absf(d.x) > 0.5
	var start_cut := half_width_along(a, not horizontal) + 2.0
	var end_cut := half_width_along(b, not horizontal) + 2.0
	return [pa + d * start_cut + right * off, pb - d * end_cut + right * off]


func neighbours(n: int) -> Array:
	return adj[n]


func nearest_node(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in nodes.size():
		if adj[i].is_empty():
			continue
		var dd := Vector2(nodes[i].x - p.x, nodes[i].z - p.z).length_squared()
		if dd < bd:
			bd = dd
			best = i
	return best


## Closest point on the road network: {pos, dir, edge:[a,b], dist}.
## The point is placed in the right-hand lane that best matches `heading`.
func nearest_road_point(p: Vector3, heading := Vector3.ZERO) -> Dictionary:
	var best := {}
	var bd := INF
	for e in edges:
		var pa := nodes[e["a"]]
		var pb := nodes[e["b"]]
		var ab := pb - pa
		var t := clampf((p - pa).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := pa + ab * t
		var dd := Vector2(q.x - p.x, q.z - p.z).length()
		if dd < bd:
			bd = dd
			best = {"a": e["a"], "b": e["b"], "q": q, "w": e["w"]}
	var a: int = best["a"]
	var b: int = best["b"]
	var dir := (nodes[b] - nodes[a]).normalized()
	if heading.length_squared() > 0.01 and heading.dot(dir) < 0.0:
		dir = -dir
		var tmp := a
		a = b
		b = tmp
	elif heading.length_squared() <= 0.01 and (p - best["q"]).dot(Vector3(-dir.z, 0, dir.x)) < 0.0:
		dir = -dir
		var tmp2 := a
		a = b
		b = tmp2
	var right := Vector3(-dir.z, 0, dir.x)
	var pos: Vector3 = best["q"] + right * lane_offset(best["w"])
	return {"pos": pos, "dir": dir, "a": a, "b": b, "dist": bd}


## True if the XZ position lies on a carriageway (not on a block).
func on_road(p: Vector3, margin := 0.0) -> bool:
	for e in edges:
		var pa := nodes[e["a"]]
		var pb := nodes[e["b"]]
		var hw: float = e["w"] * 0.5 + margin
		var minx := minf(pa.x, pb.x) - hw
		var maxx := maxf(pa.x, pb.x) + hw
		var minz := minf(pa.z, pb.z) - hw
		var maxz := maxf(pa.z, pb.z) + hw
		if p.x >= minx and p.x <= maxx and p.z >= minz and p.z <= maxz:
			return true
	return false


## Breadth-first route over the street graph (edges are near-equal length).
func route(from_id: int, to_id: int) -> Array[int]:
	var prev := {from_id: -1}
	var queue: Array[int] = [from_id]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		if n == to_id:
			break
		for m in adj[n]:
			if not prev.has(m):
				prev[m] = n
				queue.append(m)
	var out: Array[int] = []
	if not prev.has(to_id):
		return out
	var cur := to_id
	while cur != -1:
		out.push_front(cur)
		cur = prev[cur]
	return out


## Blocks between streets: [{rect: Rect2 (x, z), cells: [Vector2i...]}].
func blocks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var merged := {}
	# Merge pairs separated by a removed segment.
	for r in REMOVED:
		var a: Vector2i = r[0]
		var b: Vector2i = r[1]
		if a.x == b.x:
			# north–south segment removed → cells on both sides (west / east) merge
			var z := mini(a.y, b.y)
			merged[Vector2i(a.x - 1, z)] = Vector2i(a.x, z)
		else:
			var x := mini(a.x, b.x)
			merged[Vector2i(x, a.y - 1)] = Vector2i(x, a.y)
	var used := {}
	for cz in ZS.size() - 1:
		for cx in XS.size() - 1:
			var c := Vector2i(cx, cz)
			if used.has(c):
				continue
			var cells: Array[Vector2i] = [c]
			if merged.has(c):
				cells.append(merged[c])
				used[merged[c]] = true
			var x0 := INF
			var x1 := -INF
			var z0 := INF
			var z1 := -INF
			for cc in cells:
				x0 = minf(x0, XS[cc.x] + ROAD_W * 0.5)
				x1 = maxf(x1, XS[cc.x + 1] - ROAD_W * 0.5)
				z0 = minf(z0, ZS[cc.y] + (AVENUE_W if cc.y == AVENUE_ROW else ROAD_W) * 0.5)
				z1 = maxf(z1, ZS[cc.y + 1] - (AVENUE_W if cc.y + 1 == AVENUE_ROW else ROAD_W) * 0.5)
			out.append({"rect": Rect2(x0, z0, x1 - x0, z1 - z0), "cells": cells, "key": c})
	return out
