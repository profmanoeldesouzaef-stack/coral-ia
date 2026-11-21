"""Definição das 8 vozes do coral a partir do f0 da guia."""

from dataclasses import dataclass

import librosa
import numpy as np

ANALYSIS_SR = 16000


@dataclass(frozen=True)
class Section:
    center_hz: float      # centro da tessitura do naipe
    formant_factor: float  # >1 = timbre mais claro/"menor"; <1 = mais escuro


SECTIONS: dict[str, Section] = {
    "soprano": Section(523.0, 1.10),
    "contralto": Section(349.0, 1.04),
    "tenor": Section(220.0, 0.96),
    "baixo": Section(131.0, 0.90),
}
VOICES_PER_SECTION = 2


@dataclass(frozen=True)
class VoiceSpec:
    section: str
    semitones: float
    formant_factor: float
    delay_ms: float
    pan: float   # -1 esquerda, +1 direita
    gain: float


def estimate_f0(y: np.ndarray, sr: int) -> float | None:
    """f0 mediano dos trechos cantados; None se não houver voz detectável."""
    if np.max(np.abs(y), initial=0.0) < 1e-4:
        return None
    y16 = librosa.resample(np.asarray(y, dtype=np.float32), orig_sr=sr, target_sr=ANALYSIS_SR)
    f0, voiced, prob = librosa.pyin(y16, fmin=60, fmax=1100, sr=ANALYSIS_SR, frame_length=1024)
    voiced &= prob > 0.4  # o HMM do pYIN marca alguns frames de ruído como "voiced" com prob ~0.01
    if voiced.sum() < max(5, 0.1 * len(voiced)):
        return None
    return float(np.nanmedian(f0[voiced]))


def build_voices(guide_f0: float, rng: np.random.Generator) -> list[VoiceSpec]:
    """2 vozes por naipe, cada uma na oitava da guia mais próxima do centro do naipe.

    Oitavas (e não terças/quintas) porque a tonalidade da música é desconhecida no Modo B.
    """
    voices = []
    for name, section in SECTIONS.items():
        octaves = round(np.log2(section.center_hz / guide_f0))
        for _ in range(VOICES_PER_SECTION):
            cents = rng.uniform(4, 14) * rng.choice([-1, 1])
            voices.append(
                VoiceSpec(
                    section=name,
                    semitones=12 * octaves + cents / 100,
                    formant_factor=section.formant_factor * rng.uniform(0.98, 1.02),
                    delay_ms=rng.uniform(5.0, 30.0),
                    pan=rng.uniform(-0.8, 0.8),
                    gain=rng.uniform(0.8, 1.0),
                )
            )
    return voices
