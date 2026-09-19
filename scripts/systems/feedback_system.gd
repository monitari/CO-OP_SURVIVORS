class_name FeedbackSystem
extends Node2D

## All audio is synthesised at runtime — the project ships no sound files — so
## a cue is described by a waveform, a frequency sweep and an envelope rather
## than by a sample. Each distinct cue is rendered once and cached; playback
## reuses a pool of AudioStreamPlayers so a busy fight does not allocate.
##
## **The palette is a cat's, not an oscillator's.** Raw saw and square waves are
## what a synthesiser sounds like when nobody has decided what it is playing,
## and low ones with a wobble on them sound like exactly the rude noise you
## would expect them to. Nothing in the combat palette is a raw oscillator any
## more. What the roof sounds like instead is the things a cat is around: a
## collar bell, glass and chimes, a plucked string of yarn, a paw landing on a
## tile, and — for the two moments that are about looking after each other — an
## actual small mew. Those are built out of partial stacks, a Karplus-Strong
## string and a pair of swept formants, which is also where the richness comes
## from: a bell is four partials dying away at four different rates, and that is
## a sound with an inside, where a sine is a sound with a pitch.
##
## Three more things decide whether the result reads as a game rather than as a
## test tone, and all three live here rather than in the callers.
##
## **Width.** Every cue is rendered twice, a few cents apart, one rendering to
## each channel. Two nearly-identical voices beating against each other is the
## oldest trick there is for making a thin sound full, and for the cues built
## out of noise it also decorrelates the two channels, so a paw landing has a
## width that a mono blip cannot.
##
## **How many cues there are.** An area weapon landing on forty enemies used to
## ask for forty hit cues in one physics tick. Forty copies of the same waveform
## starting within a frame of each other do not sound like forty hits; they sum
## into one loud smeared click. So hits, kills and pickups are *reported* rather
## than played, counted for the tick, and flushed as one cue each that carries
## how many there were in its weight and its pitch.
##
## **Which cues survive.** Everything else goes through a fixed number of voices
## with a priority on each. A downed partner is never lost behind chip damage,
## because when the voices are full the quietest-ranked one is taken rather than
## the newest one dropped.

## 48 kHz, which is what the audio device is almost certainly running at. The
## old 22 kHz meant every stream was resampled on its way out and put its own
## Nyquist at 11 kHz, right in the middle of where a bell's shine lives.
const MIX_RATE := 48000
## The music beds render at half that, deliberately. They are bass and bells
## with nothing above 1 kHz in them, so 24 kHz is transparent for the material —
## and a bed is rendered at the moment the run changes state, where the cost of
## synthesising eight seconds of audio in GDScript is a hitch the player feels.
## Cues are short enough that their cost never shows.
const MUSIC_MIX_RATE := 24000

## An AoE hitting dozens of enemies used to spawn one Label + one Tween per
## hit in the same physics tick. The number is still legible well below this
## many stacked on screen at once, so the rest are simply dropped.
const MAX_DAMAGE_NUMBERS_PER_FRAME := 8

## How many cues may sound at once. Past roughly this many simultaneous voices
## nothing further is *heard* — the additions only raise the noise floor — so
## the cap is not a performance measure, it is what keeps the loudest moments
## legible. Anything arriving over the cap takes the lowest-ranked voice or is
## dropped; see `_acquire_player`.
const MAX_VOICES := 10
## Rank of a cue that names no priority of its own. Low enough that anything
## deliberately marked important outranks it.
const DEFAULT_PRIORITY := 3
## At most this many *different* batched cues are flushed in one physics tick.
## A tick where three weapons land on three enemy types is three impact sounds;
## a fourth is not more information, it is mush.
const MAX_BATCHED_CUES := 3
## How a batch's size turns into loudness and pitch. Deliberately far short of
## linear: eight simultaneous hits should read as one heavier hit, not as one
## eight times louder, so the gain follows a low power of the count and stops
## climbing entirely at the ceiling.
const BATCH_GAIN_EXPONENT := 0.30
const BATCH_GAIN_CEILING_DB := 5.0
## And how far a crowded batch drops in pitch. A pile of hits landing together
## reads as heavier, which is a thing the ear knows about bodies and impacts.
const BATCH_PITCH_DROP := 0.030
const BATCH_PITCH_FLOOR := 0.80

