import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/audio/choir_engine.dart';
import '../../core/audio/wav.dart';

/// Ambientes e o nível do reverb de cada um.
const environments = {
  'catedral': ('Catedral', 0.55),
  'igreja': ('Igreja', 0.45),
  'banheiro': ('Banheiro', 0.40),
  'estadio': ('Estádio', 0.45),
};

typedef _Rendered = ({Uint8List? bytes, double seconds, double tail, String? error});

class ChoirFile {
  ChoirFile(this.path, this.seconds, this.tailSeconds);
  final String path;
  final double seconds;
  final double tailSeconds;
}

class ChoirException implements Exception {
  ChoirException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gera o coral fora da thread da interface e salva um WAV estéreo.
Future<ChoirFile> generateChoir({required String guidePath, required String environment, required int seed}) async {
  final guideBytes = await File(guidePath).readAsBytes();
  final irBytes = (await rootBundle.load('assets/ir/$environment.wav')).buffer.asUint8List();
  final wet = environments[environment]!.$2;

  final result = await Isolate.run<_Rendered>(() {
    try {
      final ir = decodeWav(irBytes);
      final guide = decodeWav(guideBytes).resample(ir.sampleRate);
      final r = renderChoir(guide, ir, wet: wet, seed: seed);
      return (bytes: encodeWav16(r.audio), seconds: r.audio.length / r.audio.sampleRate, tail: r.tailSeconds, error: null);
    } on NoVoiceException catch (e) {
      return (bytes: null, seconds: 0.0, tail: 0.0, error: e.toString());
    } on WavFormatException catch (e) {
      return (bytes: null, seconds: 0.0, tail: 0.0, error: 'Gravação ilegível: ${e.message}');
    }
  });
  if (result.error != null) throw ChoirException(result.error!);

  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/coral_${DateTime.now().millisecondsSinceEpoch}.wav');
  await file.writeAsBytes(result.bytes!);
  return ChoirFile(file.path, result.seconds, result.tail);
}
