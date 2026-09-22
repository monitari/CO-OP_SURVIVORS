"""Render the rooftop themes and two alert cues as reproducible PCM WAV files.

Run `python tools/generate_music.py` from the project root. No third-party
packages or sampled material are used; every voice is built from oscillators
and deterministic noise. The 32-bar combat phrases share a tempo and tonal centre so
the game can crossfade between them without a rhythmic jump.
"""

from array import array
import math
from pathlib import Path
import random
import wave


RATE = 24_000
BPM = 96
BEAT = 60.0 / BPM
BARS = 32
LENGTH = BARS * 4 * BEAT
FRAMES = int(LENGTH * RATE)
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"
CHORDS = [
    (50, 53, 57, 60),  # Dm7
    (46, 50, 53, 57),  # Bbmaj7
    (48, 53, 57, 60),  # F/A
    (48, 52, 55, 60),  # Cadd9
]


def hz(midi: int) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def add_note(buf: array, start: float, duration: float, midi: int,
             amplitude: float, voice: str, seed: int = 0, rate: int = RATE) -> None:
    first = round(start * rate)
    count = min(round(duration * rate), len(buf) - first)
    if count <= 0:
        return
    freq = hz(midi)
    rng = random.Random(seed)
    for n in range(count):
        t = n / rate
        p = n / count
        if voice == "pad":
            env = min(1.0, t / 0.32) * min(1.0, (duration - t) / 0.65)
            body = (math.sin(2 * math.pi * freq * t)
                    + 0.31 * math.sin(2 * math.pi * freq * 2.003 * t)
                    + 0.16 * math.sin(2 * math.pi * freq * 3.997 * t)) / 1.47
        elif voice == "bell":
            env = min(1.0, t / 0.009) * math.exp(-3.8 * p)
            body = (math.sin(2 * math.pi * freq * t)
                    + 0.42 * math.sin(2 * math.pi * freq * 2.71 * t)
                    + 0.17 * math.sin(2 * math.pi * freq * 4.13 * t)) / 1.59
        elif voice == "pluck":
            env = min(1.0, t / 0.006) * math.exp(-5.2 * p)
            body = (math.sin(2 * math.pi * freq * t)
                    + 0.30 * (1 - p) * math.sin(2 * math.pi * freq * 2 * t)) / 1.3
        elif voice == "bass":
            env = min(1.0, t / 0.015) * math.exp(-2.8 * p)
            body = math.sin(2 * math.pi * freq * t) + 0.2 * math.sin(4 * math.pi * freq * t)
        elif voice == "kick":
            env = math.exp(-10.0 * p)
            body = math.sin(2 * math.pi * (freq * t + 12 * (1 - math.exp(-22 * t)) / 22))
        elif voice == "shaker":
            env = math.exp(-13.0 * p)
            body = rng.uniform(-1.0, 1.0) * math.sin(2 * math.pi * 4300 * t)
        else:  # A brush on a rooftop tile: noisy attack, warm resonant tail.
            env = math.exp(-11.0 * p)
            body = (0.65 * rng.uniform(-1.0, 1.0)
                    + 0.35 * math.sin(2 * math.pi * 180 * t))
        buf[first + n] += amplitude * env * body