## Cue definition fields:
##   freq    starting frequency in Hz
##   to      sweep target (omitted = steady tone)
##   dur     length in seconds
##   vol     peak amplitude, 0-1, and exactly that: the render is normalised to
##           it, so the number means the same thing whichever generator is used
##   wave    see SHAPES below
##   gap     minimum seconds before this cue may sound again
##   attack  seconds of onset ramp (default ATTACK_DEFAULT)
##   curve   decay exponent; larger is a shorter, sharper tail
##   cut     one-pole low-pass in Hz. The default is high and mostly out of the
##           way: this palette gets its softness from what the waveforms are,
##           not from filtering the life out of them afterwards. Only the cues
##           meant to be felt rather than heard name a low one.
##   tail    seconds of soft reflections after the cue, for the moments that are
##           supposed to ring. Combat cues stay dry so the mix stays tight.
##   detune  cents of spread between the two channels (default DETUNE_DEFAULT)
##   prio    rank for voice stealing (default DEFAULT_PRIORITY)
##
## `gap` is what keeps the mix readable: with two players carrying up to three
## weapons each, six independent cooldowns can land in the same handful of
## frames, and without a floor between repeats the result is mush.
const CUE_PARAMS := {
	# --- combat feedback -----------------------------------------------------
	# The generic impact, for anything with no weapon behind it. Every weapon
	# that does have one lands on its own class below instead.
	"hit": {"freq": 210.0, "to": 168.0, "dur": 0.07, "vol": 0.10, "wave": "pat", "curve": 2.4, "gap": 0.02, "prio": 2},
	"kill": {"freq": 392.0, "to": 588.0, "dur": 0.20, "vol": 0.15, "wave": "bell", "curve": 1.5, "gap": 0.03, "prio": 4},
	"xp": {"freq": 1046.0, "to": 1568.0, "dur": 0.09, "vol": 0.075, "wave": "chime", "curve": 2.2, "gap": 0.02, "prio": 2},
	"level": {"freq": 523.0, "to": 1046.0, "dur": 0.55, "vol": 0.18, "wave": "bell", "curve": 1.1, "attack": 0.008, "tail": 0.22, "prio": 8},
	"warning": {"freq": 330.0, "to": 247.0, "dur": 0.22, "vol": 0.16, "wave": "bell", "cut": 2200.0, "curve": 1.4, "prio": 7},
	"down": {"freq": 196.0, "to": 98.0, "dur": 0.55, "vol": 0.24, "wave": "bell", "cut": 1600.0, "curve": 1.0, "attack": 0.010, "tail": 0.25, "prio": 9},
	# The two cues that are about one cat looking after the other are the two
	# that actually speak. Used nowhere else, so a mew always means the pair.
	"revive": {"freq": 523.0, "to": 880.0, "dur": 0.34, "vol": 0.20, "wave": "mew", "curve": 1.3, "attack": 0.020, "tail": 0.18, "prio": 9},
	# Browsing and committing need to sound different, or a menu that two
	# people drive at once gives no feedback about which of them just acted.
	"select": {"freq": 784.0, "to": 1175.0, "dur": 0.11, "vol": 0.11, "wave": "chime", "curve": 2.0, "prio": 6},
	"reroll": {"freq": 392.0, "to": 784.0, "dur": 0.20, "vol": 0.13, "wave": "pluck", "curve": 1.5, "prio": 6},
	"dash": {"freq": 1400.0, "to": 520.0, "dur": 0.16, "vol": 0.11, "wave": "air", "curve": 2.0, "prio": 4},
	"resonance": {"freq": 659.0, "to": 1318.0, "dur": 0.52, "vol": 0.22, "wave": "chime", "curve": 1.0, "attack": 0.012, "tail": 0.30, "prio": 9},
	"boss": {"freq": 110.0, "to": 73.0, "dur": 0.70, "vol": 0.26, "wave": "bell", "cut": 1200.0, "curve": 0.9, "attack": 0.016, "tail": 0.30, "prio": 9},
	"victory": {"freq": 659.0, "to": 1318.0, "dur": 0.70, "vol": 0.22, "wave": "bell", "curve": 0.9, "attack": 0.014, "tail": 0.35, "prio": 9},

	# --- one per weapon, so a loadout is audible as well as visible ----------
	#
	# These are the *firing* half of a weapon's voice: pitched, sweeping, and
	# long enough to have a shape. The impact classes further down are all
	# short and blunt, which is what keeps the two halves apart — a weapon that
	# sounded the same going out as it does landing tells the pair nothing
	# about whether it connected.
	"weapon_boomerang": {"freq": 588.0, "to": 330.0, "dur": 0.16, "vol": 0.085, "wave": "pluck", "gap": 0.2},
	"weapon_milk": {"freq": 494.0, "to": 294.0, "dur": 0.28, "vol": 0.095, "wave": "air", "gap": 0.4},
	"weapon_homing": {"freq": 660.0, "to": 990.0, "dur": 0.11, "vol": 0.085, "wave": "chime", "gap": 0.07},
	"weapon_lightning": {"freq": 1760.0, "to": 660.0, "dur": 0.085, "vol": 0.08, "wave": "air", "gap": 0.28},
	"weapon_flame": {"freq": 520.0, "to": 240.0, "dur": 0.14, "vol": 0.085, "wave": "air", "gap": 0.08},
	"weapon_frost": {"freq": 1318.0, "to": 1760.0, "dur": 0.18, "vol": 0.08, "wave": "chime", "gap": 0.08},
	"weapon_scythe": {"freq": 880.0, "to": 330.0, "dur": 0.13, "vol": 0.10, "wave": "air", "gap": 0.08},
	"weapon_chain": {"freq": 220.0, "to": 165.0, "dur": 0.20, "vol": 0.095, "wave": "pluck", "gap": 0.08},
	"weapon_orbit": {"freq": 988.0, "to": 740.0, "dur": 0.20, "vol": 0.08, "wave": "chime", "gap": 0.10},
	"weapon_lance": {"freq": 440.0, "to": 1318.0, "dur": 0.15, "vol": 0.095, "wave": "pluck", "gap": 0.08},
	"weapon_mine": {"freq": 294.0, "to": 494.0, "dur": 0.14, "vol": 0.09, "wave": "pluck", "gap": 0.10},
	"weapon_gravity": {"freq": 220.0, "to": 87.0, "dur": 0.30, "vol": 0.12, "wave": "bell", "gap": 0.12},
	"weapon_starpiercer": {"freq": 740.0, "to": 1568.0, "dur": 0.19, "vol": 0.10, "wave": "chime", "gap": 0.08, "prio": 5},
	"weapon_thunder_god": {"freq": 1568.0, "to": 262.0, "dur": 0.26, "vol": 0.12, "wave": "bell", "gap": 0.10, "prio": 5},
	"weapon_supernova": {"freq": 622.0, "to": 117.0, "dur": 0.32, "vol": 0.12, "wave": "bell", "gap": 0.12, "prio": 5},
	"weapon_absolute_zero": {"freq": 1760.0, "to": 880.0, "dur": 0.32, "vol": 0.095, "wave": "chime", "gap": 0.12, "prio": 5},
	"weapon_black_moon": {"freq": 880.0, "to": 131.0, "dur": 0.24, "vol": 0.12, "wave": "bell", "gap": 0.10, "prio": 5},
	"weapon_stigmata": {"freq": 262.0, "to": 784.0, "dur": 0.26, "vol": 0.11, "wave": "pluck", "gap": 0.10, "prio": 5},
	"weapon_celestial": {"freq": 1046.0, "to": 523.0, "dur": 0.34, "vol": 0.095, "wave": "chime", "gap": 0.12, "prio": 5},
	"weapon_judgement": {"freq": 523.0, "to": 1760.0, "dur": 0.22, "vol": 0.11, "wave": "bell", "gap": 0.10, "prio": 5},
	"weapon_ruin_garden": {"freq": 208.0, "to": 588.0, "dur": 0.24, "vol": 0.105, "wave": "pluck", "gap": 0.12, "prio": 5},
	"weapon_event_horizon": {"freq": 147.0, "to": 49.0, "dur": 0.42, "vol": 0.14, "wave": "bell", "cut": 1400.0, "attack": 0.018, "gap": 0.14, "prio": 5},

	# --- the landing half: one per impact class ------------------------------
	#
	# Twenty weapons do not need twenty impact sounds; they need impacts you can
	# tell apart, and nine characters is as many as an ear can hold during a
	# fight. What decides the split is the *material* of the hit rather than the
	# weapon's name, so the roster can grow without the mix getting busier — a
	# new lightning-flavoured weapon joins "zap" and costs nothing.
	"impact_pierce": {"freq": 784.0, "to": 392.0, "dur": 0.07, "vol": 0.085, "wave": "pluck", "curve": 2.6, "gap": 0.02, "prio": 2},
	"impact_slash": {"freq": 1175.0, "to": 494.0, "dur": 0.08, "vol": 0.09, "wave": "air", "curve": 2.4, "gap": 0.02, "prio": 2},
	"impact_zap": {"freq": 2093.0, "to": 880.0, "dur": 0.06, "vol": 0.08, "wave": "chime", "curve": 3.0, "gap": 0.02, "prio": 2},
	"impact_burn": {"freq": 440.0, "to": 262.0, "dur": 0.10, "vol": 0.085, "wave": "air", "curve": 2.0, "gap": 0.02, "prio": 2},
	"impact_chill": {"freq": 1568.0, "to": 1976.0, "dur": 0.09, "vol": 0.07, "wave": "chime", "curve": 2.6, "gap": 0.02, "prio": 2},
	"impact_clank": {"freq": 330.0, "to": 262.0, "dur": 0.09, "vol": 0.095, "wave": "pluck", "curve": 2.4, "gap": 0.02, "prio": 2},
	"impact_blast": {"freq": 196.0, "to": 87.0, "dur": 0.12, "vol": 0.115, "wave": "pat", "cut": 1600.0, "curve": 1.9, "gap": 0.02, "prio": 3},
	"impact_void": {"freq": 165.0, "to": 82.0, "dur": 0.14, "vol": 0.10, "wave": "bell", "cut": 1300.0, "curve": 1.7, "gap": 0.02, "prio": 3},
	"impact_splash": {"freq": 588.0, "to": 330.0, "dur": 0.09, "vol": 0.08, "wave": "pat", "curve": 2.4, "gap": 0.02, "prio": 2},

	# Secondary layers mark delayed phases instead of asking one fire sound to
	# explain an entire multi-stage weapon.
	"mine_blast": {"freq": 165.0, "to": 62.0, "dur": 0.30, "vol": 0.17, "wave": "pat", "cut": 1400.0, "curve": 1.6, "tail": 0.18, "gap": 0.06, "prio": 6},
	"gravity_pull": {"freq": 330.0, "to": 131.0, "dur": 0.40, "vol": 0.09, "wave": "air", "attack": 0.040, "curve": 1.3, "gap": 0.10, "prio": 5},
	"gravity_collapse": {"freq": 110.0, "to": 55.0, "dur": 0.28, "vol": 0.17, "wave": "bell", "cut": 1100.0, "curve": 1.4, "gap": 0.08, "prio": 6},
	"chain_snap": {"freq": 262.0, "to": 1046.0, "dur": 0.13, "vol": 0.11, "wave": "pluck", "curve": 2.0, "gap": 0.07, "prio": 5},

	# --- one per field drop, so a pickup says which pickup it was ------------
	# The reward family is the one place the tails are allowed to ring, which is
	# most of what makes a drop feel like a gift rather than a notification.
	"item_heal": {"freq": 523.0, "to": 784.0, "dur": 0.40, "vol": 0.20, "wave": "mew", "attack": 0.020, "tail": 0.20, "prio": 7},
	"item_magnet": {"freq": 392.0, "to": 1568.0, "dur": 0.36, "vol": 0.18, "wave": "chime", "attack": 0.010, "tail": 0.18, "prio": 7},
	"item_guard": {"freq": 659.0, "to": 988.0, "dur": 0.46, "vol": 0.19, "wave": "bell", "attack": 0.010, "tail": 0.22, "prio": 7},
	"item_frenzy": {"freq": 294.0, "to": 880.0, "dur": 0.40, "vol": 0.19, "wave": "pluck", "tail": 0.16, "prio": 7},
	"item_time_stop": {"freq": 1318.0, "to": 262.0, "dur": 0.72, "vol": 0.20, "wave": "bell", "attack": 0.014, "tail": 0.30, "prio": 7},
	"item_chain_ward": {"freq": 440.0, "to": 988.0, "dur": 0.50, "vol": 0.19, "wave": "pluck", "tail": 0.22, "prio": 7},
	"item_purge": {"freq": 392.0, "to": 131.0, "dur": 0.46, "vol": 0.20, "wave": "air", "attack": 0.010, "tail": 0.20, "prio": 7},
	"item_chest": {"freq": 523.0, "to": 1568.0, "dur": 0.54, "vol": 0.19, "wave": "chime", "attack": 0.010, "tail": 0.24, "prio": 7},
	"chest_open": {"freq": 659.0, "to": 1976.0, "dur": 0.62, "vol": 0.19, "wave": "bell", "attack": 0.012, "tail": 0.30, "prio": 7},

	# --- the leash ------------------------------------------------------------
	#
	# One cue, and it fires when the leash actually reaches its limit.
	#
	# Only the arrival at the leash limit sounds; lower tension bands stay silent.
	"chain_strained": {"freq": 247.0, "to": 330.0, "dur": 0.34, "vol": 0.15, "wave": "pluck", "curve": 1.4, "gap": 1.2, "prio": 7},
	"chain_overcharge": {"freq": 587.0, "to": 880.0, "dur": 0.24, "vol": 0.14, "wave": "chime", "prio": 7},
	"chain_overload": {"freq": 294.0, "to": 98.0, "dur": 0.48, "vol": 0.24, "wave": "bell", "cut": 1500.0, "attack": 0.008, "tail": 0.22, "prio": 9},
	"chain_repaired": {"freq": 659.0, "to": 988.0, "dur": 0.32, "vol": 0.17, "wave": "bell", "attack": 0.010, "tail": 0.16, "prio": 8},
	"boss_enrage": {"freq": 165.0, "to": 82.0, "dur": 0.72, "vol": 0.28, "wave": "bell", "cut": 1300.0, "attack": 0.016, "tail": 0.30, "prio": 9},
}

