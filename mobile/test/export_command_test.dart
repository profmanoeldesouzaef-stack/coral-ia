import 'package:coral_ia/features/export/export_command.dart';
import 'package:coral_ia/features/project/project.dart';
import 'package:flutter_test/flutter_test.dart';

String graph(List<String> a) => a[a.indexOf('-filter_complex') + 1];

void main() {
  const base = Project(videoPath: 'v.mp4', videoSeconds: 12.5);

  test('sem coral e sem filtros: copia o vídeo sem perda', () {
    final a = buildExportArgs(base, 'o.mp4');
    expect(a.sublist(a.indexOf('-c:v'), a.indexOf('-c:v') + 2), ['-c:v', 'copy']);
    expect(graph(a), '[0:a]volume=1.000[a0];[a0]amix=inputs=1:duration=longest:normalize=0,alimiter=limit=0.95[aout]');
    expect(a.last, 'o.mp4');
    expect(a[a.indexOf('-t') + 1], '12.500');
  });

  test('coral entra no segundo certo com fades e volume', () {
    final p = base.copyWith(choirPath: 'c.wav', choirSeconds: 6, guideOffset: 3, choirNudge: -0.2, choirVolume: 0.7);
    final g = graph(buildExportArgs(p, 'o.mp4'));
    expect(g, contains('[1:a]afade=t=in:d=0.300,afade=t=out:st=4.500:d=1.500,adelay=2800:all=1,volume=0.700[a1]'));
    expect(g, contains('[a0][a1]amix=inputs=2'));
  });

  test('ajuste negativo antes do início do vídeo corta o começo do coral', () {
    final p = base.copyWith(choirPath: 'c.wav', choirSeconds: 6, guideOffset: 0.1, choirNudge: -0.5);
    final g = graph(buildExportArgs(p, 'o.mp4'));
    expect(g, contains('atrim=start=0.400,asetpts=PTS-STARTPTS,'));
    expect(g, contains('adelay=0:all=1'));
  });

  test('vídeo sem áudio usa silêncio; trilha extra vira terceira entrada', () {
    final p = base.copyWith(videoHasAudio: false, choirPath: 'c.wav', choirSeconds: 4, extraPath: 'm.mp3');
    final g = graph(buildExportArgs(p, 'o.mp4'));
    expect(g, startsWith('anullsrc=r=44100:cl=stereo[a0]'));
    expect(g, contains('[2:a]volume=0.400[a2]'));
    expect(g, contains('[a0][a1][a2]amix=inputs=3'));
  });

  test('melhorias de voz e vídeo', () {
    final a = buildExportArgs(base.copyWith(enhanceVoice: true, enhanceVideo: true), 'o.mp4');
    expect(graph(a), contains('[0:a]$voiceEnhance,volume'));
    expect(graph(a), contains('[0:v]$videoEnhance[vout]'));
    expect(a, containsAllInOrder(['-map', '[vout]', '-c:v', 'libx264']));
  });
}
