import numpy as np
import pytest

from app.audio.dsp import delay, shift_pitch_formant
from tests.conftest import SR, median_f0, spectral_centroid


@pytest.mark.parametrize("semitones", [12, -12, 0.1])
def test_shift_moves_f0_by_semitones(tone, semitones):
    out = shift_pitch_formant(tone, SR, semitones, formant_factor=1.0)
    expected = 220.0 * 2 ** (semitones / 12)
    assert median_f0(out, SR) == pytest.approx(expected, rel=0.02)


def test_shift_preserves_length(tone):
    assert len(shift_pitch_formant(tone, SR, 5, 1.1)) == len(tone)


def test_formant_factor_moves_spectral_envelope(tone):
    # Mesmo pitch, formante maior -> energia sobe para agudos.
    low = shift_pitch_formant(tone, SR, 0, formant_factor=0.85)
    high = shift_pitch_formant(tone, SR, 0, formant_factor=1.15)
    assert spectral_centroid(high, SR) > spectral_centroid(low, SR) * 1.1


@pytest.mark.parametrize("semitones", [-5, 7, 12])
def test_unity_formant_keeps_envelope(tone, semitones):
    out = shift_pitch_formant(tone, SR, semitones, formant_factor=1.0)
    assert spectral_centroid(out, SR) == pytest.approx(spectral_centroid(tone, SR), rel=0.2)


def test_octave_down_is_brighter_than_plain_pitch_shift(tone):
    # Oitava abaixo não recupera agudos que a fonte não tem (ganho limitado a ±20 dB),
    # mas a correção precisa tirar o som "abafado" do phase vocoder puro.
    import librosa

    plain = librosa.effects.pitch_shift(tone, sr=SR, n_steps=-12)
    out = shift_pitch_formant(tone, SR, -12, formant_factor=1.0)
    assert spectral_centroid(out, SR) > spectral_centroid(plain, SR) * 1.2


def test_delay_shifts_signal_by_ms():
    y = np.zeros(1000, dtype=np.float32)
    y[0] = 1.0
    out = delay(y, 1000, ms=12.4)
    assert len(out) == len(y) + 12
    assert np.argmax(out) == 12
