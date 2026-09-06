class_name LayoutGrid
extends RefCounted

## The one grid every screen is placed on.
##
## Layout used to be sixty hand-picked numbers. Six overlays sat at six
## unrelated origins — (20,132), (70,30), (90,55), (180,132), (220,92) — and
## inside them headings started at x=24, x=32 or x=38 depending on which screen
## you were looking at, so nothing lined up with anything on the screen before
## it. Panels are placed in columns and rows now, which is what makes two
## different screens feel like one product.
##
## 12 columns x 8 rows over the 1280x720 viewport, chosen so every edge lands on
## a whole pixel: 48px page margin, 84px columns, 66px rows, 16px gutters.
##
##   x(col)  = 48 + col * 100          w(cols) = cols * 100 - 16
##   y(row)  = 40 + row * 82           h(rows) = rows * 82 - 16
##
## Twelve columns divide by 2, 3, 4 and 6, which covers every split the game
## actually uses — two survivor panels, three result tiles, four settings rows.

const VIEWPORT := Vector2(1280.0, 720.0)
const MARGIN := Vector2(48.0, 40.0)
const CELL := Vector2(84.0, 66.0)
const GUTTER := 16.0
const COLS := 12
const ROWS := 8

## Half a gutter. The unit for padding inside a card, so interior spacing is a
## fraction of the grid rather than a new number.
const PAD := GUTTER * 0.5


static func x(col: float) -> float:
	return MARGIN.x + col * (CELL.x + GUTTER)


static func y(row: float) -> float:
	return MARGIN.y + row * (CELL.y + GUTTER)


## Width spanning `cols` columns, gutters included but not trailing.
static func w(cols: float) -> float:
	return cols * (CELL.x + GUTTER) - GUTTER


static func h(rows: float) -> float:
	return rows * (CELL.y + GUTTER) - GUTTER


static func rect(col: float, row: float, cols := 1.0, rows := 1.0) -> Rect2:
	return Rect2(x(col), y(row), w(cols), h(rows))


## The same rectangle expressed relative to a container that itself starts at
## (col, row). Screens build their children in local coordinates, so this keeps
## them on the page grid without every call subtracting the panel origin.
static func inner(origin_col: float, origin_row: float, col: float, row: float, cols := 1.0, rows := 1.0) -> Rect2:
	var outer := rect(col, row, cols, rows)
	return Rect2(outer.position - Vector2(x(origin_col), y(origin_row)), outer.size)


## A row of `count` equal cells inside a span, sharing one gutter between each.
## Used where the divisions are not whole columns — four settings rows, eight
## loadout icons — so they still breathe on the grid's rhythm.
static func slice(span: Rect2, count: int, index: int, gutter := GUTTER) -> Rect2:
	var width := (span.size.x - gutter * float(count - 1)) / float(count)
	return Rect2(span.position + Vector2((width + gutter) * float(index), 0.0), Vector2(width, span.size.y))
