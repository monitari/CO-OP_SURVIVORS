extends RefCounted
## Translation for the parts of the game that are not a Node.
##
## Godot already translates a Control's own `text` property, which covers every
## caption written once from a literal. It cannot cover the other half of this
## game's text: lines built at runtime ("%s 격파    남은 보스 %d"), strings kept
## in `const` tables in the catalogs, and anything composed inside a `static`
## helper, where `Node.tr()` does not exist. Those all come through here.
##
## The key is always the Korean sentence, exactly as `localization/ui.csv` lists
## it in its first column, so an untranslated key still renders as the original
## Korean rather than as a blank or a symbol.


## One key. Use this for a plain string.
static func t(key: String) -> String:
	if key.is_empty():
		return key
	return TranslationServer.translate(key)


## A key with `%`-arguments. Translate first and format second: the translation
## carries the format specifiers, so a locale is free to move them ("Lv.%d 진화
## %s" against "%s evolves at Lv.%d" would need reordering, which %s cannot do —
## keep the order in that case and reword instead).
static func f(key: String, args: Variant) -> String:
	return TranslationServer.translate(key) % args


## Each entry of a list of keys, in order. Handy for `const` tables of options.
static func each(keys: Array) -> Array[String]:
	var out: Array[String] = []
	for key in keys:
		out.append(TranslationServer.translate(String(key)))
	return out
