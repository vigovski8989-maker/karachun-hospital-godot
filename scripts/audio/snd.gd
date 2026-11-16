# Port of sound.js: same synthesized tones, pre-rendered into AudioStreamWAV buffers (no external files)
class_name Snd
extends Node

const RATE := 22050
var on = true
var streams = {}
var players: Array[AudioStreamPlayer] = []
var last_play = {}

const DEFS := {
	"click": [[800, .05, "square", .05, 0, 0]],
	"build": [[200, .08, "square", .1, 0, 0], [150, .1, "square", .1, .1, 0]],
	"cash": [[1200, .08, "triangle", .12, 0, 0], [1600, .15, "triangle", .12, .08, 0]],
	"arrive": [[660, .12, "sine", .08, 0, 0], [880, .15, "sine", .08, .12, 0]],
	"bad": [[300, .4, "sawtooth", .1, 0, .5]],
	"boom": [[80, .6, "sawtooth", .25, 0, .3], [60, .8, "square", .2, .05, .4]],
	"win": [[523, .25, "triangle", .15, 0, 0], [659, .25, "triangle", .15, .15, 0], [784, .25, "triangle", .15, .30, 0], [1046, .25, "triangle", .15, .45, 0]],
	"pa": [[523, .15, "sine", .1, 0, 0], [659, .15, "sine", .1, .15, 0], [784, .25, "sine", .1, .3, 0]],
}

func _ready() -> void:
	for k in DEFS: streams[k] = _render(DEFS[k])
	for i in 6:
		var p = AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

func _render(tones: Array) -> AudioStreamWAV:
	var total = 0.0
	for t in tones: total = maxf(total, float(t[4]) + float(t[1]) + 0.03)
	var n = int(total * RATE)
	var buf = PackedFloat32Array(); buf.resize(n)
	for t in tones:
		var f0: float = t[0]
		var d: float = t[1]
		var typ: String = t[2]
		var v: float = t[3]
		var dl: float = t[4]
		var slide: float = t[5]
		var i0 = int(dl * RATE)
		var ph = 0.0
		var cnt = int((d + 0.02) * RATE)
		for i in cnt:
			var tt = float(i) / RATE
			var f = f0
			if slide > 0: f = f0 * pow(slide, minf(tt / d, 1.0))
			ph += f / RATE
			var x = fmod(ph, 1.0)
			var s = 0.0
			match typ:
				"sine": s = sin(TAU * x)
				"square": s = 1.0 if x < 0.5 else -1.0
				"triangle": s = 4.0 * absf(x - 0.5) - 1.0
				"sawtooth": s = 2.0 * x - 1.0
			var g = v * pow(0.001 / v, minf(tt / d, 1.0)) if tt <= d else 0.0
			var j = i0 + i
			if j < n: buf[j] += s * g
	var bytes = PackedByteArray(); bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * 1.6, -1, 1) * 32000))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

func play(k: String) -> void:
	if not on or not streams.has(k): return
	var now = Time.get_ticks_msec()
	if now - int(last_play.get(k, -1000)) < 60: return
	last_play[k] = now
	for p in players:
		if not p.playing:
			p.stream = streams[k]; p.play(); return
	players[0].stream = streams[k]; players[0].play()
