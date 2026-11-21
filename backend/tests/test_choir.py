import numpy as np
import pytest

from app.audio.choir import OUTPUT_SR, PEAK_LINEAR, NoVoiceDetected, render_choir
from tests.conftest import SR, sung_tone


@pytest.fixture
def guide():
    return sung_tone(220.0, seconds=1.5)


def test_renders_stereo_48k_with_tail(guide, tmp_path):
    res = render_choir(guide, SR, "igreja", seed=1, ir_dir=tmp_path)
    guide_len = round(len(guide) * OUTPUT_SR / SR)
    assert res.audio.ndim == 2 and res.audio.shape[1] == 2
    assert res.sample_rate == OUTPUT_SR == 48000
    assert res.audio.shape[0] > guide_len
    assert res.tail_seconds == pytest.approx((res.audio.shape[0] - guide_len) / OUTPUT_SR, abs=1e-3)
    assert len(res.voices) == 8


def test_peak_is_normalized_below_minus_1_dbfs(guide, tmp_path):
    res = render_choir(guide * 1.9, SR, "banheiro", seed=1, ir_dir=tmp_path)  # guia clipando
    assert np.abs(res.audio).max() == pytest.approx(PEAK_LINEAR, rel=1e-3)
    assert PEAK_LINEAR <= 10 ** (-1 / 20) + 1e-9


def test_same_seed_is_reproducible(guide, tmp_path):
    a = render_choir(guide, SR, "catedral", seed=42, ir_dir=tmp_path)
    b = render_choir(guide, SR, "catedral", seed=42, ir_dir=tmp_path)
    np.testing.assert_array_equal(a.audio, b.audio)


def test_stereo_guide_is_accepted(guide, tmp_path):
    stereo = np.stack([guide, guide], axis=1)
    res = render_choir(stereo, SR, "estadio", seed=3, ir_dir=tmp_path)
    assert res.audio.shape[1] == 2


def test_choir_starts_with_the_guide_plus_micro_delay(tmp_path):
    lead = 0.5
    guide = np.concatenate([np.zeros(int(lead * SR), np.float32), sung_tone(220.0, 1.0)])
    res = render_choir(guide, SR, "banheiro", seed=5, ir_dir=tmp_path)
    assert np.isfinite(res.audio).all()  # silêncio digital gera aviso no phase vocoder do librosa
    env = np.abs(res.audio).max(axis=1)
    onset = np.argmax(env > 0.05 * env.max()) / OUTPUT_SR
    assert lead + 0.005 - 0.01 <= onset <= lead + 0.030 + 0.06  # fade-in de 50 ms da guia


def test_silence_raises(tmp_path):
    with pytest.raises(NoVoiceDetected):
        render_choir(np.zeros(SR, np.float32), SR, "igreja", seed=1, ir_dir=tmp_path)
