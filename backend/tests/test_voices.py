from collections import Counter

import numpy as np
import pytest

from app.audio.voices import SECTIONS, build_voices, estimate_f0
from tests.conftest import SR, sung_tone


def test_estimate_f0_finds_sung_pitch():
    assert estimate_f0(sung_tone(196.0), SR) == pytest.approx(196.0, rel=0.03)


def test_estimate_f0_returns_none_for_silence():
    assert estimate_f0(np.zeros(SR, dtype=np.float32), SR) is None


def test_estimate_f0_returns_none_for_noise():
    noise = np.random.default_rng(0).normal(0, 0.1, SR).astype(np.float32)
    assert estimate_f0(noise, SR) is None


def test_build_voices_makes_two_per_section():
    voices = build_voices(220.0, np.random.default_rng(1))
    assert len(voices) == 8
    assert Counter(v.section for v in voices) == {s: 2 for s in SECTIONS}


def test_voice_parameters_respect_ranges():
    for v in build_voices(220.0, np.random.default_rng(2)):
        assert 5.0 <= v.delay_ms <= 30.0
        octaves, cents = divmod(round(v.semitones * 100), 1200)
        cents = cents - 1200 if cents > 600 else cents
        assert -14 <= cents <= 14
        assert -1.0 <= v.pan <= 1.0


@pytest.mark.parametrize("guide_f0", [110.0, 220.0, 440.0])
def test_each_section_lands_near_its_center(guide_f0):
    for v in build_voices(guide_f0, np.random.default_rng(3)):
        sung = guide_f0 * 2 ** (v.semitones / 12)
        center = SECTIONS[v.section].center_hz
        assert center / np.sqrt(2) <= sung <= center * np.sqrt(2)


def test_same_seed_same_voices():
    a = build_voices(220.0, np.random.default_rng(7))
    b = build_voices(220.0, np.random.default_rng(7))
    assert a == b
