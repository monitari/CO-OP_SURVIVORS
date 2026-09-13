class_name DrawProxy
extends Node2D
## A canvas that borrows someone else's brush.
##
## A Node2D can sit at exactly one depth, but a rooftop has parts that belong at
## two: the far parapet is behind everything and the near parapet is in front of
## everything, and they are the same wall described by the same code. Rather
## than split that code across two classes that must be kept agreeing, the
## owner keeps one description of the roof and hands each layer a proxy with a
## painter to call.
##
## It exists for ordering, not for logic. Nothing that decides anything should
## live in a painter — the caller owns the state, and this only says where in
## the stack the result lands.

var painter: Callable
## Redraw every frame. On for layers whose content depends on where the actors
## are — the see-through silhouettes — and off for a wall that only changes when
## the roof itself does.
var live := false


func _process(_delta: float) -> void:
	if live:
		queue_redraw()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
