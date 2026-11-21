import numpy as np
import pytest
import soundfile as sf

from app.audio.reverb import PRESETS, apply_reverb, load_ir

SR = 48000


def rt60(ir: np.ndarray, sr: int) -> float:
    """T30 por integração de Schroeder, extrapolado para 60 dB."""
    energy = np.cumsum((ir[:, 0] ** 2)[::-1])[::-1]
    edc = 10 * np.log10(energy / energy[0] + 1e-20)
    t5, t35 = np.argmax(edc <= -5), np.argmax(edc <= -35)
    return 2 * (t35 - t5) / sr


@pytest.mark.parametrize("preset", list(PRESETS))
def test_synthetic_ir_matches_preset_rt60(preset, tmp_path):
    ir = load_ir(preset, SR, tmp_path)
    assert ir.ndim == 2 and ir.shape[1] == 2
    assert rt60(ir, SR) == pytest.approx(PRESETS[preset].rt60, rel=0.25)


def test_rooms_are_ordered_by_size(tmp_path):
    r = {p: rt60(load_ir(p, SR, tmp_path), SR) for p in ("catedral", "igreja", "banheiro")}
    assert r["catedral"] > r["igreja"] > r["banheiro"]


def test_ir_channels_are_decorrelated(tmp_path):
    ir = load_ir("igreja", SR, tmp_path)
    assert abs(np.corrcoef(ir[:, 0], ir[:, 1])[0, 1]) < 0.5


def test_real_ir_file_overrides_synthetic(tmp_path):
    real = np.zeros((2400, 2), dtype=np.float32)
    real[10] = [1.0, 0.5]
    sf.write(tmp_path / "banheiro.wav", real, 24000)
    ir = load_ir("banheiro", SR, tmp_path)
    assert ir.shape == (4800, 2)  # reamostrado para 48 kHz
    assert np.argmax(np.abs(ir[:, 0])) == pytest.approx(20, abs=2)


def test_apply_reverb_appends_tail_and_keeps_dry(tmp_path):
    dry = np.zeros((SR, 2), dtype=np.float32)
    dry[0] = 1.0
    out = apply_reverb(dry, SR, "banheiro", tmp_path)
    assert out.shape[0] > dry.shape[0]
    assert out.shape[1] == 2
    assert out[0, 0] > 0.3  # impulso seco ainda presente
    assert np.abs(out[SR // 4 :]).max() < np.abs(out[: SR // 20]).max()  # decai
