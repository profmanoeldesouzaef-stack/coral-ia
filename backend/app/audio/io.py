"""Decodificação da guia e codificação do coral (WAV via soundfile, demais via ffmpeg)."""

import io
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf


# Só demuxers de áudio/vídeo comuns: impede playlists (hls, concat) que leriam arquivos do servidor.
INPUT_FORMATS = "mov,mp4,m4a,3gp,3g2,mj2,aac,mp3,ogg,flac,wav,matroska,webm"


class UnsupportedAudio(ValueError):
    pass


class EncoderUnavailable(RuntimeError):
    pass


def _ffmpeg() -> str | None:
    return shutil.which("ffmpeg")


def decode_audio(data: bytes) -> tuple[np.ndarray, int]:
    """Retorna (amostras float32 [n] ou [n, canais], sample rate)."""
    try:
        y, sr = sf.read(io.BytesIO(data), dtype="float32")
        return y, sr
    except (sf.LibsndfileError, RuntimeError, TypeError):
        pass  # m4a/aac/mp3 do celular: tenta ffmpeg

    ffmpeg = _ffmpeg()
    if ffmpeg is None:
        raise UnsupportedAudio("Formato não suportado sem ffmpeg; envie WAV/FLAC/OGG.")
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in"
        src.write_bytes(data)  # arquivo (não pipe): mp4/m4a precisa de seek
        proc = subprocess.run(
            [ffmpeg, "-v", "error", "-protocol_whitelist", "file", "-format_whitelist", INPUT_FORMATS, "-i", str(src), "-f", "wav", "-c:a", "pcm_f32le", "pipe:1"],
            capture_output=True,
            timeout=120,
        )
    if proc.returncode != 0 or not proc.stdout:
        raise UnsupportedAudio("Não foi possível ler o arquivo de áudio.")
    y, sr = sf.read(io.BytesIO(proc.stdout), dtype="float32")
    return y, sr


def encode_wav(audio: np.ndarray, sr: int) -> bytes:
    buf = io.BytesIO()
    sf.write(buf, audio, sr, format="WAV", subtype="PCM_24")
    return buf.getvalue()


def encode_aac(audio: np.ndarray, sr: int, bitrate: str = "256k") -> bytes:
    """AAC em contêiner .m4a (faststart), pronto para o ffmpeg_kit no app."""
    ffmpeg = _ffmpeg()
    if ffmpeg is None:
        raise EncoderUnavailable("ffmpeg não está instalado no servidor; use output_format=wav.")
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = Path(tmp) / "in.wav", Path(tmp) / "out.m4a"
        sf.write(src, audio, sr, subtype="FLOAT")
        proc = subprocess.run(
            [ffmpeg, "-v", "error", "-y", "-i", str(src), "-c:a", "aac", "-b:a", bitrate,
             "-movflags", "+faststart", str(dst)],
            capture_output=True,
            timeout=300,
        )
        if proc.returncode != 0:
            raise EncoderUnavailable(f"Falha ao codificar AAC: {proc.stderr.decode(errors='ignore')[-300:]}")
        return dst.read_bytes()