## Which impact class a weapon's hits land on. A weapon missing from here falls
## back on the generic "hit", which is the right default: an unclassified weapon
## should be quietly ordinary rather than silently mute.
const WEAPON_IMPACT := {
	"boomerang": "clank", "milk": "splash", "homing": "pierce", "lightning": "zap",
	"flame": "burn", "frost": "chill", "scythe": "slash", "chain": "clank",
	"orbit": "pierce", "lance": "pierce", "mine": "blast", "gravity": "void",
	"starpiercer": "pierce", "thunder_god": "zap", "supernova": "blast",
	"absolute_zero": "chill", "black_moon": "void", "stigmata": "slash",
	"celestial": "chill", "judgement": "zap", "ruin_garden": "burn",
	"event_horizon": "void",
}

## Onset ramp for a cue that does not name one. Six milliseconds is short enough
## that a hit still reads as instant and long enough that the waveform is not
## starting from a vertical edge, which is what a click is.
const ATTACK_DEFAULT := 0.006
## And the matching ramp at the other end, so a cue that is still moving when it
## runs out of samples lands on silence rather than on a step.
const RELEASE_TAIL := 0.004
## How far apart, in cents, the two channels are detuned. Small enough that no
## cue sounds out of tune with itself, large enough that the beating between the
## two is what gives an otherwise thin synthesised note its body.
const DETUNE_DEFAULT := 7.0
## Default low-pass, as a multiple of the cue's own top pitch, and the range it
## is allowed to sit in. High on purpose — an earlier pass filtered everything
## down to around a kilohertz in the name of not being harsh, and got mud.
const CUT_MULTIPLE := 6.0
const CUT_MIN := 3200.0
const CUT_MAX := 16000.0

