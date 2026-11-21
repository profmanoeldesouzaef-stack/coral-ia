# Coral IA

App mobile (Flutter) que gera coral vocal por IA sobre vídeos + backend FastAPI de áudio.

## Layout
- `mobile/` — Flutter, clean architecture por feature (`lib/features/<capture|choir|editor|export>/{data,domain,presentation}`), Riverpod.
- `backend/` — FastAPI. `app/api/v1/` rotas finas; `app/audio/` DSP puro e sem estado (testável sem HTTP).
- `docs/superpowers/` — design e planos por etapa.

## Comandos
- Backend testes: `cd backend && python -m pytest -q` (precisa de ffmpeg no PATH)
- Backend dev: `cd backend && uvicorn app.main:app --reload`
- Mobile: `cd mobile && flutter pub get && flutter run`

## Convenções
- TDD: teste falhando antes do código; DSP testado com sinais sintéticos de `tests/conftest.py` (`sung_tone`).
- Saída de áudio do backend: 48 kHz estéreo, pico −1 dBFS, alinhada ao início da guia.
- Atalhos deliberados marcados com `# shortcut: <limite>, <quando evoluir>`.
- Pacote FFmpeg do app: `ffmpeg_kit_flutter_new` (Full-GPL) — revisar licença antes de publicar.
