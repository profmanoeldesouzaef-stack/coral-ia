# Coral IA — backend (Etapa 1, Modo B)

## Rodar local
```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install fastapi "uvicorn[standard]" python-multipart numpy scipy librosa soundfile pytest httpx
# Modo A (Demucs) depois: pip install -r requirements.txt  (torch é grande; veja o comentário no arquivo)
# ffmpeg no PATH: necessário para receber m4a/aac/mp3 e para output_format=aac
uvicorn app.main:app --reload --port 8000
```
Docs interativas: http://localhost:8000/docs

## Testar
```bash
python -m pytest -q
curl -F file=@guia.m4a -F environment=catedral -F output_format=aac -F seed=11 \
     -o coral.m4a -D - http://localhost:8000/api/v1/generate-choir
```

## `POST /api/v1/generate-choir` (multipart/form-data)
| Campo | Valores | Padrão |
|---|---|---|
| `file` | wav, flac, ogg (direto); m4a, aac, mp3 (via ffmpeg) | — |
| `environment` | `catedral`, `igreja`, `banheiro`, `estadio` | `igreja` |
| `output_format` | `wav` (PCM 24-bit) ou `aac` (.m4a 256 kbps) | `wav` |
| `seed` | inteiro ≥ 0 — repete o mesmo coral | aleatório |

Resposta: áudio 48 kHz estéreo, **começa no mesmo instante da guia** (coloque na timeline no mesmo offset em que a guia foi gravada). Headers: `X-Choir-Tail-Seconds` (cauda de reverb após o fim da guia), `X-Choir-Seed`, `X-Choir-Voices`, `X-Choir-Sample-Rate`.

Erros: 413 (> 25 MB), 415 (arquivo ilegível), 422 (duração fora de 0,5–120 s, sem voz detectada ou parâmetro inválido), 503 (AAC pedido sem ffmpeg).

## IRs reais
Coloque `assets/ir/<preset>.wav` (ex.: `catedral.wav`) e ele substitui o IR sintético. Qualquer sample rate, mono ou estéreo.

## Configuração (env)
`CHOIR_MAX_UPLOAD_MB` (25), `CHOIR_MIN_SECONDS` (0.5), `CHOIR_MAX_SECONDS` (120), `CHOIR_IR_DIR`.

## Como o coral é gerado
`app/audio/voices.py` detecta o f0 da guia (pYIN) e cria 2 vozes por naipe na oitava mais próxima do centro de cada naipe, com ±4–14 cents de desafinação, formante próprio, atraso 5–30 ms, pan e ganho aleatórios. `dsp.py` faz pitch shift (phase vocoder) e recoloca os formantes via "true envelope" cepstral. `reverb.py` convolui com o IR. `choir.py` mixa e normaliza a −1 dBFS.