## Waveforms, resolved to an integer once per render so the inner loop is not
## comparing strings forty thousand times.
const SHAPES := {
	"sine": 0, "tri": 1, "square": 2, "saw": 3, "noise": 4,
	"bell": 5, "chime": 6, "pluck": 7, "mew": 8, "pat": 9, "air": 10,
}
const SHAPE_SINE := 0
const SHAPE_TRI := 1
const SHAPE_SQUARE := 2
const SHAPE_SAW := 3
const SHAPE_NOISE := 4
const SHAPE_BELL := 5
const SHAPE_CHIME := 6
const SHAPE_PLUCK := 7
const SHAPE_MEW := 8
const SHAPE_PAT := 9
const SHAPE_AIR := 10

## A struck bell's partials are not whole multiples of its fundamental, which is
## exactly why it sounds like metal and not like an organ. These are the classic
## tubular ratios; the decay column is what does the real work, because the high
## partials dying first is the "ting" settling into a "hum".
const BELL_PARTIALS := [1.0, 2.76, 5.40, 8.93]
const BELL_GAINS := [1.0, 0.42, 0.22, 0.11]
const BELL_DECAYS := [1.0, 2.1, 3.6, 5.4]
## Glass is harmonic where a bell is not, so a chime is bright without the
## clang. This is the pickup and level-up family.
const CHIME_PARTIALS := [1.0, 2.0, 3.0, 4.2, 5.4]
const CHIME_GAINS := [1.0, 0.48, 0.26, 0.13, 0.07]
const CHIME_DECAYS := [1.0, 1.7, 2.6, 3.8, 5.2]
## How much brightness a plucked string keeps on each trip round its delay line.
## Just under one, so every pass rounds another edge off the noise it started
## as — which is the whole of why Karplus-Strong sounds like a string.
const PLUCK_DAMPING := 0.996
## The two formants a small mew moves between, as multiples of the note, and how
## sharp each resonance is. Two moving peaks over a buzz is the cheapest thing
## that reads as a voice rather than as a tone.
const MEW_FORMANTS := [2.6, 5.4]
const MEW_RESONANCE := 0.16

## Looping beds, rendered from note lists the same way cues are rendered from
## sweeps. Entries are [start seconds, frequency, duration, volume, waveform].
const MUSIC_TRACKS := {
	"field": {
		"length": 4.0,
		"notes": [
			[0.0, 440.0, 0.35, 0.05, "sine"], [0.5, 523.25, 0.35, 0.05, "sine"],
			[1.0, 659.25, 0.35, 0.05, "sine"], [1.5, 523.25, 0.35, 0.05, "sine"],
			[2.0, 440.0, 0.35, 0.05, "sine"], [2.5, 659.25, 0.35, 0.05, "sine"],
			[3.0, 392.0, 0.35, 0.05, "sine"], [3.5, 659.25, 0.35, 0.05, "sine"],
		],
	},
	"boss": {
		"length": 3.0,
		"notes": [
			[0.0, 293.66, 0.20, 0.05, "sine"], [0.75, 415.30, 0.20, 0.05, "sine"],
			[1.5, 293.66, 0.20, 0.05, "sine"], [2.25, 415.30, 0.20, 0.05, "sine"],
		],
	},
	# A second field theme appears after odd-numbered boss checkpoints. Its
	# syncopated bell melody stays light without a metronomic low-frequency pulse.
	"moonlight": {
		"length": 8.0,
		"notes": [
			[0.0, 587.33, 0.24, 0.045, "sine"], [0.75, 783.99, 0.18, 0.045, "sine"],
			[1.5, 659.25, 0.30, 0.05, "sine"], [2.5, 880.0, 0.20, 0.045, "sine"],
			[3.25, 739.99, 0.30, 0.05, "sine"], [4.0, 659.25, 0.22, 0.045, "sine"],
			[5.0, 987.77, 0.18, 0.05, "sine"], [5.75, 880.0, 0.26, 0.045, "sine"],
			[6.5, 739.99, 0.28, 0.05, "sine"], [7.25, 587.33, 0.38, 0.05, "sine"],
		],
	},
}

