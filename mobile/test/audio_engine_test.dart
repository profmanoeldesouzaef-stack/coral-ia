import 'dart:math' as math;
import 'dart:typed_data';

import 'package:coral_ia/core/audio/choir_engine.dart';
import 'package:coral_ia/core/audio/fft.dart';
import 'package:coral_ia/core/audio/pitch.dart';
import 'package:coral_ia/core/audio/psola.dart';
import 'package:coral_ia/core/audio/wav.dart';
import 'package:flutter_test/flutter_test.dart';

const sr = 44100;

/// Vogal /a/ sintética: harmônicos com ressonâncias de Lorentz e vibrato leve.
Float32List sungTone(double f0, double seconds) {
  final n = (seconds * sr).round();
  final y = Float64List(n);
  const formants = [(800.0, 90.0), (1150.0, 110.0), (2900.0, 160.0)];
  final amps = <double>[];
  for (var h = 1; h < 8000 / f0; h++) {
    final f = h * f0;
    var a = 0.0;
    for (final (fc, bw) in formants) {
      a += 1 / (1 + math.pow((f - fc) / bw, 2));
    }
    amps.add(a / math.sqrt(h));
  }
  var phase = 0.0, peak = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    phase += 2 * math.pi * f0 * (1 + 0.004 * math.sin(2 * math.pi * 5.5 * t)) / sr;
    var s = 0.0;
    for (var h = 0; h < amps.length; h++) {
      s += amps[h] * math.sin((h + 1) * phase);
    }
    y[i] = s;
    peak = math.max(peak, s.abs());
  }
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final fade = math.min(1.0, math.min(t, (n - i) / sr) / 0.05);
    out[i] = 0.5 * y[i] / peak * fade;
  }
  return out;
}

double measuredF0(Float32List y) => yinTrack(y, sr).median()!;

void main() {
  final tone = sungTone(196, 2.0);
  final track = yinTrack(tone, sr);

  group('pitch', () {
    test('YIN encontra o f0 cantado', () {
      expect(track.median(), closeTo(196, 196 * 0.02));
    });
    test('silêncio não tem voz', () {
      expect(yinTrack(Float32List(sr), sr).median(), isNull);
    });
    test('ruído não tem voz', () {
      final rng = math.Random(0);
      final noise = Float32List.fromList(List.generate(sr, (_) => (rng.nextDouble() - 0.5) * 0.3));
      expect(yinTrack(noise, sr).median(), isNull);
    });
  });

  group('psola', () {
    for (final st in [12.0, -12.0, 7.0, -5.0]) {
      test('desloca $st semitons', () {
        final y = psola(tone, sr, track, math.pow(2, st / 12).toDouble());
        expect(y.length, tone.length);
        expect(measuredF0(y), closeTo(196 * math.pow(2, st / 12), 196 * math.pow(2, st / 12) * 0.02));
      });
    }
    test('formante não muda o tom', () {
      final y = psola(tone, sr, track, 1.0, formant: 1.15);
      expect(measuredF0(y), closeTo(196, 4));
    });
  });

  group('fft', () {
    test('convolução bate com a direta', () {
      final rng = math.Random(1);
      final x = Float32List.fromList(List.generate(9000, (_) => rng.nextDouble() - 0.5));
      final h = Float32List.fromList(List.generate(300, (_) => rng.nextDouble() - 0.5));
      final fast = convolve(x, h);
      expect(fast.length, x.length + h.length - 1);
      for (final i in [0, 299, 4500, 9298]) {
        var s = 0.0;
        for (var k = 0; k < h.length; k++) {
          if (i - k >= 0 && i - k < x.length) s += x[i - k] * h[k];
        }
        expect(fast[i], closeTo(s, 1e-4));
      }
    });
  });

  group('wav', () {
    test('ida e volta 16-bit estéreo', () {
      final a = PcmAudio([Float32List.fromList([0, 0.5, -0.5]), Float32List.fromList([0.25, -1, 1])], 44100);
      final b = decodeWav(encodeWav16(a));
      expect(b.sampleRate, 44100);
      expect(b.channels.length, 2);
      expect(b.channels[1][1], closeTo(-1, 1e-3));
      expect(b.channels[0][1], closeTo(0.5, 1e-3));
    });
    test('arquivo que não é wav dá erro claro', () {
      expect(() => decodeWav(Uint8List.fromList([1, 2, 3])), throwsA(isA<WavFormatException>()));
    });
  });

  group('coral', () {
    final ir = PcmAudio([
      Float32List.fromList(List.generate(4410, (i) => math.exp(-i / 800) * (i.isEven ? 1 : -1))),
      Float32List.fromList(List.generate(4410, (i) => math.exp(-i / 800) * (i % 3 == 0 ? 1 : -1))),
    ], sr);

    test('8 vozes, 2 por naipe, parâmetros nos limites', () {
      final v = buildVoices(220, math.Random(2));
      expect(v.length, 8);
      for (final s in sections) {
        expect(v.where((x) => x.section == s.name).length, 2);
      }
      for (final x in v) {
        expect(x.delayMs, inInclusiveRange(5, 30));
        final sung = 220 * math.pow(2, x.semitones / 12);
        final c = sections.firstWhere((s) => s.name == x.section).centerHz;
        expect(sung, inInclusiveRange(c / math.sqrt2, c * math.sqrt2));
      }
    });

    test('renderiza estéreo normalizado, com cauda e atraso inicial', () {
      final lead = Float32List(sr ~/ 2);
      final guide = Float32List.fromList([...lead, ...sungTone(220, 1.0)]);
      final r = renderChoir(PcmAudio([guide], sr), ir, wet: 0.4, seed: 5);
      expect(r.audio.channels.length, 2);
      expect(r.audio.length, greaterThan(guide.length));
      var peak = 0.0;
      var onset = -1;
      for (var i = 0; i < r.audio.length; i++) {
        final v = math.max(r.audio.channels[0][i].abs(), r.audio.channels[1][i].abs());
        peak = math.max(peak, v);
      }
      for (var i = 0; i < r.audio.length; i++) {
        if (math.max(r.audio.channels[0][i].abs(), r.audio.channels[1][i].abs()) > 0.05 * peak) {
          onset = i;
          break;
        }
      }
      expect(peak, closeTo(peakLinear, 1e-3));
      expect(onset / sr, inInclusiveRange(0.5 + 0.005 - 0.01, 0.5 + 0.03 + 0.06));
    });

    test('mesmo seed, mesmo coral', () {
      final g = PcmAudio([sungTone(220, 0.8)], sr);
      final a = renderChoir(g, ir, wet: 0.4, seed: 9).audio.channels[0];
      final b = renderChoir(g, ir, wet: 0.4, seed: 9).audio.channels[0];
      expect(a, b);
    });

    test('silêncio vira NoVoiceException', () {
      expect(() => renderChoir(PcmAudio([Float32List(sr)], sr), ir, wet: 0.4, seed: 1),
          throwsA(isA<NoVoiceException>()));
    });
  });
}
