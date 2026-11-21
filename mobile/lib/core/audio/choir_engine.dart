import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'pitch.dart';
import 'psola.dart';
import 'wav.dart';

class NoVoiceException implements Exception {
  @override
  String toString() => 'Não encontrei voz cantada na gravação. Cante mais perto do microfone.';
}

class Section {
  const Section(this.name, this.centerHz, this.formant);
  final String name;
  final double centerHz;
  final double formant;
}

const sections = [
  Section('soprano', 523, 1.10),
  Section('contralto', 349, 1.04),
  Section('tenor', 220, 0.96),
  Section('baixo', 131, 0.90),
];

class Voice {
  Voice(this.section, this.semitones, this.formant, this.delayMs, this.pan, this.gain);
  final String section;
  final double semitones;
  final double formant;
  final double delayMs;
  final double pan;
  final double gain;
}

/// 2 vozes por naipe, na oitava da guia mais próxima do centro do naipe
/// (oitavas e não terças: a tonalidade da música é desconhecida).
List<Voice> buildVoices(double guideF0, math.Random rng, {int perSection = 2}) {
  double uni(double a, double b) => a + rng.nextDouble() * (b - a);
  final voices = <Voice>[];
  for (final s in sections) {
    final octaves = (math.log(s.centerHz / guideF0) / math.ln2).round();
    for (var i = 0; i < perSection; i++) {
      final cents = uni(4, 14) * (rng.nextBool() ? 1 : -1);
      voices.add(Voice(s.name, 12.0 * octaves + cents / 100, s.formant * uni(0.98, 1.02), uni(5, 30),
          uni(-0.8, 0.8), uni(0.8, 1.0)));
    }
  }
  return voices;
}

class ChoirResult {
  ChoirResult(this.audio, this.tailSeconds, this.voices);
  final PcmAudio audio;
  final double tailSeconds;
  final List<Voice> voices;
}

const peakLinear = 0.89; // -1 dBFS

/// Guia -> vozes -> mix estéreo -> reverb (IR) -> normaliza. Saída alinhada ao início da guia.
ChoirResult renderChoir(PcmAudio guide, PcmAudio ir, {required double wet, required int seed}) {
  if (ir.sampleRate != guide.sampleRate) {
    throw ArgumentError('IR (${ir.sampleRate} Hz) e guia (${guide.sampleRate} Hz) precisam da mesma taxa');
  }
  final sr = guide.sampleRate;
  final x = guide.toMono();
  final track = yinTrack(x, sr);
  final f0 = track.median();
  if (f0 == null) throw NoVoiceException();

  final voices = buildVoices(f0, math.Random(seed));
  final n = x.length;
  final dryLen = n + (30 * sr ~/ 1000) + 1;
  final left = Float32List(dryLen), right = Float32List(dryLen);
  for (final v in voices) {
    final y = psola(x, sr, track, math.pow(2, v.semitones / 12).toDouble(), formant: v.formant);
    final delay = (v.delayMs * sr / 1000).round();
    final angle = (v.pan + 1) * math.pi / 4;
    final gl = v.gain * math.cos(angle), gr = v.gain * math.sin(angle);
    for (var i = 0; i < n; i++) {
      left[i + delay] += y[i] * gl;
      right[i + delay] += y[i] * gr;
    }
  }

  final irL = _unitEnergy(ir.channels.first);
  final irR = _unitEnergy(ir.channels.length > 1 ? ir.channels[1] : ir.channels.first);
  final wetL = convolve(left, irL), wetR = convolve(right, irR);
  final outL = Float32List(wetL.length), outR = Float32List(wetR.length);
  var peak = 1e-9;
  for (var i = 0; i < outL.length; i++) {
    outL[i] = wetL[i] * wet + (i < dryLen ? left[i] : 0);
    outR[i] = wetR[i] * wet + (i < dryLen ? right[i] : 0);
    peak = math.max(peak, math.max(outL[i].abs(), outR[i].abs()));
  }
  final g = peakLinear / peak;
  for (var i = 0; i < outL.length; i++) {
    outL[i] *= g;
    outR[i] *= g;
  }
  return ChoirResult(PcmAudio([outL, outR], sr), (outL.length - n) / sr, voices);
}

Float32List _unitEnergy(Float32List h) {
  var e = 0.0;
  for (final v in h) {
    e += v * v;
  }
  final s = 1 / math.sqrt(math.max(e, 1e-12));
  return Float32List.fromList([for (final v in h) v * s]);
}
