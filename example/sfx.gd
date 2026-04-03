extends Node

## Procedural sound effects — no audio files needed.
## Generates all sounds at runtime using AudioStreamWAV.

var _players: Dictionary = {}
var _music_player: AudioStreamPlayer


func _ready() -> void:
	# Pre-generate all sound effects
	_create_sfx("jump", _gen_jump())
	_create_sfx("land", _gen_land())
	_create_sfx("pass", _gen_pass())
	_create_sfx("near_miss", _gen_near_miss())
	_create_sfx("death", _gen_death())
	_create_sfx("tier", _gen_tier())
	_create_sfx("countdown", _gen_countdown())
	_create_sfx("go", _gen_go())
	_create_sfx("menu_select", _gen_menu_select())

	# Music
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.volume_db = -12.0
	add_child(_music_player)
	_music_player.stream = _gen_music()
	# Loop handled by AudioStreamWAV loop settings


func play(sfx_name: String, volume_db: float = 0.0) -> void:
	if _players.has(sfx_name):
		var p: AudioStreamPlayer = _players[sfx_name]
		p.volume_db = volume_db
		p.play()


func start_music() -> void:
	if not _music_player.playing:
		_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func _create_sfx(sfx_name: String, stream: AudioStreamWAV) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Master"
	add_child(player)
	_players[sfx_name] = player


# ── Sound generators ──────────────────────────────────────────────────────────

func _gen_jump() -> AudioStreamWAV:
	# Quick rising pitch sweep
	var samples := 4000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var freq := lerpf(300.0, 800.0, t)
		var envelope := (1.0 - t) * (1.0 - t)
		var val := sin(t * freq * 0.15) * envelope * 0.6
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_land() -> AudioStreamWAV:
	# Low thump
	var samples := 3000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var freq := lerpf(200.0, 60.0, t)
		var envelope := (1.0 - t) * (1.0 - t) * (1.0 - t)
		var val := sin(t * freq * 0.2) * envelope * 0.5
		# Add some noise for texture
		val += (randf() - 0.5) * 0.1 * envelope
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_pass() -> AudioStreamWAV:
	# Quick bright blip
	var samples := 2000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var envelope := (1.0 - t) * 0.8
		var val := sin(t * 1200.0 * 0.12) * envelope * 0.3
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_near_miss() -> AudioStreamWAV:
	# Swoosh + high ding
	var samples := 6000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var envelope := sin(t * PI) * 0.7
		# Swoosh (noise with bandpass feel)
		var noise := (randf() - 0.5) * 2.0
		var swoosh := noise * (1.0 - t) * 0.3
		# High ding
		var ding := sin(t * 2000.0 * 0.1) * envelope * 0.4
		var val := swoosh + ding
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_death() -> AudioStreamWAV:
	# Explosion: noise burst + descending tone
	var samples := 18000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var envelope := (1.0 - t) * (1.0 - t)
		# Heavy noise
		var noise := (randf() - 0.5) * 2.0 * envelope * 0.5
		# Descending bass
		var freq := lerpf(300.0, 40.0, t)
		var bass := sin(t * freq * 0.25) * envelope * 0.5
		var val := noise + bass
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_tier() -> AudioStreamWAV:
	# Ascending fanfare: three notes rising
	var samples := 22050
	var data := PackedByteArray()
	data.resize(samples * 2)
	var notes := [523.0, 659.0, 784.0]  # C5, E5, G5
	for i in range(samples):
		var t := float(i) / float(samples)
		var note_idx := mini(int(t * 3.0), 2)
		var note_t := fmod(t * 3.0, 1.0)
		var freq: float = notes[note_idx]
		var envelope := (1.0 - note_t * 0.5) * (1.0 - t * 0.3)
		# Main tone + octave
		var val := sin(t * freq * 0.14) * 0.4 + sin(t * freq * 0.28) * 0.2
		val *= envelope
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_countdown() -> AudioStreamWAV:
	# Short beep
	var samples := 4000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var envelope := 1.0 if t < 0.7 else (1.0 - (t - 0.7) / 0.3)
		var val := sin(t * 880.0 * 0.14) * envelope * 0.35
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_go() -> AudioStreamWAV:
	# Higher, longer beep
	var samples := 8000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var envelope := 1.0 if t < 0.6 else (1.0 - (t - 0.6) / 0.4)
		var val := sin(t * 1320.0 * 0.14) * 0.3 + sin(t * 660.0 * 0.14) * 0.2
		val *= envelope
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_menu_select() -> AudioStreamWAV:
	# Bright click
	var samples := 2000
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / float(samples)
		var envelope := (1.0 - t) * (1.0 - t)
		var val := sin(t * 1500.0 * 0.12) * envelope * 0.4
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	return _make_stream(data, samples)


