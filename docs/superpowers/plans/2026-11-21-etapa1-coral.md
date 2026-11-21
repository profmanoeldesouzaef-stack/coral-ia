# Etapa 1 — Núcleo de coral Implementation Plan

**Goal:** endpoint que transforma uma guia cantada em coral de 8 vozes com reverb.
**Architecture:** FastAPI fino (`app/api/v1/choir.py`) sobre um pacote DSP puro (`app/audio/*`) sem estado; decodificação/codificação via soundfile + ffmpeg.
**Tech Stack:** Python 3.11+, FastAPI, numpy, scipy, librosa, soundfile, ffmpeg.
**Spec:** `docs/superpowers/specs/2026-11-21-etapa1-coral-design.md`

## Global Constraints
- 8 vozes: 2× soprano, contralto, tenor, baixo.
- Micro-atraso por voz ∈ [5 ms, 30 ms].
- Presets: `catedral`, `igreja`, `banheiro`, `estadio`.
- Saída 48 000 Hz, estéreo, pico ≤ −1 dBFS; formatos `wav` | `aac`.
- Upload ≤ 25 MB; duração 0,5–120 s.

## Review Focus
- Guia em silêncio/sem voz detectável → 422 com mensagem clara (não coral de ruído).
- Arquivo corrompido ou formato desconhecido → 415/422, nunca 500.
- Guia mono ou estéreo, qualquer sample rate → mesma saída 48 kHz estéreo.
- Clipping na soma das 8 vozes → pico normalizado.
- ffmpeg ausente com `output_format=aac` → 503 explícito.

### Task 1: DSP (`app/audio/dsp.py`) — `tests/test_dsp.py`
- `shift_pitch_formant(y, sr, semitones, formant_factor) -> np.ndarray`: f0 do resultado ≈ f0·2^(st/12) (±2%); comprimento preservado.
- `delay(y, sr, ms) -> np.ndarray`: primeira amostra não nula deslocada de round(ms·sr/1000).

### Task 2: Vozes (`app/audio/voices.py`) — `tests/test_voices.py`
- `estimate_f0(y, sr) -> float | None`; `build_voices(guide_f0, rng) -> list[VoiceSpec]`: 8 vozes, 2 por naipe, atrasos em [5, 30], deslocamentos múltiplos de 12 + cents em [-14, 14].

### Task 3: Reverb (`app/audio/reverb.py`) — `tests/test_reverb.py`
- `load_ir(preset, sr, ir_dir) -> np.ndarray (n, 2)`; RT60 catedral > igreja > banheiro; `apply_reverb(stereo, sr, preset)` alonga o sinal pela cauda.

### Task 4: Orquestrador (`app/audio/choir.py`) — `tests/test_choir.py`
- `render_choir(y, sr, environment, seed) -> ChoirResult(audio (n,2) 48 kHz, tail_seconds, voices)`; pico ≤ 10^(−1/20); mesmo seed → mesma saída; silêncio → `NoVoiceDetected`.

### Task 5: Endpoint (`app/api/v1/choir.py`) — `tests/test_api.py`
- 200 WAV/AAC com headers; 422 preset inválido; 415 arquivo inválido; 413 grande demais; 422 silêncio.
