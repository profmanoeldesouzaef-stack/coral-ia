import 'package:flutter_riverpod/flutter_riverpod.dart';

const _keep = Object();

/// Tudo o que define o vídeo final. Imutável; alterações via [ProjectController].
class Project {
  const Project({
    this.videoPath,
    this.videoHasAudio = true,
    this.videoSeconds = 0,
    this.guidePath,
    this.guideOffset = 0,
    this.choirPath,
    this.choirSeconds = 0,
    this.environment = 'igreja',
    this.originalVolume = 1.0,
    this.choirVolume = 0.8,
    this.choirFadeIn = 0.3,
    this.choirFadeOut = 1.5,
    this.choirNudge = 0,
    this.extraPath,
    this.extraVolume = 0.4,
    this.enhanceVoice = false,
    this.enhanceVideo = false,
  });

  final String? videoPath;
  final bool videoHasAudio;
  final double videoSeconds;
  final String? guidePath;
  final double guideOffset; // segundo do vídeo em que a guia começou
  final String? choirPath;
  final double choirSeconds;
  final String environment;
  final double originalVolume;
  final double choirVolume;
  final double choirFadeIn;
  final double choirFadeOut;
  final double choirNudge; // ajuste fino de sincronia, em segundos
  final String? extraPath;
  final double extraVolume;
  final bool enhanceVoice;
  final bool enhanceVideo;

  /// Onde o coral começa na timeline.
  double get choirStart => guideOffset + choirNudge;

  Project copyWith({
    Object? videoPath = _keep,
    bool? videoHasAudio,
    double? videoSeconds,
    Object? guidePath = _keep,
    double? guideOffset,
    Object? choirPath = _keep,
    double? choirSeconds,
    String? environment,
    double? originalVolume,
    double? choirVolume,
    double? choirFadeIn,
    double? choirFadeOut,
    double? choirNudge,
    Object? extraPath = _keep,
    double? extraVolume,
    bool? enhanceVoice,
    bool? enhanceVideo,
  }) =>
      Project(
        videoPath: identical(videoPath, _keep) ? this.videoPath : videoPath as String?,
        videoHasAudio: videoHasAudio ?? this.videoHasAudio,
        videoSeconds: videoSeconds ?? this.videoSeconds,
        guidePath: identical(guidePath, _keep) ? this.guidePath : guidePath as String?,
        guideOffset: guideOffset ?? this.guideOffset,
        choirPath: identical(choirPath, _keep) ? this.choirPath : choirPath as String?,
        choirSeconds: choirSeconds ?? this.choirSeconds,
        environment: environment ?? this.environment,
        originalVolume: originalVolume ?? this.originalVolume,
        choirVolume: choirVolume ?? this.choirVolume,
        choirFadeIn: choirFadeIn ?? this.choirFadeIn,
        choirFadeOut: choirFadeOut ?? this.choirFadeOut,
        choirNudge: choirNudge ?? this.choirNudge,
        extraPath: identical(extraPath, _keep) ? this.extraPath : extraPath as String?,
        extraVolume: extraVolume ?? this.extraVolume,
        enhanceVoice: enhanceVoice ?? this.enhanceVoice,
        enhanceVideo: enhanceVideo ?? this.enhanceVideo,
      );
}

class ProjectController extends Notifier<Project> {
  @override
  Project build() => const Project();

  void newVideo(String path) => state = Project(videoPath: path);
  void edit(Project Function(Project p) change) => state = change(state);
}

final projectProvider = NotifierProvider<ProjectController, Project>(ProjectController.new);
