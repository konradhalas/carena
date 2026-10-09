# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy"]
# ///
"""Synthesises the game's sound effects into assets/audio/*.wav.

Everything is generated (no third-party samples), deterministic (fixed seed)
and tweakable here. Loops are seamless: their frequencies fit the loop length
exactly and noise is shaped in the frequency domain (circular filtering).

Usage: uv run tools/audio/generate_sounds.py
"""

from pathlib import Path
import wave

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio"
rng = np.random.default_rng(7)


def timeline(seconds: float) -> np.ndarray:
    return np.arange(int(RATE * seconds)) / RATE


def band_noise(samples: int, low: float, high: float, tilt: float = 0.0) -> np.ndarray:
    """White noise band-passed in the frequency domain (periodic over its length).
    tilt < 0 darkens the band (more energy at the low end)."""
    spectrum = np.fft.rfft(rng.standard_normal(samples))
    freqs = np.fft.rfftfreq(samples, 1 / RATE)
    mask = ((freqs >= low) & (freqs <= high)).astype(float)
    with np.errstate(divide="ignore"):
        mask *= np.where(freqs > 0, (freqs / max(low, 1.0)) ** tilt, 0.0)
    out = np.fft.irfft(spectrum * mask, samples)
    return out / (np.max(np.abs(out)) + 1e-9)


def lowpass(signal: np.ndarray, cutoff: float) -> np.ndarray:
    spectrum = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(signal.size, 1 / RATE)
    spectrum *= 1.0 / (1.0 + (freqs / cutoff) ** 4)
    return np.fft.irfft(spectrum, signal.size)


def normalise(signal: np.ndarray, peak: float = 0.9) -> np.ndarray:
    return signal / (np.max(np.abs(signal)) + 1e-9) * peak


def fade(signal: np.ndarray, fade_in: float = 0.002, fade_out: float = 0.01) -> np.ndarray:
    out = signal.copy()
    n_in, n_out = int(fade_in * RATE), int(fade_out * RATE)
    if n_in:
        out[:n_in] *= np.linspace(0, 1, n_in)
    if n_out:
        out[-n_out:] *= np.linspace(1, 0, n_out)
    return out


