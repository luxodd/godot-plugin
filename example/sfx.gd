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
	# Looping synthwave bass line — 4 bars at 130 BPM
	var bpm := 130.0
	var beats_per_bar := 4
	var bars := 4
	var total_beats := bars * beats_per_bar
	var beat_duration := 60.0 / bpm
	var total_seconds := total_beats * beat_duration
	var sample_rate := 22050
	var samples := int(total_seconds * float(sample_rate))
	var data := PackedByteArray()
	data.resize(samples * 2)

	# Bass note pattern (MIDI-ish): C2, C2, Eb2, Eb2, F2, F2, G2, G2, repeat...
	var bass_freqs := [65.4, 65.4, 77.8, 77.8, 87.3, 87.3, 98.0, 98.0,
					   65.4, 65.4, 77.8, 77.8, 87.3, 98.0, 87.3, 65.4]

	for i in range(samples):
		var t := float(i) / float(sample_rate)
		var beat := t / beat_duration
		var beat_idx := int(beat) % bass_freqs.size()
		var beat_phase := fmod(beat, 1.0)

		# Bass synth — saw-ish wave with filter envelope
		var freq: float = bass_freqs[beat_idx]
		var bass_env := clampf(1.0 - beat_phase * 1.5, 0.0, 1.0)
		var phase := fmod(t * freq, 1.0)
		var saw := (phase * 2.0 - 1.0) * 0.3
		# Crude low-pass: mix with sine
		var sine := sin(t * freq * TAU) * 0.25
		var bass := (saw * 0.4 + sine * 0.6) * bass_env

		# Hi-hat pattern on every 8th note
		var eighth := fmod(beat * 2.0, 1.0)
		var hat_env := clampf(1.0 - eighth * 8.0, 0.0, 1.0)
		var hat := (randf() - 0.5) * hat_env * 0.08

		# Kick on beats 1 and 3
		var kick := 0.0
		var beat_in_bar := fmod(beat, 4.0)
		if beat_in_bar < 0.15 or (beat_in_bar >= 2.0 and beat_in_bar < 2.15):
			var kick_t := fmod(beat_in_bar, 2.0) / 0.15
			var kick_freq := lerpf(150.0, 50.0, kick_t)
			kick = sin(kick_t * kick_freq * 0.5) * (1.0 - kick_t) * 0.35

		# Arp synth — 16th note arpeggiated chord
		var sixteenth := fmod(beat * 4.0, 1.0)
		var arp_env := clampf(1.0 - sixteenth * 3.0, 0.0, 1.0) * 0.12
		var arp_notes := [261.6, 311.1, 392.0, 523.3]  # C4, Eb4, G4, C5
		var arp_idx := int(fmod(beat * 4.0, 4.0))
		var arp_freq: float = arp_notes[arp_idx]
		var arp := sin(t * arp_freq * TAU) * arp_env

		var val := bass + hat + kick + arp
		var s := clampi(int(val * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
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
