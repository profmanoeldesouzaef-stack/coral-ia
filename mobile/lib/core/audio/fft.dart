import 'dart:math' as math;
import 'dart:typed_data';

/// FFT radix-2 iterativa in-place. [inverse] já divide por n.
void fft(Float64List re, Float64List im, {bool inverse = false}) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = 2 * math.pi / len * (inverse ? 1 : -1);
    final wr = math.cos(ang), wi = math.sin(ang);
    final half = len >> 1;
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var j = 0; j < half; j++) {
        final a = i + j, b = a + half;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
  if (inverse) {
    for (var i = 0; i < n; i++) {
      re[i] /= n;
      im[i] /= n;
    }
  }
}

int nextPow2(int v) {
  var p = 1;
  while (p < v) {
    p <<= 1;
  }
  return p;
}

/// Convolução linear por overlap-add (saída com len(x) + len(h) - 1 amostras).
Float32List convolve(Float32List x, Float32List h) {
  final m = h.length;
  final block = nextPow2(math.max(m, 4096));
  final size = block * 2;
  final hr = Float64List(size), hi = Float64List(size);
  for (var i = 0; i < m; i++) {
    hr[i] = h[i];
  }
  fft(hr, hi);

  final out = Float64List(x.length + m - 1);
  final re = Float64List(size), im = Float64List(size);
  for (var start = 0; start < x.length; start += block) {
    re.fillRange(0, size, 0);
    im.fillRange(0, size, 0);
    final end = math.min(start + block, x.length);
    for (var i = start; i < end; i++) {
      re[i - start] = x[i];
    }
    fft(re, im);
    for (var i = 0; i < size; i++) {
      final r = re[i] * hr[i] - im[i] * hi[i];
      im[i] = re[i] * hi[i] + im[i] * hr[i];
      re[i] = r;
    }
    fft(re, im, inverse: true);
    final limit = math.min(size, out.length - start);
    for (var i = 0; i < limit; i++) {
      out[start + i] += re[i];
    }
  }
  return Float32List.fromList(out);
}