var sound_enabled := true
var music_enabled := true
var damage_numbers_enabled := true
var damage_numbers: DamageNumberField
var damage_numbers_this_frame := 0

var _cue_cooldowns: Dictionary = {}
var _tone_cache: Dictionary = {}
var _music_cache: Dictionary = {}
var _player_pool: Array[AudioStreamPlayer] = []
## Every voice ever created, idle or sounding, which is what the cap counts and
## what a steal picks from.
var _voices: Array[AudioStreamPlayer] = []
## Rank of whatever each voice is currently playing, by instance id.
var _voice_priority: Dictionary = {}
## Cue id to how many times it was reported this physics tick, flushed at the
## end of it as one cue apiece.
var _batched: Dictionary = {}
var _music_player: AudioStreamPlayer
var _current_track := ""
## The synthesiser's own source of randomness, kept off the global one on
## purpose. The noise-based generators draw thousands of values per cue, and a
## cue renders the first time it happens to be played — so sharing the global
## stream would mean the enemy spawn that comes after a lightning bolt depends
## on whether that bolt's waveform had been built yet. Seeded so a given cue
## also renders the same way every launch.
var _noise_source := RandomNumberGenerator.new()


func _ready() -> void:
	_noise_source.seed = 0x6D6F6F6E
	_ensure_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -14.0
	add_child(_music_player)


## Separate SFX and Music buses so the two can be balanced (and later exposed
## as sliders) independently. Created at runtime because the project has no
## bus layout resource to ship.
##
## The SFX bus also carries a limiter, which is the last line of defence behind
## the voice cap and the batching: those two keep the *number* of overlapping
## cues sane, and this keeps the handful that do overlap from summing past full
## scale and clipping — digital clipping being the harshest sound this game is
## capable of making.
func _ensure_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
		if bus_name == "SFX":
			var limiter := _make_limiter()
			if limiter != null:
				AudioServer.add_bus_effect(index, limiter)


func _make_limiter() -> AudioEffect:
	if ClassDB.class_exists("AudioEffectHardLimiter"):
		var limiter: AudioEffect = ClassDB.instantiate("AudioEffectHardLimiter")
		limiter.set("ceiling_db", -1.5)
		limiter.set("pre_gain_db", 0.0)
		return limiter
	return null