func _gen_music() -> AudioStreamWAV:
	# 32-bar synthwave track with arrangement that builds and evolves.
	# Key of C minor. Chord progression: Cm - Fm - Ab - G (i-iv-VI-V)
	var bpm := 128.0
	var bars := 32
	var beat_dur := 60.0 / bpm
	var total_beats := bars * 4
	var sr := 22050
	var samples := int(total_beats * beat_dur * float(sr))
	var data := PackedByteArray()
	data.resize(samples * 2)

	# Chord roots per bar (repeating 4-bar progression)
	var chord_roots := [65.4, 87.3, 103.8, 98.0]  # C2, F2, Ab2, G2
	# Chord triads for arps/pads (octave 4)
	var chord_triads := [
		[261.6, 311.1, 392.0],  # Cm: C4, Eb4, G4
		[349.2, 415.3, 523.3],  # Fm: F4, Ab4, C5
		[415.3, 523.3, 622.3],  # Ab: Ab4, C5, Eb5
		[392.0, 493.9, 587.3],  # G:  G4, B4, D5
	]
	# Lead melody — 2 phrases of 8 bars each, in scale degrees (C minor pentatonic)
	# Values are frequencies. 0.0 = rest.
	var melody_a := [
		523.3, 0.0, 622.3, 523.3, 392.0, 0.0, 311.1, 0.0,  # bar 1-2
		523.3, 622.3, 784.0, 622.3, 523.3, 0.0, 392.0, 0.0,  # bar 3-4
		311.1, 0.0, 392.0, 523.3, 0.0, 622.3, 523.3, 392.0,  # bar 5-6
		311.1, 261.6, 0.0, 311.1, 392.0, 0.0, 0.0, 0.0,      # bar 7-8
	]
	var melody_b := [
		784.0, 0.0, 622.3, 784.0, 932.3, 0.0, 784.0, 622.3,
		523.3, 0.0, 622.3, 0.0, 784.0, 622.3, 523.3, 0.0,
		392.0, 523.3, 622.3, 784.0, 0.0, 622.3, 523.3, 0.0,
		392.0, 311.1, 261.6, 0.0, 311.1, 392.0, 523.3, 0.0,
	]

	for i in range(samples):
		var t := float(i) / float(sr)
		var beat := t / beat_dur
		var bar := int(beat / 4.0)
		var beat_in_bar := fmod(beat, 4.0)
		var section := bar / 4  # 0-7 (8 sections of 4 bars)
		var chord_idx := bar % 4
		var prog_beat := int(beat) % (bars * 4)

		# ── ARRANGEMENT flags based on section ──
		var has_kick := section >= 1
		var has_hat := section >= 2
		var has_snare := section >= 2
		var has_bass := true
		var has_arp := section >= 2 and section != 4
		var has_lead := section >= 3 and section != 4
		var has_pad := section == 0 or section == 4 or section >= 6
		# Section 4 = breakdown (just bass + pad)
		# Section 0 = intro (bass + pad)

		var beat_phase := fmod(beat, 1.0)
		var val := 0.0

		# ── KICK: four-on-floor ──
		if has_kick and beat_phase < 0.12:
			var kt := beat_phase / 0.12
			var kf := lerpf(160.0, 45.0, kt)
			val += sin(kt * kf * 0.6) * (1.0 - kt) * 0.32

		# ── SNARE: beats 2 and 4 ──
		if has_snare:
			var snare_hits := [1.0, 3.0]
			for sh in snare_hits:
				var sd: float = beat_in_bar - sh
				if sd >= 0.0 and sd < 0.1:
					var st := sd / 0.1
					val += (randf() - 0.5) * (1.0 - st) * 0.22
					val += sin(st * 200.0 * 0.4) * (1.0 - st) * 0.12

		# ── HI-HAT: 8th notes, open on offbeats ──
		if has_hat:
			var eighth_phase := fmod(beat * 2.0, 1.0)
			var is_offbeat := int(beat * 2.0) % 2 == 1
			var hat_decay := 8.0 if not is_offbeat else 3.0
			var hat_env := clampf(1.0 - eighth_phase * hat_decay, 0.0, 1.0)
			val += (randf() - 0.5) * hat_env * (0.06 if not is_offbeat else 0.09)

		# ── BASS: root note, saw+sine with rhythmic gate ──
		if has_bass:
			var root: float = chord_roots[chord_idx]
			# 8th note rhythm with accent on beat
			var eighth_beat := fmod(beat * 2.0, 1.0)
			var bass_gate := clampf(1.0 - eighth_beat * 2.5, 0.0, 1.0)
			# Accent pattern: strong on 1, medium on others
			var accent := 1.0 if fmod(beat, 1.0) < 0.05 else 0.7
			var bphase := fmod(t * root, 1.0)
			var bsaw := (bphase * 2.0 - 1.0) * 0.22
			var bsine := sin(t * root * TAU) * 0.2
			# Sub bass (one octave down)
			var sub := sin(t * root * 0.5 * TAU) * 0.15
			val += (bsaw * 0.4 + bsine * 0.6 + sub) * bass_gate * accent

		# ── PAD: soft chord, triangle-ish wave ──
		if has_pad:
			var pad_vol := 0.04
			for note_idx in range(3):
				var pfreq: float = chord_triads[chord_idx][note_idx] * 0.5  # octave 3
				var pphase := fmod(t * pfreq, 1.0)
				# Triangle wave
				var tri := abs(pphase * 4.0 - 2.0) - 1.0
				val += tri * pad_vol
			# Slight detuned copy for width
			for note_idx in range(3):
				var pfreq: float = chord_triads[chord_idx][note_idx] * 0.501
				var pphase := fmod(t * pfreq, 1.0)
				var tri := abs(pphase * 4.0 - 2.0) - 1.0
				val += tri * pad_vol * 0.7

		# ── ARP: 16th note arpeggiated chord with filter sweep ──
		if has_arp:
			var sixteenth := fmod(beat * 4.0, 1.0)
			var arp_gate := clampf(1.0 - sixteenth * 4.0, 0.0, 1.0)
			var arp_idx := int(fmod(beat * 4.0, 6.0)) % 3  # cycle through triad
			var afreq: float = chord_triads[chord_idx][arp_idx]
			# Alternate octave on some notes
			if int(beat * 4.0) % 4 == 3:
				afreq *= 2.0
			# Filter sweep: brightness increases through each 4-bar section
			var section_phase := fmod(float(bar), 4.0) / 4.0
			var brightness := 0.3 + section_phase * 0.5
			# Square-ish wave with variable pulse width
			var aphase := fmod(t * afreq, 1.0)
			var pulse := 1.0 if aphase < (0.3 + brightness * 0.2) else -1.0
			var arp_sine := sin(t * afreq * TAU)
			var arp_val := (pulse * brightness + arp_sine * (1.0 - brightness)) * arp_gate * 0.08
			val += arp_val

		# ── LEAD MELODY ──
		if has_lead:
			var melody: Array = melody_a if section < 6 else melody_b
			var mel_idx := prog_beat % melody.size()
			# Half-note melody (one note per 2 beats)
			mel_idx = (int(beat / 2.0)) % melody.size()
			var mfreq: float = melody[mel_idx]
			if mfreq > 0.0:
				var mel_phase := fmod(beat / 2.0, 1.0)
				var mel_env := clampf(1.0 - mel_phase * 0.7, 0.3, 1.0)
				# Vibrato
				var vibrato := sin(t * 5.5) * 3.0
				var mphase := fmod(t * (mfreq + vibrato), 1.0)
				# Smooth saw with sine blend
				var msaw := (mphase * 2.0 - 1.0) * 0.5
				var msine := sin(t * (mfreq + vibrato) * TAU) * 0.5
				val += (msaw * 0.4 + msine * 0.6) * mel_env * 0.1

		# ── FINAL MIX: soft clip ──
		val = clampf(val, -0.85, 0.85)
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sr
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	return stream


func _make_stream(data: PackedByteArray, samples: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.data = data
	return stream
