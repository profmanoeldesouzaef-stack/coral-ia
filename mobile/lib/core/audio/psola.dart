import 'dart:math' as math;
import 'dart:typed_data';

import 'pitch.dart';

/// TD-PSOLA: muda o tom por [ratio] preservando o timbre; [formant] > 1 clareia,
/// < 1 escurece (reamostra cada grão). Mantém o comprimento do sinal.
Float32List psola(Float32List x, int sr, PitchTrack track, double ratio, {double formant = 1.0}) {
  final n = x.length;
  final unvoiced = sr ~/ 200;

  ({int p, bool voiced}) periodAt(int t) {
    final f = track.at(t);
    return f > 0 ? (p: (sr / f).round(), voiced: true) : (p: unvoiced, voiced: false);
  }

  // Marcas de análise, uma por período.
  final marks = <int>[];
  for (var t = 0; t < n;) {
    marks.add(t);
    t += periodAt(t).p;
  }

  final out = Float64List(n + 4 * sr ~/ 100);
  final windows = <int, Float64List>{};
  Float64List hann(int len) => windows.putIfAbsent(
        len,
        () => Float64List.fromList(
          List.generate(len, (i) => 0.5 - 0.5 * math.cos(2 * math.pi * (i + 1) / (len + 1))),
        ),
      );

  var k = 0;
  var ts = 0.0;
  while (ts < n) {
    while (k + 1 < marks.length && (marks[k + 1] - ts).abs() <= (marks[k] - ts).abs()) {
      k++;
    }
    final m = marks[k];
    final per = periodAt(m);
    final p = per.p;
    final len = 2 * p;
    final w = hann(len);
    final gain = per.voiced ? 1.0 / ratio : 1.0; // sobreposição média dos grãos = ratio
    var grain = Float64List(len);
    for (var i = 0; i < len; i++) {
      final idx = m - p + i;
      if (idx >= 0 && idx < n) grain[i] = x[idx] * w[i] * gain;
    }
    if (formant != 1.0 && per.voiced) {
      final l2 = math.max(4, (len / formant).round());
      final res = Float64List(l2);
      for (var i = 0; i < l2; i++) {
        final pos = i * (len - 1) / (l2 - 1);
        final j = pos.floor();
        final fr = pos - j;
        res[i] = j + 1 < len ? grain[j] * (1 - fr) + grain[j + 1] * fr : grain[len - 1];
      }
      grain = res;
    }
    final start = ts.round() - grain.length ~/ 2;
    for (var i = 0; i < grain.length; i++) {
      final o = start + i;
      if (o >= 0 && o < out.length) out[o] += grain[i];
    }
    ts += per.voiced ? p / ratio : p;
  }

  final result = Float32List(n);
  for (var i = 0; i < n; i++) {
    result[i] = out[i];
  }
  return result;
}
