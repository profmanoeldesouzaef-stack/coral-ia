import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../project/project.dart';
import 'export_command.dart';

class ExportException implements Exception {
  ExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// true se o arquivo de vídeo tem trilha de áudio.
Future<bool> videoHasAudio(String path) async {
  final session = await FFprobeKit.getMediaInformation(path);
  final streams = session.getMediaInformation()?.getStreams() ?? [];
  return streams.any((s) => s.getType() == 'audio');
}

/// Renderiza o vídeo final e salva na galeria. Retorna o caminho do arquivo.
Future<String> exportToGallery(Project p) async {
  final dir = await getTemporaryDirectory();
  final out = '${dir.path}/coral_${DateTime.now().millisecondsSinceEpoch}.mp4';
  final session = await FFmpegKit.executeWithArguments(buildExportArgs(p, out));
  final code = await session.getReturnCode();
  if (!ReturnCode.isSuccess(code)) {
    final logs = await session.getAllLogsAsString() ?? '';
    final tail = logs.length > 400 ? logs.substring(logs.length - 400) : logs;
    throw ExportException('Falha ao gerar o vídeo.\n$tail');
  }
  if (!await Gal.hasAccess()) await Gal.requestAccess();
  await Gal.putVideo(out, album: 'Coral IA');
  return out;
}
