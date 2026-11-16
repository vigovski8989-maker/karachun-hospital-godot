# Theme + small widget helpers mirroring the 45.x HTML/CSS look (Nunito, blue buttons, dark translucent panels)
class_name UIKit
extends RefCounted

static var _theme: Theme
static var font_600: Font
static var font_800: Font

const C_BTN := Color("#3274b2")
const C_BTN_SH := Color("#1b3f66")
const C_ON := Color("#e08a1e")
const C_RED := Color("#b33333")
const C_GRN := Color("#2a8a3a")
const C_PANEL := Color(0.10, 0.17, 0.23, 0.96)
const C_BAR := Color(15 / 255.0, 25 / 255.0, 32 / 255.0, 0.85)
const C_GOLD := Color("#ffd24a")

static func _font(w: int) -> Font:
	var lat = FontFile.new()
	lat.load_dynamic_font("res://assets/fonts/nunito-latin-%d.woff2" % w)
	var cyr = FontFile.new()
	cyr.load_dynamic_font("res://assets/fonts/nunito-cyrillic-%d.woff2" % w)
	var emo = FontFile.new()
	emo.load_dynamic_font("res://assets/fonts/TwemojiMozilla.ttf")
	var sysf = SystemFont.new()
	sysf.font_names = PackedStringArray(["Noto Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Sans Symbols 2", "DejaVu Sans", "sans-serif"])
	lat.fallbacks = [cyr, emo, sysf]
	return lat

static func theme() -> Theme:
	if _theme: return _theme
	font_600 = _font(600)
	font_800 = _font(800)
	var t = Theme.new()
	t.default_font = font_600
	t.default_font_size = 19
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = C_BTN if k != "pressed" else C_BTN.darkened(0.12)
		if k == "disabled": sb.bg_color = Color(C_BTN, 0.4)
		if k == "focus":
			sb.draw_center = false
		sb.set_corner_radius_all(9)
		sb.border_width_bottom = 3 if k != "pressed" else 1
		sb.border_color = C_BTN_SH
		sb.content_margin_left = 11; sb.content_margin_right = 11
		sb.content_margin_top = 7; sb.content_margin_bottom = 7
		t.set_stylebox(k, "Button", sb)
	t.set_font("font", "Button", font_800)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	var pn = StyleBoxFlat.new()
	pn.bg_color = C_PANEL
	pn.set_corner_radius_all(14)
	pn.border_color = Color(140 / 255.0, 190 / 255.0, 230 / 255.0, 0.25)
	pn.set_border_width_all(1)
	pn.shadow_color = Color(0, 0, 0, 0.45); pn.shadow_size = 10
	pn.content_margin_left = 14; pn.content_margin_right = 14; pn.content_margin_top = 10; pn.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", pn)
	t.set_color("default_color", "RichTextLabel", Color.WHITE)
	t.set_font("bold_font", "RichTextLabel", font_800)
	t.set_font("normal_font", "RichTextLabel", font_600)
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 19)
	var vs = StyleBoxFlat.new(); vs.bg_color = Color(1, 1, 1, 0.25); vs.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", vs)
	t.set_stylebox("grabber_highlight", "VScrollBar", vs)
	var vsb = StyleBoxEmpty.new(); vsb.content_margin_left = 6
	t.set_stylebox("scroll", "VScrollBar", vsb)
	_theme = t
	return t

static func style_btn(b: Button, kind: String) -> void:
	if kind == "": return
	var col = C_ON if kind == "on" else (C_RED if kind == "red" else (C_GRN if kind == "grn" else C_BTN))
	for k in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(k, "Button").duplicate()
		sb.bg_color = col if k != "pressed" else col.darkened(0.12)
		if k == "disabled": sb.bg_color = Color(col, 0.4)
		sb.border_color = col.darkened(0.45)
		b.add_theme_stylebox_override(k, sb)

static func bar_style() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_BAR
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb

static func chip_style(col: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 1; sb.content_margin_bottom = 1
	return sb
