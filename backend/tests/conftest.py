import numpy as np
import pytest

SR = 44100


def sung_tone(f0: float = 220.0, seconds: float = 2.0, sr: int = SR) -> np.ndarray:
    """Vogal sintética /a/: harmônicos com ressonâncias (forma de Lorentz, como no trato vocal) e vibrato."""
    t = np.arange(int(seconds * sr)) / sr
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
    phase = 2 * np.pi * np.cumsum(f0 * vib) / sr
    formants = [(800, 90), (1150, 110), (2900, 160)]
    y = np.zeros_like(t)
    for h in range(1, int(8000 / f0)):
        freq = h * f0
        amp = sum(1 / (1 + ((freq - fc) / bw) ** 2) for fc, bw in formants) / h**0.5
        y += amp * np.sin(h * phase)
    fade = np.minimum(1, np.minimum(t, t[::-1]) / 0.05)
    return (0.5 * y / np.max(np.abs(y)) * fade).astype(np.float32)


def median_f0(y: np.ndarray, sr: int) -> float:
    import librosa

    f0 = librosa.yin(y, fmin=50, fmax=1500, sr=sr)
    return float(np.median(f0[len(f0) // 4 : -len(f0) // 4]))


def spectral_centroid(y: np.ndarray, sr: int) -> float:
    import librosa

    return float(np.mean(librosa.feature.spectral_centroid(y=y, sr=sr)))


@pytest.fixture
def tone():
    return sung_tone()
