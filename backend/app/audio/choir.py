"""Orquestra guia -> 8 vozes -> mix estéreo -> reverb -> normalização."""

from dataclasses import dataclass
from pathlib import Path

import librosa
import numpy as np

from app.audio.dsp import delay, guide_envelope, shift_pitch_formant
from app.audio.reverb import apply_reverb
from app.audio.voices import VoiceSpec, build_voices, estimate_f0

OUTPUT_SR = 48000
PEAK_LINEAR = 10 ** (-1 / 20)  # -1 dBFS: margem para o AAC não clipar
MAX_DELAY_MS = 30.0
DEFAULT_IR_DIR = Path(__file__).resolve().parents[2] / "assets" / "ir"


class NoVoiceDetected(ValueError):
    pass


@dataclass
class ChoirResult:
    audio: np.ndarray  # (n, 2) float32, alinhado ao início da guia
    sample_rate: int
    tail_seconds: float
    voices: list[VoiceSpec]


def render_choir(
    y: np.ndarray, sr: int, environment: str, seed: int | None = None, ir_dir: Path = DEFAULT_IR_DIR
) -> ChoirResult:
    mono = np.asarray(y, dtype=np.float32)
    if mono.ndim == 2:
        mono = mono.mean(axis=1)
    mono = librosa.resample(mono, orig_sr=sr, target_sr=OUTPUT_SR) if sr != OUTPUT_SR else mono

    f0 = estimate_f0(mono, OUTPUT_SR)
    if f0 is None:
        raise NoVoiceDetected("Nenhuma voz cantada detectada na guia.")

    voices = build_voices(f0, np.random.default_rng(seed))
    n = len(mono)
    env = guide_envelope(mono, OUTPUT_SR)
    mix = np.zeros((n + int(np.ceil(MAX_DELAY_MS * OUTPUT_SR / 1000)) + 1, 2), dtype=np.float32)
    for v in voices:
        sig = delay(shift_pitch_formant(mono, OUTPUT_SR, v.semitones, v.formant_factor, env), OUTPUT_SR, v.delay_ms)
        angle = (v.pan + 1) * np.pi / 4  # pan de potência constante
        mix[: len(sig)] += v.gain * np.outer(sig, [np.cos(angle), np.sin(angle)])

    out = apply_reverb(mix, OUTPUT_SR, environment, ir_dir)
    out *= PEAK_LINEAR / max(float(np.abs(out).max()), 1e-9)
    return ChoirResult(out.astype(np.float32), OUTPUT_SR, (len(out) - n) / OUTPUT_SR, voices)
