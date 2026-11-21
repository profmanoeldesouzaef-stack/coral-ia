# Etapa 1 — Núcleo de coral (Modo B manual) — Design

## Intenção
O usuário grava uma guia cantada no celular; o backend devolve uma faixa de coral
(8 vozes + ambiente) alinhada ao início da guia, pronta para a Faixa 3 da timeline.

## Objetivos
- `POST /api/v1/generate-choir` recebe a guia (wav/m4a/aac/mp3/ogg/flac) e devolve WAV 24-bit ou AAC (.m4a).
- 8 vozes: 2 Soprano, 2 Contralto, 2 Tenor, 2 Baixo.
- Cada voz: deslocamento de pitch (semitons + cents), formante próprio, micro-atraso aleatório 5–30 ms, pan estéreo.
- Reverb por convolução: `catedral`, `igreja`, `banheiro`, `estadio`.

## Não-objetivos (Etapa 1)
Modo A (Whisper/letras/Demucs), 10–25 vozes, filas assíncronas, autenticação, telas Flutter.

## Abordagens consideradas
1. **DSP clássico em numpy/librosa (escolhida):** roda em CPU, sem GPU, sem modelos, testável. Soa como "doubling" coral, não como cantores distintos.
2. RVC/So-VITS: timbres realmente diferentes, mas exige modelos treinados e GPU. Fica para etapa posterior, atrás da mesma interface `render_choir`.
3. API paga (Kits.ai/ElevenLabs): custo por chamada e dependência externa; fora do MVP.

## Decisões de implementação (minhas, corrigíveis)
- **Naipe por oitava, não por intervalo:** sem saber a tonalidade, terças/quintas podem soar dissonantes. Detecto o f0 mediano da guia (pYIN) e escolho, para cada naipe, a oitava (múltiplo de 12 semitons) mais próxima do centro do naipe (S≈523 Hz, A≈349 Hz, T≈220 Hz, B≈131 Hz). O desafinado de ±4–14 cents gera o efeito de coro.
- **Formante:** pitch shift (phase vocoder) desloca formantes junto; corrijo o envelope espectral (cepstro) para o fator do naipe (S 1.10, A 1.04, T 0.96, B 0.90).
- **IRs:** se existir `assets/ir/<preset>.wav` (IR real), uso; senão gero IR sintético estéreo (RT60, pré-delay, reflexões iniciais, amortecimento de agudos por preset).
- **Saída** em 48 kHz estéreo, início alinhado com a guia; cauda de reverb anexada e informada no header `X-Choir-Tail-Seconds`.
- **Seed** opcional para reproduzir o mesmo resultado.
- Limites: 25 MB, 0,5–120 s de áudio.
