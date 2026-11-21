import 'dart:math' as math;
import 'dart:typed_data';

/// f0 por frame (0 = sem voz); frame i cobre a amostra i * hop.
class PitchTrack {
  PitchTrack(this.f0, this.hop);
  final List<double> f0;
  final int hop;

  double at(int sample) {
    if (f0.isEmpty) return 0;
    final i = (sample ~/ hop).clamp(0, f0.length - 1);
    return f0[i];
  }

  /// f0 mediano dos frames com voz; null se a voz cobrir < 10% (ou < 5 frames).
  double? median() {
    final voiced = f0.where((f) => f > 0).toList()..sort();
    if (voiced.length < math.max(5, 0.1 * f0.length)) return null;
    return voiced[voiced.length ~/ 2];
  }
}

const _decim = 4;
const _win = 512;
const _hopD = 128;

/// YIN sobre o sinal decimado por 4 (rápido o bastante para o celular).
PitchTrack yinTrack(Float32List x, int sr, {double fmin = 70, double fmax = 1000, double threshold = 0.15}) {
  final n = x.length ~/ _decim;
  final d = Float64List(n);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (var k = 0; k < _decim; k++) {
      s += x[i * _decim + k];
    }
    d[i] = s / _decim;
  }
  final dsr = sr / _decim;
  final tmin = (dsr / fmax).floor();
  final tmax = math.min((dsr / fmin).floor(), _win - 1);

  var total = 0.0;
  for (final v in d) {
    total += v * v;
  }
  final rmsAll = math.sqrt(total / math.max(1, n)) + 1e-12;

  final f0 = <double>[];
  final diff = Float64List(tmax + 1);
  final cm = Float64List(tmax + 1);
  for (var s = 0; s < math.max(1, n - _win - tmax); s += _hopD) {
    if (s + _win + tmax > n) {
      f0.add(0);
      continue;
    }
    var e = 0.0, peak = 0.0;
    for (var i = 0; i < _win; i++) {
      e += d[s + i] * d[s + i];
      peak = math.max(peak, d[s + i].abs());
    }
    if (math.sqrt(e / _win) < 0.1 * rmsAll || peak < 1e-3) {
      f0.add(0);
      continue;
    }
    for (var t = 0; t <= tmax; t++) {
      var acc = 0.0;
      for (var i = 0; i < _win; i++) {
        final dv = d[s + i] - d[s + i + t];
        acc += dv * dv;
      }
      diff[t] = acc;
    }
    cm[0] = 1;
    var run = 0.0;
    for (var t = 1; t <= tmax; t++) {
      run += diff[t];
      cm[t] = run > 0 ? diff[t] * t / run : 1;
    }
    var tau = -1;
    for (var t = tmin; t <= tmax; t++) {
      if (cm[t] < threshold) {
        while (t + 1 <= tmax && cm[t + 1] < cm[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 0) {
      f0.add(0);
      continue;
    }
    var refined = tau.toDouble();
    if (tau >= 1 && tau < tmax) {
      final a = cm[tau - 1], b = cm[tau], c = cm[tau + 1];
      final den = a - 2 * b + c;
      if (den != 0) refined += 0.5 * (a - c) / den;
    }
    f0.add(dsr / refined);
  }
  return PitchTrack(f0, _hopD * _decim);
}
