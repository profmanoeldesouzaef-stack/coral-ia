import 'dart:math' as math;

import '../project/project.dart';

const voiceEnhance =
    'highpass=f=80,acompressor=threshold=0.125:ratio=3:attack=10:release=200:makeup=2,equalizer=f=3000:t=q:w=1:g=3';
const videoEnhance = 'eq=brightness=0.03:contrast=1.04:saturation=1.06,hqdn3d=1.5:1.5:3:3';

String _n(double v) => v.toStringAsFixed(3);

/// Argumentos do FFmpeg para o vídeo final. Sem filtro de vídeo, o vídeo é copiado sem perda.
List<String> buildExportArgs(Project p, String output) {
  final args = <String>['-y', '-i', p.videoPath!];
  final filters = <String>[];
  final mix = <String>[];
  var input = 1;

  if (p.videoHasAudio) {
    filters.add('[0:a]${p.enhanceVoice ? '$voiceEnhance,' : ''}volume=${_n(p.originalVolume)}[a0]');
  } else {
    filters.add('anullsrc=r=44100:cl=stereo[a0]');
  }
  mix.add('[a0]');

  if (p.choirPath != null) {
    args.addAll(['-i', p.choirPath!]);
    final start = p.choirStart;
    final trim = start < 0 ? 'atrim=start=${_n(-start)},asetpts=PTS-STARTPTS,' : '';
    final length = p.choirSeconds - math.max(0.0, -start);
    final fadeOutAt = math.max(0.0, length - p.choirFadeOut);
    final delayMs = (math.max(0.0, start) * 1000).round();
    filters.add('[$input:a]${trim}afade=t=in:d=${_n(p.choirFadeIn)},'
        'afade=t=out:st=${_n(fadeOutAt)}:d=${_n(p.choirFadeOut)},'
        'adelay=$delayMs:all=1,volume=${_n(p.choirVolume)}[a1]');
    mix.add('[a1]');
    input++;
  }

  if (p.extraPath != null) {
    args.addAll(['-i', p.extraPath!]);
    filters.add('[$input:a]volume=${_n(p.extraVolume)}[a2]');
    mix.add('[a2]');
    input++;
  }

  filters.add('${mix.join()}amix=inputs=${mix.length}:duration=longest:normalize=0,alimiter=limit=0.95[aout]');
  if (p.enhanceVideo) filters.add('[0:v]$videoEnhance[vout]');

  args.addAll(['-filter_complex', filters.join(';'), '-map', p.enhanceVideo ? '[vout]' : '0:v', '-map', '[aout]']);
  args.addAll(p.enhanceVideo
      ? ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p']
      : ['-c:v', 'copy']);
  args.addAll(['-c:a', 'aac', '-b:a', '256k', '-t', _n(p.videoSeconds), '-movflags', '+faststart', output]);
  return args;
}
