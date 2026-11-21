"""Blocos DSP: pitch shift com controle de formante e atraso."""

import librosa
import numpy as np

N_FFT = 2048
HOP = 512
MAX_GAIN_DB = 20.0


def _envelope(mag: np.ndarray, lifter: int, iterations: int = 12) -> np.ndarray:
    """"True envelope" (cepstro iterativo): passa pelos picos dos harmônicos.

    O cepstro simples dá a média do log, que fica mais alta quanto mais densos os
    harmônicos (voz grave); isso enviesava a correção entre sinais de f0 diferentes.
    """
    log_mag = np.log(mag + 1e-9)
    target = log_mag
    for _ in range(iterations):
        cep = np.fft.irfft(target, axis=0)
        cep[lifter:-lifter] = 0.0
        smooth = np.fft.rfft(cep, axis=0).real
        target = np.maximum(log_mag, smooth)
    return np.exp(smooth)


def _warp(env: np.ndarray, factor: float) -> np.ndarray:
    """Estica o envelope no eixo de frequência: formante em f vai para f*factor."""
    bins = np.arange(env.shape[0])
    src = bins / factor
    return np.stack([np.interp(src, bins, env[:, i]) for i in range(env.shape[1])], axis=1)


def lifter_for(sr: int) -> int:
    return max(8, int(sr / 1200))  # abaixo do período do f0 mais agudo esperado


def guide_envelope(y: np.ndarray, sr: int) -> np.ndarray:
    """Envelope espectral da guia; calcule uma vez e reutilize em todas as vozes."""
    return _envelope(np.abs(librosa.stft(np.asarray(y, dtype=np.float32), n_fft=N_FFT, hop_length=HOP)), lifter_for(sr))


def shift_pitch_formant(
    y: np.ndarray, sr: int, semitones: float, formant_factor: float, env_orig: np.ndarray | None = None
) -> np.ndarray:
    """Desloca o pitch em `semitones` e posiciona os formantes em `formant_factor` x original.

    O phase vocoder move os formantes junto com o pitch; corrigimos isso trocando o
    envelope do sinal deslocado pelo envelope original esticado por `formant_factor`.
    """
    y = np.asarray(y, dtype=np.float32)
    shifted = librosa.effects.pitch_shift(y, sr=sr, n_steps=semitones) if semitones else y.copy()

    env_orig = guide_envelope(y, sr) if env_orig is None else env_orig
    spec_shift = librosa.stft(shifted, n_fft=N_FFT, hop_length=HOP)
    env_shift = _envelope(np.abs(spec_shift), lifter_for(sr))
    target = _warp(env_orig, formant_factor) if formant_factor != 1.0 else env_orig

    limit = 10 ** (MAX_GAIN_DB / 20)
    gain = np.clip(target / (env_shift + 1e-9), 1 / limit, limit)
    out = librosa.istft(spec_shift * gain, hop_length=HOP, length=len(y))
    return out.astype(np.float32)


def delay(y: np.ndarray, sr: int, ms: float) -> np.ndarray:
    """Atrasa o sinal inserindo silêncio no início (o comprimento cresce)."""
    pad = int(round(ms * sr / 1000))
    return np.concatenate([np.zeros(pad, dtype=y.dtype), y])
