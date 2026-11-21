"""Reverb por convolução: IR real em assets/ir/<preset>.wav ou IR sintético do preset."""

from dataclasses import dataclass
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, sosfilt


@dataclass(frozen=True)
class RoomPreset:
    rt60: float                 # segundos para cair 60 dB (graves/médios)
    hf_ratio: float             # rt60 dos agudos = rt60 * hf_ratio (absorção do ar/superfícies)
    predelay_ms: float
    early: tuple[tuple[float, float], ...]  # reflexões iniciais (ms, ganho)
    wet: float                  # nível do sinal reverberado somado ao seco


PRESETS: dict[str, RoomPreset] = {
    "catedral": RoomPreset(4.5, 0.45, 45, ((23, 0.5), (41, 0.4), (67, 0.35), (89, 0.3)), 0.55),
    "igreja": RoomPreset(2.4, 0.55, 25, ((13, 0.5), (24, 0.4), (37, 0.3)), 0.45),
    "banheiro": RoomPreset(0.8, 0.9, 3, ((2, 0.7), (4, 0.6), (6, 0.5), (9, 0.4)), 0.4),
    # Ecos discretos das arquibancadas sobre uma cauda longa e escura.
    "estadio": RoomPreset(3.2, 0.4, 70, ((120, 0.45), (260, 0.3), (420, 0.2)), 0.45),
}


def _synthetic_ir(preset: RoomPreset, sr: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    pre = int(preset.predelay_ms * sr / 1000)
    n = pre + int(preset.rt60 * 1.2 * sr)
    t = np.arange(n - pre) / sr
    ir = np.zeros((n, 2))
    low_sos = butter(4, 3000, "low", fs=sr, output="sos")
    high_sos = butter(4, 3000, "high", fs=sr, output="sos")
    onset = np.minimum(1.0, t / 0.01)
    for ch in range(2):
        noise = rng.standard_normal(n - pre)
        low = sosfilt(low_sos, noise) * np.exp(-6.91 * t / preset.rt60)
        high = sosfilt(high_sos, noise) * np.exp(-6.91 * t / (preset.rt60 * preset.hf_ratio))
        ir[pre:, ch] = (low + high) * onset
        for ms, gain in preset.early:
            # pequenas diferenças L/R dão largura estéreo
            idx = pre + int((ms + rng.uniform(-1.5, 1.5)) * sr / 1000)
            if idx < n:
                ir[idx, ch] += gain * 4 * np.sqrt(np.mean(ir[pre : pre + sr // 100, ch] ** 2))
    return ir


def _read_ir(path: Path, sr: int) -> np.ndarray:
    data, file_sr = sf.read(path, always_2d=True, dtype="float64")
    data = np.repeat(data, 2, axis=1) if data.shape[1] == 1 else data[:, :2]
    if file_sr != sr:
        data = librosa.resample(data.T, orig_sr=file_sr, target_sr=sr).T
    return data


def load_ir(preset: str, sr: int, ir_dir: Path) -> np.ndarray:
    """IR estéreo (n, 2) com energia unitária por canal."""
    real = Path(ir_dir) / f"{preset}.wav"
    ir = _read_ir(real, sr) if real.exists() else _synthetic_ir(PRESETS[preset], sr, seed=sum(map(ord, preset)))
    energy = np.sqrt(np.sum(ir**2, axis=0, keepdims=True))
    return (ir / np.maximum(energy, 1e-12)).astype(np.float32)


def apply_reverb(stereo: np.ndarray, sr: int, preset: str, ir_dir: Path) -> np.ndarray:
    """Seco + reverb. A saída cresce len(IR)-1 amostras (cauda)."""
    ir = load_ir(preset, sr, ir_dir)
    wet = np.stack([fftconvolve(stereo[:, c], ir[:, c]) for c in range(2)], axis=1)
    out = wet * PRESETS[preset].wet
    out[: len(stereo)] += stereo
    return out.astype(np.float32)
