import 'dart:typed_data';

/// Áudio PCM em memória: um Float32List por canal, valores em [-1, 1].
class PcmAudio {
  PcmAudio(this.channels, this.sampleRate);
  final List<Float32List> channels;
  final int sampleRate;

  int get length => channels.isEmpty ? 0 : channels.first.length;

  /// Reamostragem linear (suficiente para alinhar a guia à taxa dos IRs).
  PcmAudio resample(int target) {
    if (target == sampleRate || length == 0) return this;
    final outLen = (length * target / sampleRate).round();
    final step = sampleRate / target;
    return PcmAudio([
      for (final ch in channels)
        Float32List.fromList(List.generate(outLen, (i) {
          final pos = i * step;
          final j = pos.floor();
          if (j + 1 >= ch.length) return ch[ch.length - 1];
          final f = pos - j;
          return ch[j] * (1 - f) + ch[j + 1] * f;
        })),
    ], target);
  }

  Float32List toMono() {
    if (channels.length == 1) return channels.first;
    final out = Float32List(length);
    for (final ch in channels) {
      for (var i = 0; i < out.length; i++) {
        out[i] += ch[i] / channels.length;
      }
    }
    return out;
  }
}

class WavFormatException implements Exception {
  WavFormatException(this.message);
  final String message;
  @override
  String toString() => 'WavFormatException: $message';
}

/// Lê WAV PCM 16/24/32-bit ou float32.
PcmAudio decodeWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw WavFormatException('não é um arquivo WAV');
  }
  int? format, numChannels, sampleRate, bits;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    var size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      format = data.getUint16(body, Endian.little);
      numChannels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
      if (format == 0xFFFE && size >= 26) {
        format = data.getUint16(body + 24, Endian.little); // WAVE_FORMAT_EXTENSIBLE
      }
    } else if (id == 'data') {
      if (format == null) throw WavFormatException('chunk fmt ausente');
      // Gravadores às vezes deixam o tamanho zerado/errado: usa o que existe.
      if (size == 0 || body + size > bytes.length) size = bytes.length - body;
      return _readSamples(data, body, size, format, numChannels!, sampleRate!, bits!);
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw WavFormatException('chunk data ausente');
}

PcmAudio _readSamples(ByteData data, int start, int size, int format, int nch, int sr, int bits) {
  final bytesPer = bits ~/ 8;
  final frames = size ~/ (bytesPer * nch);
  final chans = List.generate(nch, (_) => Float32List(frames));
  var p = start;
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < nch; c++) {
      double v;
      if (format == 3 && bits == 32) {
        v = data.getFloat32(p, Endian.little);
      } else if (format == 1 && bits == 16) {
        v = data.getInt16(p, Endian.little) / 32768.0;
      } else if (format == 1 && bits == 24) {
        var x = data.getUint8(p) | (data.getUint8(p + 1) << 8) | (data.getUint8(p + 2) << 16);
        if (x & 0x800000 != 0) x -= 0x1000000;
        v = x / 8388608.0;
      } else if (format == 1 && bits == 32) {
        v = data.getInt32(p, Endian.little) / 2147483648.0;
      } else {
        throw WavFormatException('formato não suportado (fmt=$format, $bits bits)');
      }
      chans[c][i] = v;
      p += bytesPer;
    }
  }
  return PcmAudio(chans, sr);
}

/// Escreve WAV PCM 16-bit intercalado.
Uint8List encodeWav16(PcmAudio audio) {
  final nch = audio.channels.length;
  final n = audio.length;
  final dataSize = n * nch * 2;
  final out = ByteData(44 + dataSize);
  void str(int o, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  out.setUint32(4, 36 + dataSize, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, nch, Endian.little);
  out.setUint32(24, audio.sampleRate, Endian.little);
  out.setUint32(28, audio.sampleRate * nch * 2, Endian.little);
  out.setUint16(32, nch * 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  str(36, 'data');
  out.setUint32(40, dataSize, Endian.little);
  var p = 44;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < nch; c++) {
      final v = (audio.channels[c][i] * 32767).round().clamp(-32768, 32767);
      out.setInt16(p, v, Endian.little);
      p += 2;
    }
  }
  return out.buffer.asUint8List();
}