def compose(kind: str) -> array:
    late = kind.endswith("_late")
    kind = kind.removesuffix("_late")
    enraged = kind == "boss_enraged"
    if enraged:
        kind = "boss"
    buf = array("f", [0.0]) * FRAMES
    for bar in range(BARS):
        start = bar * 4 * BEAT
        chord = CHORDS[(bar // 4) % 4]
        # Broad chords give the cats' rooftop its nocturnal, unhurried colour.
        for pitch in chord[1:]:
            add_note(buf, start, 4 * BEAT, pitch + 12,
                     0.027 if kind != "boss" else 0.019, "pad")
        for beat in (0, 2):
            add_note(buf, start + beat * BEAT, 0.58, chord[0] - 12,
                     0.076 if kind == "boss" else 0.047, "bass")
        # The second half answers the first instead of repeating its melody.
        if bar >= 16:
            for step, pitch in enumerate((chord[3], chord[2], chord[1])):
                add_note(buf, start + (step + 0.25) * BEAT, 0.65,
                         pitch + 12, 0.020, "pluck")
        if late or enraged:
            for step in range(8):
                add_note(buf, start + step * BEAT / 2, 0.13, 78,
                         0.009 if late else 0.017, "shaker", bar * 8 + step)
            for beat in (0, 2):
                add_note(buf, start + beat * BEAT, 0.22, 38,
                         0.024 if late else 0.038, "kick")
            add_note(buf, start + 3 * BEAT, 0.42, chord[2] - 12, 0.036, "bass")
        if kind == "field":
            notes = tuple(chord[i] + 24 for i in ((1, 2, 3, 2) if bar < 16 else (3, 2, 1, 2)))
            for step in range(4):
                if (bar + step) % 5 != 0:
                    add_note(buf, start + (step + 0.5) * BEAT, 0.48, notes[step],
                             0.040, "pluck")
            if bar % 4 == 3:
                add_note(buf, start + 3.5 * BEAT, 1.0, chord[3] + 24,
                         0.026, "bell")
        elif kind == "moonlight":
            melody = (chord[2] + 24, chord[3] + 24, chord[1] + 36,
                      chord[3] + 24, chord[2] + 24)
            if bar >= 16:
                melody = tuple(reversed(melody))
            for step, pitch in enumerate(melody):
                offset = (0.0, 0.75, 1.5, 2.75, 3.5)[step]
                if (bar + step) % 6 != 0:
                    add_note(buf, start + offset * BEAT, 0.75, pitch,
                             0.039, "bell")
            add_note(buf, start + 2.5 * BEAT, 0.48, chord[1] + 24,
                     0.021, "pluck")
        else:
            # The boss keeps the same pulse, but moves its weight to the floor.
            for beat in range(4):
                add_note(buf, start + beat * BEAT, 0.20, 38, 0.040, "kick")
                if beat in (1, 3):
                    add_note(buf, start + beat * BEAT, 0.15, 52, 0.032, "brush", bar * 4 + beat)
            for half in range(8):
                if half % 2 or bar >= 8:
                    add_note(buf, start + half * BEAT / 2, 0.11, 80,
                             0.012, "shaker", bar * 8 + half)
            for beat, pitch in ((0, chord[0] + 24), (1.5, chord[2] + 24),
                                (3, chord[1] + 24)):
                add_note(buf, start + beat * BEAT, 0.70, pitch, 0.035, "bell")
    return buf


def compose_scene(kind: str) -> array:
    title = kind == "title"
    bars = 16 if title else 4
    buf = array("f", [0.0]) * round(bars * 4 * BEAT * RATE)
    progression = CHORDS if title else (
        [(53, 57, 60, 65), (48, 52, 55, 60), (46, 50, 53, 57), (53, 57, 60, 65)]
        if kind == "result_win" else
        [(50, 53, 57, 60), (46, 50, 53, 57), (45, 52, 57, 60), (50, 53, 57, 62)])
    for bar in range(bars):
        chord = progression[(bar // 4 if title else bar) % 4]
        start = bar * 4 * BEAT
        for pitch in chord:
            add_note(buf, start, 2.4, pitch, 0.020, "pad")
        add_note(buf, start, 1.4, chord[0] - 12, 0.033, "bass")
        # Space between notes leaves the menu and end-of-run conversation room.
        for step in (0, 2):
            pitch = chord[1 if step == 0 else 2] + (24 if kind == "result_win" else 12)
            add_note(buf, start + (step + 0.5) * BEAT, 1.1, pitch, 0.035, "bell" if title else "pluck")
    if title:
        # A very low rooftop breeze under the title, made without external samples.
        rng = random.Random(721)
        wind = 0.0
        for i in range(len(buf)):
            wind += 0.025 * (rng.uniform(-1, 1) - wind)
            buf[i] += wind * (0.012 + 0.006 * math.sin(2 * math.pi * i / len(buf)))
    else:
        # A composed ending with a release, not an endlessly repeated fanfare.
        fade = round(1.5 * RATE)
        for i in range(fade):
            buf[len(buf) - fade + i] *= 1 - i / fade
    return buf


def write_wav(name: str, buf: array, rate: int = RATE,
              target_peak: float = 0.72, edge_seconds: float = 0.025,
              target_rms: float | None = None) -> None:
    # Keep the phrase edges quiet so a loop never clicks on a transition.
    edge = round(edge_seconds * rate)
    peak = max(abs(value) for value in buf)
    gain = target_peak / peak
    if target_rms is not None:
        rms = math.sqrt(sum(float(value) ** 2 for value in buf) / len(buf))
        gain = min(gain, target_rms / max(rms, 1e-9))
    pcm = array("h")
    for index, value in enumerate(buf):
        edge_gain = min(1.0, index / edge, (len(buf) - 1 - index) / edge)
        pcm.append(round(max(-1.0, min(1.0, value * gain * edge_gain)) * 32767))
    with wave.open(str(OUT / name), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(rate)
        target.writeframes(pcm.tobytes())
    rms = math.sqrt(sum(float(sample) ** 2 for sample in pcm) / len(buf)) / 32768
    print(f"{name}: {len(buf) / rate:.1f}s, peak={max(abs(sample) for sample in pcm) / 32768:.3f}, rms={rms:.3f}")


def compose_signal(kind: str) -> array:
    rate = 48_000
    duration = 0.72 if kind == "down" else 0.52
    buf = array("f", [0.0]) * round(duration * rate)
    if kind == "down":
        # A descending fourth plus a low landing, distinct from boss bells.
        add_note(buf, 0.0, 0.40, 79, 0.28, "bell", rate=rate)
        add_note(buf, 0.24, 0.46, 74, 0.26, "bell", rate=rate)
        add_note(buf, 0.27, 0.40, 38, 0.09, "bass", rate=rate)
    else:
        # The semitone rub is the leash tightening, before it snaps.
        add_note(buf, 0.0, 0.30, 69, 0.22, "pluck", rate=rate)
        add_note(buf, 0.17, 0.32, 70, 0.21, "pluck", rate=rate)
        add_note(buf, 0.10, 0.15, 54, 0.05, "brush", seed=8, rate=rate)
    return buf


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for track in ("field", "moonlight", "field_late", "moonlight_late", "boss", "boss_enraged"):
        write_wav(f"{track}.wav", compose(track), target_peak=0.86, target_rms=0.145)
    for scene in ("title", "result_win", "result_loss"):
        write_wav(f"{scene}.wav", compose_scene(scene), target_peak=0.50)
    for signal, peak in (("down", 0.24), ("chain_strained", 0.18)):
        write_wav(f"{signal}.wav", compose_signal(signal), rate=48_000,
                  target_peak=peak, edge_seconds=0.005)
