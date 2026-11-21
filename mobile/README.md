# Coral IA — app Android (offline)

Tudo roda no celular: gravação da guia, geração do coral (8 vozes, PSOLA + reverb por convolução) e montagem do vídeo (FFmpeg). Não precisa de servidor nem internet.

## Como usar
1. **Gravar vídeo** ou **Escolher da galeria**.
2. Leve o vídeo até o trecho do coro, toque em **Gravar coro aqui** e cante uma vez (use fone).
3. Escolha o ambiente (Catedral, Igreja, Banheiro, Estádio) e toque em **Gerar coral**.
4. Ajuste na timeline: volume do áudio original, volume/fades/sincronia do coral, trilha extra.
5. **Exportar para a galeria** → álbum "Coral IA".

## Build
O APK é gerado pelo GitHub Actions (`.github/workflows/build-apk.yml`) a cada push em `main` e publicado no branch `apk`.
Local: `flutter create --platforms=android . && bash ../scripts/patch_android.sh && flutter build apk --split-per-abi`.

## Código
- `lib/core/audio/` — motor puro em Dart (YIN, PSOLA, FFT/convolução, WAV, `renderChoir`), testado em `test/`.
- `lib/features/` — telas (home, editor/timeline), serviço do coral (isolate) e exportação (FFmpeg + galeria).
- `assets/ir/` — respostas de impulso dos 4 ambientes (geradas por `backend/app/audio/reverb.py`).