func _physics_process(_delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_physics_process(_delta)
	FrameProbe.add(&"feedback", probe_started)


func _probed_physics_process(_delta: float) -> void:
	damage_numbers_this_frame = 0
	_flush_batched()


func _process(delta: float) -> void:
	var probe_started := FrameProbe.mark()
	_probed_process(delta)
	FrameProbe.add(&"feedback", probe_started)


func _probed_process(delta: float) -> void:
	for cue in _cue_cooldowns.keys():
		var remaining: float = float(_cue_cooldowns[cue]) - delta
		if remaining <= 0.0:
			_cue_cooldowns.erase(cue)
		else:
			_cue_cooldowns[cue] = remaining


## Plays a cue now. `gain_db` and `pitch` exist for the batched flush, which
## needs the same rendered waveform to carry a different weight — a stream is
## cached per cue, never per loudness.
func play_cue(cue: String, gain_db := 0.0, pitch := 1.0) -> void:
	if not sound_enabled:
		return
	if _cue_cooldowns.has(cue):
		return
	var params: Dictionary = CUE_PARAMS.get(cue, {})
	if params.is_empty():
		return
	var gap := float(params.get("gap", 0.0))
	if gap > 0.0:
		_cue_cooldowns[cue] = gap
	# Rendered before a voice is asked for, not after. A cue that loses the
	# competition for a voice is still a cue the game will ask for again, and
	# synthesising it here means the first time it *does* win is not also the
	# first time it is built.
	if not _tone_cache.has(cue):
		_tone_cache[cue] = _render_cue(params)
	var player := _acquire_player(int(params.get("prio", DEFAULT_PRIORITY)))
	if player == null:
		return
	player.stream = _tone_cache[cue]
	player.volume_db = -5.0 + gain_db
	player.pitch_scale = pitch
	player.play()


## Convenience wrappers so callers name the thing that happened rather than
## assembling cue ids inline.
func play_item_cue(item_id: String) -> void:
	play_cue("item_" + item_id)


## The impact class a weapon's hits belong to, as a cue id.
static func impact_cue(weapon_id: String) -> String:
	# Cached: this runs once per hit, a few hundred times a tick in a late run,
	# and building "impact_" + family allocated a new string every time.
	var cached: Variant = _impact_cues.get(weapon_id)
	if cached != null:
		return cached
	var family: String = String(WEAPON_IMPACT.get(weapon_id, ""))
	var cue := "hit" if family.is_empty() else "impact_" + family
	_impact_cues[weapon_id] = cue
	return cue


static var _impact_cues: Dictionary = {}


## A hit landed. Reported rather than played, because a single area weapon can
## land forty of these inside one physics tick and forty copies of one waveform
## starting a frame apart do not sound like forty hits — they sound like one
## loud click. The tick's worth is flushed as one cue carrying the count.
func report_hit(weapon_id := "") -> void:
	_report(impact_cue(weapon_id))


## Something died. Same reasoning: a nova clearing a screen is one heavier kill
## sound, not thirty of them.
func report_kill() -> void:
	_report("kill")


## Experience collected. The one most likely to arrive in a stream — a magnet
## pickup drags in every mote on the roof at once.
func report_xp() -> void:
	_report("xp")


func _report(cue: String) -> void:
	if not sound_enabled:
		return
	_batched[cue] = int(_batched.get(cue, 0)) + 1


## One cue per reported group, weighted by how many there were, and only the
## few highest-ranked groups if a tick somehow produced more than that.
func _flush_batched() -> void:
	if _batched.is_empty():
		return
	var cues: Array = _batched.keys()
	if cues.size() > MAX_BATCHED_CUES:
		cues.sort_custom(func(left: String, right: String) -> bool:
			return _priority_of(left) > _priority_of(right))
		cues.resize(MAX_BATCHED_CUES)
	for cue: String in cues:
		var count := int(_batched[cue])
		var gain := minf(BATCH_GAIN_CEILING_DB, 20.0 * log(pow(float(count), BATCH_GAIN_EXPONENT)) / log(10.0))
		var pitch := maxf(BATCH_PITCH_FLOOR, 1.0 - BATCH_PITCH_DROP * float(count - 1))
		play_cue(cue, gain, pitch)
	_batched.clear()


func _priority_of(cue: String) -> int:
	return int((CUE_PARAMS.get(cue, {}) as Dictionary).get("prio", DEFAULT_PRIORITY))


func play_chain_limit(stage: int, previous_stage: int) -> void:
	if stage >= 3 and previous_stage < 3:
		play_cue("chain_strained")


func play_music(track_id: String) -> void:
	if track_id == _current_track:
		return
	_current_track = track_id
	if not music_enabled or not MUSIC_TRACKS.has(track_id):
		_music_player.stop()
		return
	if not _music_cache.has(track_id):
		_music_cache[track_id] = _render_music(MUSIC_TRACKS[track_id])
	_music_player.stream = _music_cache[track_id]
	_music_player.play()


func stop_music() -> void:
	_current_track = ""
	_music_player.stop()


## Re-applies the music toggle without losing which track should be playing,
## so flipping it off and on again resumes the right bed.
func refresh_music() -> void:
	var track := _current_track
	_current_track = ""
	if music_enabled and not track.is_empty():
		play_music(track)
	else:
		_current_track = track
		_music_player.stop()


func show_damage(world_position: Vector2, amount: float, color: Color = Color.WHITE) -> void:
	var probe_started := FrameProbe.mark()
	_probed_show_damage(world_position, amount, color)
	FrameProbe.add(&"damage_numbers (incl)", probe_started)


func _probed_show_damage(world_position: Vector2, amount: float, color: Color) -> void:
	if not damage_numbers_enabled:
		return
	if damage_numbers_this_frame >= MAX_DAMAGE_NUMBERS_PER_FRAME:
		return
	damage_numbers_this_frame += 1
	# One batched field rather than a Label and a Tween per number; see
	# DamageNumberField for what that was costing.
	_number_field().add(world_position, str(int(round(amount))), color)


## Numbers currently floating, for tests and the profiler.
func live_damage_numbers() -> int:
	return damage_numbers.live_count() if damage_numbers != null else 0


func _number_field() -> DamageNumberField:
	if damage_numbers == null:
		damage_numbers = DamageNumberField.new()
		damage_numbers.name = "DamageNumbers"
		add_child(damage_numbers)
	return damage_numbers


## A cue, as a stereo stream: the same note rendered twice a few cents apart,
## one rendering to each channel.
##
## That is the cheapest real richness available here. Two voices slightly out of
## tune beat against each other instead of sitting still, which is the
## difference between a note and a test tone — and for the cues built out of
## noise it also means the two channels are genuinely different, so a paw
## landing has width rather than being a point in the middle of the head.
func _render_cue(params: Dictionary) -> AudioStreamWAV:
	var spread := float(params.get("detune", DETUNE_DEFAULT)) * 0.5
	var left := _render_voice(params, pow(2.0, -spread / 1200.0))
	var right := _render_voice(params, pow(2.0, spread / 1200.0))
	var frames := mini(left.size(), right.size())
	# `vol` is a peak, and it has to be an honest one. These generators do not
	# arrive at the same level for the same amplitude — a plucked string spends
	# most of its energy averaging itself away and lands quiet, while a pair of
	# resonant formants rings and lands twice as loud as it was asked to — so
	# the written volume would otherwise mean something different in every
	# family, and balancing the mix by ear would be balancing the synthesis
	# instead. Measured across both channels together so the stereo image does
	# not shift when one side happens to peak higher than the other.
	var peak := 0.0
	for index in frames:
		peak = maxf(peak, maxf(absf(left[index]), absf(right[index])))
	var trim := float(params["vol"]) / peak if peak > 0.00001 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(frames * 4)
	for index in frames:
		bytes.encode_s16(index * 4, int(_soft_clip(left[index] * trim) * 32767.0))
		bytes.encode_s16(index * 4 + 2, int(_soft_clip(right[index] * trim) * 32767.0))
	return _make_stream(bytes, false, MIX_RATE, true)


## One channel's worth of a cue, at `pitch_ratio` times its written pitch.
##
## Frequency is swept by accumulating phase rather than by evaluating
## sin(TAU * f * t): with a changing f the latter warps the whole waveform
## instead of gliding the pitch.
##
## Everything after the oscillator is what stops a synthesised cue sounding
## synthetic — a ramp on at both ends, a filter that is mostly out of the way,
## and for the cues that are supposed to ring, a few soft reflections so the
## note lands somewhere rather than in a vacuum.
func _render_voice(params: Dictionary, pitch_ratio: float) -> PackedFloat32Array:
	var duration := float(params["dur"])
	var start_freq := float(params["freq"]) * pitch_ratio
	var end_freq := float(params.get("to", params["freq"])) * pitch_ratio
	var volume := float(params["vol"])
	var shape: int = int(SHAPES.get(String(params.get("wave", "sine")), SHAPE_SINE))
	var attack := float(params.get("attack", ATTACK_DEFAULT))
	var decay_curve := float(params.get("curve", 2.0))
	var tail := float(params.get("tail", 0.0))
	var cutoff := float(params.get("cut",
		clampf(maxf(start_freq, end_freq) * CUT_MULTIPLE, CUT_MIN, CUT_MAX)))

	var body_count := maxi(1, int(duration * MIX_RATE))
	var total_count := body_count + maxi(0, int(tail * MIX_RATE))
	var attack_samples := clampi(int(attack * MIX_RATE), 1, maxi(1, body_count - 1))
	var low_pass := 1.0 - exp(-TAU * cutoff / float(MIX_RATE))
	var voice := PackedFloat32Array()
	voice.resize(total_count)

	# Per-shape state. Declared up front rather than inside the branch so the
	# inner loop never allocates and the filters keep their memory across it.
	var phase := 0.0
	var filtered := 0.0
	var noise_state := 0.0
	var string := PackedFloat32Array()
	var string_index := 0
	if shape == SHAPE_PLUCK:
		# The delay line is the string. It is filled with noise once and then
		# spends the whole cue averaging itself smooth, which is a plucked note
		# arriving bright and settling onto its fundamental.
		string.resize(maxi(4, int(float(MIX_RATE) / maxf(20.0, minf(start_freq, end_freq)))) + 2)
		for index in string.size():
			string[index] = _noise_source.randf_range(-1.0, 1.0)
	var formant_low := [0.0, 0.0]
	var formant_band := [0.0, 0.0]

	for index in body_count:
		var progress := float(index) / float(body_count)
		var freq := lerpf(start_freq, end_freq, progress)
		var step := freq / float(MIX_RATE)
		phase = fposmod(phase + step, 1.0)
		var raw := 0.0
		match shape:
			SHAPE_BELL:
				raw = _partial_stack(phase, progress, BELL_PARTIALS, BELL_GAINS, BELL_DECAYS)
			SHAPE_CHIME:
				raw = _partial_stack(phase, progress, CHIME_PARTIALS, CHIME_GAINS, CHIME_DECAYS)
			SHAPE_PLUCK:
				var length := clampi(int(float(MIX_RATE) / maxf(20.0, freq)), 2, string.size() - 1)
				string_index = string_index % length
				var ahead := string[(string_index + 1) % length]
				raw = string[string_index]
				string[string_index] = (raw + ahead) * 0.5 * PLUCK_DAMPING
				string_index += 1
			SHAPE_MEW:
				# A buzz through two moving resonances. The formants open and
				# close across the cue, which is the "ee" turning into "ow".
				var buzz := _saw(phase, step)
				var open := 0.6 + 0.8 * sin(progress * PI)
				for band in 2:
					var centre: float = freq * float(MEW_FORMANTS[band]) * open
					var tuning := 2.0 * sin(PI * clampf(centre, 40.0, 9000.0) / float(MIX_RATE))
					formant_low[band] = float(formant_low[band]) + tuning * float(formant_band[band])
					var high: float = buzz - float(formant_low[band]) - float(formant_band[band]) * MEW_RESONANCE
					formant_band[band] = float(formant_band[band]) + tuning * high
					raw += float(formant_band[band]) * (0.7 if band == 0 else 0.45)
			SHAPE_PAT:
				# A paw on a tile: a short breath of air with a soft pitched
				# thump under it, the thump outliving the air.
				noise_state = lerpf(noise_state, _noise_source.randf_range(-1.0, 1.0), clampf(step * 12.0, 0.05, 1.0))
				raw = noise_state * 1.6 * pow(1.0 - progress, 3.0) + sin(phase * TAU) * 0.9
			SHAPE_AIR:
				# Noise slewed toward the cue's own pitch rather than white.
				# White noise is the same fizz whatever cue it is in; noise that
				# darkens as the sweep falls reads as a movement losing energy.
				noise_state = lerpf(noise_state, _noise_source.randf_range(-1.0, 1.0), clampf(step * 4.0, 0.01, 1.0))
				raw = noise_state * 2.6
			SHAPE_NOISE:
				noise_state = lerpf(noise_state, _noise_source.randf_range(-1.0, 1.0), clampf(step * TAU, 0.02, 1.0))
				raw = noise_state * 2.2
			_:
				raw = _wave_sample(shape, phase, step)
		filtered += low_pass * (raw - filtered)
		var envelope := volume
		if index < attack_samples:
			var rise := float(index) / float(attack_samples)
			envelope *= rise * rise * (3.0 - 2.0 * rise)
		else:
			var fall := float(index - attack_samples) / float(maxi(1, body_count - attack_samples))
			envelope *= pow(1.0 - fall, decay_curve)
		voice[index] = filtered * envelope

	if total_count > body_count:
		_add_tail(voice, body_count)
	# The closing ramp goes on last so it applies to the tail as well, and so
	# whatever the cue was doing when it ran out of samples, it ends on silence.
	var release_samples := clampi(int(RELEASE_TAIL * MIX_RATE), 1, total_count)
	for index in release_samples:
		voice[total_count - 1 - index] *= float(index) / float(release_samples)
	return voice


## A handful of soft reflections at spacings that do not line up into a pitch of
## their own. Not a reverb — just enough for the cue to sound like it happened
## on a rooftop rather than inside the mixer.
func _add_tail(voice: PackedFloat32Array, body_count: int) -> void:
	const TAPS := [0.031, 0.047, 0.071, 0.103]
	const GAINS := [0.30, 0.20, 0.13, 0.08]
	var total := voice.size()
	for tap in TAPS.size():
		var delay := int(float(TAPS[tap]) * MIX_RATE)
		var gain := float(GAINS[tap])
		for index in body_count:
			var at := index + delay
			if at >= total:
				break
			voice[at] += voice[index] * gain


## A stack of partials over one fundamental, each with its own level and its own
## rate of dying away. This is the whole difference between a bell and a beep:
## the ear hears the high partials leave and reads the sound as a physical thing
## with an inside, rather than as a tone that was switched on and off.
func _partial_stack(phase: float, progress: float, ratios: Array, gains: Array, decays: Array) -> float:
	var value := 0.0
	var total := 0.0
	for index in ratios.size():
		var level := float(gains[index]) * exp(-float(decays[index]) * progress * 2.4)
		value += sin(phase * TAU * float(ratios[index])) * level
		total += float(gains[index])
	return value / maxf(0.001, total) * 1.7


func _render_music(track: Dictionary) -> AudioStreamWAV:
	var length := float(track["length"])
	var sample_count := maxi(1, int(length * MUSIC_MIX_RATE))
	var mix := PackedFloat32Array()
	mix.resize(sample_count)

	for entry in track["notes"]:
		var note: Array = entry
		var start := int(float(note[0]) * MUSIC_MIX_RATE)
		var freq := float(note[1])
		var note_samples := int(float(note[2]) * MUSIC_MIX_RATE)
		var volume := float(note[3])
		var shape: int = int(SHAPES.get(String(note[4]), SHAPE_SINE))
		var step := freq / float(MUSIC_MIX_RATE)
		var phase := 0.0
		for offset in note_samples:
			var index := start + offset
			if index >= sample_count:
				break
			phase = fposmod(phase + step, 1.0)
			# Soft attack as well as decay: a hard edge on a looping bed
			# reads as a click every time the note starts.
			var progress := float(offset) / float(note_samples)
			var envelope := minf(1.0, progress * 12.0) * pow(1.0 - progress, 1.5)
			mix[index] += _wave_sample(shape, phase, step) * envelope * volume

	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in sample_count:
		bytes.encode_s16(index * 2, int(_soft_clip(mix[index]) * 32767.0))
	return _make_stream(bytes, true, MUSIC_MIX_RATE, false)


func _make_stream(bytes: PackedByteArray, looping: bool, rate: int, stereo: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = stereo
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# Counted in frames, which is the same number as samples only while the
		# stream is mono.
		stream.loop_end = bytes.size() / (4 if stereo else 2)
	return stream


## One cycle of a plain waveform at normalised phase `t`, with `step` cycles per
## sample so the edged shapes can band-limit themselves against it. The music
## beds are written against these; the combat palette is built from the richer
## shapes above.
func _wave_sample(shape: int, t: float, step: float) -> float:
	match shape:
		SHAPE_SQUARE:
			var square := 1.0 if t < 0.5 else -1.0
			return square + _poly_blep(t, step) - _poly_blep(fposmod(t + 0.5, 1.0), step)
		SHAPE_SAW:
			return _saw(t, step)
		SHAPE_TRI:
			# Naive, and that is fine: a triangle's harmonics fall away as the
			# square of their number, so the few that reach past Nyquist arrive
			# far too quiet to be heard folding back.
			return 4.0 * absf(t - 0.5) - 1.0
	# The default keeps the original two-partial sine, which is what the music
	# beds were written against.
	var phase := t * TAU
	return sin(phase) + sin(phase * 1.5) * 0.22


func _saw(t: float, step: float) -> float:
	return 2.0 * t - 1.0 - _poly_blep(t, step)


## The correction that turns a naive edge into a band-limited one.
##
## A square or a saw built by comparing or by taking a remainder has a vertical
## edge in it, and a vertical edge is every harmonic at once — including all the
## ones above half the sample rate, which do not simply vanish. They fold back
## down to frequencies that have nothing to do with the note and sit there as a
## metallic whistle that follows the pitch around in the wrong direction. This
## rounds the edge over exactly one sample, which removes them at the source
## rather than filtering them out after they have already been aliased.
static func _poly_blep(t: float, step: float) -> float:
	if step <= 0.0:
		return 0.0
	if t < step:
		var rising := t / step
		return rising + rising - rising * rising - 1.0
	if t > 1.0 - step:
		var falling := (t - 1.0) / step
		return falling * falling + falling + falling + 1.0
	return 0.0


## A knee rather than a wall. Reaches exactly full scale at an input of 1.5 and
## never exceeds it, so a cue that sums with three others is quietly compressed
## instead of being squared off into a buzz.
static func _soft_clip(value: float) -> float:
	var x := clampf(value, -1.5, 1.5)
	return x - x * x * x / 6.75


## Hands back an idle player, or makes one while the voice budget allows it, or
## takes the lowest-ranked voice currently sounding if this cue outranks it.
##
## The last case is the point of the whole arrangement. A fixed cap that simply
## dropped anything arriving late would lose a downed partner behind chip damage
## from a swarm, which is the one cue in the game that has to be heard; ranking
## the voices means the cap costs the mix its least important sound instead of
## its most recent one.
func _acquire_player(priority: int) -> AudioStreamPlayer:
	for player in _player_pool:
		if not player.playing:
			_player_pool.erase(player)
			_voice_priority[player.get_instance_id()] = priority
			return player
	if _voices.size() < MAX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = -5.0
		player.finished.connect(func() -> void: _player_pool.append(player))
		_voices.append(player)
		_voice_priority[player.get_instance_id()] = priority
		add_child(player)
		return player
	var weakest: AudioStreamPlayer = null
	var weakest_priority := priority
	for player in _voices:
		var rank := int(_voice_priority.get(player.get_instance_id(), 0))
		if rank < weakest_priority:
			weakest = player
			weakest_priority = rank
	if weakest == null:
		return null
	_player_pool.erase(weakest)
	weakest.stop()
	_voice_priority[weakest.get_instance_id()] = priority
	return weakest
