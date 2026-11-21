import io
import subprocess

import numpy as np
import pytest
import soundfile as sf
from fastapi.testclient import TestClient

from app.audio import io as audio_io
from app.core.config import settings
from app.main import app
from tests.conftest import SR, sung_tone

client = TestClient(app)
URL = "/api/v1/generate-choir"


def wav_bytes(y: np.ndarray, sr: int = SR) -> bytes:
    buf = io.BytesIO()
    sf.write(buf, y, sr, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def post(data: bytes, filename="guia.wav", **form):
    return client.post(URL, files={"file": (filename, data, "application/octet-stream")}, data=form)


@pytest.fixture(scope="module")
def guide_wav():
    return wav_bytes(sung_tone(220.0, 1.2))


def test_returns_wav_choir_with_metadata(guide_wav):
    r = post(guide_wav, environment="catedral", seed="7")
    assert r.status_code == 200, r.text
    assert r.headers["content-type"] == "audio/wav"
    audio, sr = sf.read(io.BytesIO(r.content))
    assert sr == 48000 and audio.shape[1] == 2
    assert float(r.headers["x-choir-tail-seconds"]) > 1.0
    assert r.headers["x-choir-seed"] == "7"
    assert r.headers["x-choir-voices"] == "8"


def test_returns_aac_m4a(guide_wav):
    r = post(guide_wav, environment="igreja", output_format="aac")
    assert r.status_code == 200, r.text
    assert r.headers["content-type"] == "audio/mp4"
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,channels,sample_rate", "-of", "csv=p=0", "-"],
        input=r.content, capture_output=True, check=True, text=False,
    )
    assert probe.stdout.decode().strip() == "aac,48000,2"


def test_seed_is_generated_when_missing(guide_wav):
    assert post(guide_wav).headers["x-choir-seed"].isdigit()


def test_accepts_phone_m4a_upload(guide_wav, tmp_path):
    src, dst = tmp_path / "g.wav", tmp_path / "g.m4a"
    src.write_bytes(guide_wav)
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(src), "-c:a", "aac", str(dst)], check=True)
    assert post(dst.read_bytes(), filename="guia.m4a").status_code == 200


def test_unknown_environment_is_422(guide_wav):
    assert post(guide_wav, environment="praia").status_code == 422


def test_garbage_file_is_415():
    assert post(b"isto nao e audio", filename="x.wav").status_code == 415


def test_playlist_upload_cannot_read_server_files():
    playlist = b"#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nfile:///etc/hostname\n#EXT-X-ENDLIST\n"
    assert post(playlist, filename="guia.m3u8").status_code == 415


def test_too_large_is_413(guide_wav, monkeypatch):
    monkeypatch.setattr(settings, "max_upload_bytes", 1000)
    assert post(guide_wav).status_code == 413


def test_too_short_is_422():
    r = post(wav_bytes(sung_tone(220.0, 0.3)))
    assert r.status_code == 422
    assert "0.5" in r.json()["detail"]


def test_silence_is_422():
    r = post(wav_bytes(np.zeros(SR, np.float32)))
    assert r.status_code == 422
    assert "voz" in r.json()["detail"].lower()


def test_aac_without_ffmpeg_is_503(guide_wav, monkeypatch):
    monkeypatch.setattr(audio_io.shutil, "which", lambda _: None)
    assert post(guide_wav, output_format="aac").status_code == 503


def test_health():
    assert client.get("/health").json() == {"status": "ok"}