def write(name: str, signal: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data = (np.clip(signal, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(data.tobytes())
    print(f"{name}.wav  {signal.size / RATE:.2f}s")


def engine_loop() -> np.ndarray:
    """1 s loop at a 40 Hz idle: buzzy harmonics, cylinder-firing pulses and a
    breath of intake noise. Played pitched up with speed in the game."""
    t = timeline(1.0)
    f0 = 40.0  # integer Hz -> seamless over 1 s
    tone = sum(np.sin(2 * np.pi * f0 * k * t + k) / k**0.8 for k in range(1, 16))
    firing = 0.55 + 0.45 * np.maximum(np.sin(2 * np.pi * f0 * 2 * t), 0) ** 3
    rumble = band_noise(t.size, 60, 900, tilt=-1.0) * 0.35
    return normalise(np.tanh(1.6 * tone * firing / 4.0) + rumble, 0.8)


def skid_loop() -> np.ndarray:
    """1 s loop: dirt scrubbing / tyre squeal — bright band noise that flutters."""
    t = timeline(1.0)
    scrub = band_noise(t.size, 400, 5000, tilt=-0.5)
    flutter = 0.7 + 0.3 * np.sin(2 * np.pi * 13 * t) * np.sin(2 * np.pi * 3 * t)
    return normalise(scrub * flutter, 0.7)


def cannon() -> np.ndarray:
    """Heavy cannon: deep boom with a sharp blast on top and a metallic
    clank of the breech, longer tail than the old gunshot."""
    t = timeline(0.9)
    blast = band_noise(t.size, 300, 7000, tilt=-0.6) * np.exp(-t / 0.025)
    sweep = 2 * np.pi * np.cumsum(90 * np.exp(-t / 0.08) + 32) / RATE
    boom = np.sin(sweep) * np.exp(-t / 0.22)
    tail = lowpass(band_noise(t.size, 40, 2500, tilt=-1.0), 500) * np.exp(-t / 0.3) * 0.5
    clank_t = np.clip(t - 0.12, 0, None)
    clank = sum(np.sin(2 * np.pi * f * clank_t) * np.exp(-clank_t / 0.05) for f in (820, 1310, 1975))
    clank *= (t > 0.12) * 0.15
    mix = np.tanh(2.2 * (blast * 0.9 + boom * 1.3 + tail)) + clank
    return fade(normalise(mix, 0.95), 0.0005, 0.1)


def empty_click() -> np.ndarray:
    """Dry trigger click when the magazine is empty."""
    t = timeline(0.12)
    click = band_noise(t.size, 1500, 9000) * np.exp(-t / 0.006)
    knock = np.sin(2 * np.pi * 420 * t) * np.exp(-t / 0.02) * 0.4
    return fade(normalise(click + knock, 0.6), 0.0005, 0.02)


def pickup() -> np.ndarray:
    """Collecting a pickup: bright rising two-note chime."""
    t = timeline(0.5)
    note = lambda f, start: (
        np.sin(2 * np.pi * f * np.clip(t - start, 0, None))
        * (t >= start) * np.exp(-np.clip(t - start, 0, None) / 0.18)
    )
    chime = note(880, 0.0) + note(1318.5, 0.09) + 0.3 * note(2637, 0.09)
    return fade(normalise(chime, 0.7), 0.002, 0.05)


def impact_metal() -> np.ndarray:
    """Bullet hitting a car: inharmonic metallic ping over a click."""
    t = timeline(0.45)
    partials = [(1320, 0.10), (2035, 0.07), (2870, 0.05), (4110, 0.035), (5600, 0.02)]
    ping = sum(np.sin(2 * np.pi * f * t + i) * np.exp(-t / d) for i, (f, d) in enumerate(partials))
    click = band_noise(t.size, 2000, 12000) * np.exp(-t / 0.004)
    return fade(normalise(ping * 0.7 + click * 0.8, 0.8), 0.0005, 0.05)


def impact_dirt() -> np.ndarray:
    """Bullet hitting the ground: dull puff of dirt."""
    t = timeline(0.3)
    puff = lowpass(band_noise(t.size, 60, 4000, tilt=-1.0), 900) * np.exp(-t / 0.05)
    return fade(normalise(puff, 0.7), 0.001, 0.05)


def landing() -> np.ndarray:
    """Heavy thump of a car landing: low body slam plus suspension rattle."""
    t = timeline(0.6)
    slam = np.sin(2 * np.pi * np.cumsum(70 * np.exp(-t / 0.08) + 38) / RATE) * np.exp(-t / 0.14)
    rattle = band_noise(t.size, 150, 2500, tilt=-0.5) * np.exp(-t / 0.05) * 0.5
    return fade(normalise(np.tanh(2.0 * (slam + rattle)), 0.85), 0.001, 0.08)


def explosion() -> np.ndarray:
    """Car explosion: sub boom, rolling low-passed roar and debris crackle."""
    t = timeline(3.0)
    boom = np.sin(2 * np.pi * np.cumsum(55 * np.exp(-t / 0.25) + 28) / RATE) * np.exp(-t / 0.6)
    roar = lowpass(band_noise(t.size, 30, 6000, tilt=-1.2), 700) * (1 - np.exp(-t / 0.01)) * np.exp(-t / 0.9)
    crackle = np.zeros(t.size)
    for _ in range(90):
        start = int(rng.uniform(0.02, 1.8) * RATE)
        length = int(rng.uniform(0.003, 0.02) * RATE)
        end = min(start + length, t.size)
        crackle[start:end] += rng.standard_normal(end - start) * np.exp(-start / RATE / 0.7)
    crackle = lowpass(crackle, 5000) * 0.35
    mix = np.tanh(1.8 * (boom * 1.2 + roar + crackle))
    return fade(normalise(mix, 0.95), 0.001, 0.3)


def main() -> None:
    write("engine_loop", engine_loop())
    write("skid_loop", skid_loop())
    write("cannon", cannon())
    write("empty_click", empty_click())
    write("pickup", pickup())
    write("impact_metal", impact_metal())
    write("impact_dirt", impact_dirt())
    write("landing", landing())
    write("explosion", explosion())


if __name__ == "__main__":
    main()
