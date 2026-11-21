# Coral IA

App Android (Flutter) 100% offline que gera coral vocal sobre vídeos. O `backend/` FastAPI é o protótipo da etapa 1 (opcional).

## Layout
- `mobile/` — Flutter + Riverpod. `lib/core/audio/` motor puro em Dart (YIN, PSOLA, FFT, WAV, `renderChoir`); `lib/features/<home|editor|choir|export|project>/` telas e serviços. `android/` é gerado no CI (`flutter create` + `scripts/patch_android.sh`).
- `backend/` — FastAPI. `app/api/v1/` rotas finas; `app/audio/` DSP puro e sem estado (testável sem HTTP).
- `docs/superpowers/` — design e planos por etapa.

## Comandos
- Backend testes: `cd backend && python -m pytest -q` (precisa de ffmpeg no PATH)
- Backend dev: `cd backend && uvicorn app.main:app --reload`
- Mobile testes: `cd mobile && flutter test`
- APK: push em `main` → GitHub Actions publica APKs no branch `apk` e o log em `build-status`.

## Convenções
- TDD: teste falhando antes do código; DSP testado com sinais sintéticos de `tests/conftest.py` (`sung_tone`).
- Saída de áudio do backend: 48 kHz estéreo, pico −1 dBFS, alinhada ao início da guia.
- Atalhos deliberados marcados com `# shortcut: <limite>, <quando evoluir>`.
- Pacote FFmpeg do app: `ffmpeg_kit_flutter_new_min_gpl` (GPL por causa do libx264) — revisar licença antes de publicar na loja.
