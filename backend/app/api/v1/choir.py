import secrets
from enum import StrEnum

from fastapi import APIRouter, File, Form, HTTPException, Response, UploadFile

from app.audio.choir import NoVoiceDetected, render_choir
from app.audio.io import EncoderUnavailable, UnsupportedAudio, decode_audio, encode_aac, encode_wav
from app.audio.reverb import PRESETS
from app.core.config import settings

router = APIRouter()

Environment = StrEnum("Environment", {name: name for name in PRESETS})


class OutputFormat(StrEnum):
    wav = "wav"
    aac = "aac"


MEDIA = {OutputFormat.wav: ("audio/wav", "wav"), OutputFormat.aac: ("audio/mp4", "m4a")}


# shortcut: endpoint síncrono roda no threadpool do FastAPI e prende 1 CPU por ~segundos;
# com muitos usuários simultâneos, mover para fila (Celery/RQ) + polling.
@router.post("/generate-choir", summary="Gera coral de 8 vozes a partir da guia cantada (Modo B)")
def generate_choir(
    file: UploadFile = File(..., description="Guia cantada: wav, m4a, aac, mp3, ogg, flac"),
    environment: Environment = Form(Environment.igreja),
    output_format: OutputFormat = Form(OutputFormat.wav),
    seed: int | None = Form(None, ge=0, description="Repete exatamente o mesmo coral"),
) -> Response:
    data = file.file.read(settings.max_upload_bytes + 1)
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(413, f"Arquivo maior que {settings.max_upload_bytes // (1024 * 1024)} MB.")

    try:
        y, sr = decode_audio(data)
    except UnsupportedAudio as exc:
        raise HTTPException(415, str(exc)) from exc

    seconds = len(y) / sr
    if not settings.min_seconds <= seconds <= settings.max_seconds:
        raise HTTPException(
            422, f"A guia deve ter entre {settings.min_seconds} e {settings.max_seconds} s (recebido {seconds:.2f} s)."
        )

    seed = secrets.randbelow(2**31) if seed is None else seed
    try:
        result = render_choir(y, sr, environment.value, seed=seed, ir_dir=settings.ir_dir)
    except NoVoiceDetected as exc:
        raise HTTPException(422, str(exc)) from exc

    try:
        body = encode_aac(result.audio, result.sample_rate) if output_format is OutputFormat.aac else encode_wav(
            result.audio, result.sample_rate
        )
    except EncoderUnavailable as exc:
        raise HTTPException(503, str(exc)) from exc

    media_type, ext = MEDIA[output_format]
    return Response(
        content=body,
        media_type=media_type,
        headers={
            "Content-Disposition": f'attachment; filename="coral_{environment.value}.{ext}"',
            "X-Choir-Sample-Rate": str(result.sample_rate),
            "X-Choir-Tail-Seconds": f"{result.tail_seconds:.3f}",
            "X-Choir-Voices": str(len(result.voices)),
            "X-Choir-Seed": str(seed),
            "Access-Control-Expose-Headers": "X-Choir-Sample-Rate, X-Choir-Tail-Seconds, X-Choir-Voices, X-Choir-Seed",
        },
    )
