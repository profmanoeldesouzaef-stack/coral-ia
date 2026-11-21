import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../choir/choir_service.dart';
import '../export/export_service.dart';
import '../project/project.dart';
import 'timeline.dart';

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  VideoPlayerController? _video;
  final _recorder = AudioRecorder();
  final _choir = AudioPlayer();
  final _extra = AudioPlayer();
  Timer? _choirTimer;
  bool _recording = false;
  bool _playing = false;
  double _recStart = 0;
  String? _busy;

  Project get _p => ref.read(projectProvider);
  void _update(Project Function(Project p) f) => ref.read(projectProvider.notifier).edit(f);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = _p.videoPath!;
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    controller.addListener(_onVideoTick);
    final hasAudio = await videoHasAudio(path).catchError((_) => true);
    if (!mounted) return;
    _update((p) => p.copyWith(
          videoHasAudio: hasAudio,
          videoSeconds: controller.value.duration.inMilliseconds / 1000,
        ));
    setState(() => _video = controller);
  }

  void _onVideoTick() {
    final c = _video;
    if (c == null) return; // listener pode disparar antes do controller ser atribuído
    final v = c.value;
    final ended = v.duration > Duration.zero && v.position >= v.duration;
    if (ended && _recording) _toggleRecord();
    if (ended && _playing) _stopPreview();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _choirTimer?.cancel();
    _video?.dispose();
    _recorder.dispose();
    _choir.dispose();
    _extra.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  double get _position => (_video?.value.position.inMilliseconds ?? 0) / 1000;

  // ---------- Gravação da guia (Modo B) ----------
  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      await _video!.pause();
      setState(() => _recording = false);
      if (path != null) {
        _update((p) => p.copyWith(guidePath: path, guideOffset: _recStart, choirPath: null, choirNudge: 0));
        _snack('Guia gravada. Agora toque em "Gerar coral".');
      }
      return;
    }
    if (!await _recorder.hasPermission()) {
      _snack('Permita o acesso ao microfone para gravar o coro.');
      return;
    }
    await _stopPreview();
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/guia_${DateTime.now().millisecondsSinceEpoch}.wav';
    _recStart = _position;
    await _video!.setVolume(_p.videoHasAudio ? _p.originalVolume : 0);
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1),
      path: path,
    );
    await _video!.play();
    setState(() => _recording = true);
  }

  // ---------- Coral ----------
  Future<void> _generate() async {
    await _stopPreview();
    setState(() => _busy = 'Gerando o coral de 8 vozes…');
    try {
      final c = await generateChoir(
        guidePath: _p.guidePath!,
        environment: _p.environment,
        seed: math.Random().nextInt(1 << 31),
      );
      await _choir.setFilePath(c.path);
      _update((p) => p.copyWith(choirPath: c.path, choirSeconds: c.seconds));
      _snack('Coral pronto! Toque no play para ouvir.');
    } on ChoirException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Não consegui gerar o coral: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ---------- Pré-escuta ----------
  Future<void> _togglePreview() async => _playing ? _stopPreview() : _startPreview();

  Future<void> _startPreview() async {
    final p = _p;
    final v = _video!;
    if (v.value.position >= v.value.duration) await v.seekTo(Duration.zero);
    final pos = _position;
    await v.setVolume(p.videoHasAudio ? p.originalVolume : 0);
    if (p.choirPath != null) {
      await _choir.setVolume(p.choirVolume);
      final rel = pos - p.choirStart;
      if (rel >= 0 && rel < p.choirSeconds) {
        await _choir.seek(Duration(milliseconds: (rel * 1000).round()));
        unawaited(_choir.play());
      } else if (rel < 0) {
        _choirTimer = Timer(Duration(milliseconds: (-rel * 1000).round()), () async {
          await _choir.seek(Duration.zero);
          unawaited(_choir.play());
        });
      }
    }
    if (p.extraPath != null) {
      await _extra.setVolume(p.extraVolume);
      await _extra.seek(Duration(milliseconds: (pos * 1000).round()));
      unawaited(_extra.play());
    }
    await v.play();
    setState(() => _playing = true);
  }

  Future<void> _stopPreview() async {
    _choirTimer?.cancel();
    await _video?.pause();
    await _choir.pause();
    await _extra.pause();
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _seek(double seconds) async {
    final wasPlaying = _playing;
    await _stopPreview();
    await _video!.seekTo(Duration(milliseconds: (seconds * 1000).round()));
    if (wasPlaying) await _startPreview();
  }

  Future<void> _pickExtra() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = res?.files.single.path;
    if (path == null) return;
    await _extra.setFilePath(path);
    _update((p) => p.copyWith(extraPath: path));
  }

  // ---------- Exportar ----------
  Future<void> _export() async {
    await _stopPreview();
    setState(() => _busy = 'Gerando o vídeo final…');
    try {
      await exportToGallery(_p);
      _snack('Vídeo salvo na galeria (álbum "Coral IA").');
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(title: const Text('Erro ao exportar'), content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final p = ref.watch(projectProvider);
    final v = _video;
    final busy = _busy != null || _recording;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar'),
        bottom: _busy == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Column(children: [
                  Text(_busy!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  const LinearProgressIndicator(),
                ]),
              ),
      ),
      body: v == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _preview(v),
                const SizedBox(height: 12),
                _section('1. Cante o coro', [
                  const Text(
                    'Leve o vídeo até o ponto do coro, toque no microfone e cante o trecho uma vez. '
                    'Use fone de ouvido para o som do vídeo não vazar na gravação.',
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _busy != null ? null : _toggleRecord,
                      icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                      label: Text(_recording ? 'Parar gravação' : 'Gravar coro aqui'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _recording ? Colors.red : null,
                        minimumSize: const Size(220, 52),
                      ),
                    ),
                  ),
                  if (p.guidePath != null && !_recording)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('✓ Guia gravada a partir de ${_fmt(p.guideOffset)}', textAlign: TextAlign.center),
                    ),
                ]),
                _section('2. Ambiente e acabamento', [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in environments.entries)
                        ChoiceChip(
                          label: Text(e.value.$1),
                          selected: p.environment == e.key,
                          onSelected: busy ? null : (_) => _update((x) => x.copyWith(environment: e.key)),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Melhorar voz principal'),
                    subtitle: const Text('Compressão e equalização no áudio original'),
                    value: p.enhanceVoice,
                    onChanged: p.videoHasAudio ? (b) => _update((x) => x.copyWith(enhanceVoice: b)) : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Melhorar pele e iluminação'),
                    subtitle: const Text('Desligado = vídeo original intacto'),
                    value: p.enhanceVideo,
                    onChanged: (b) => _update((x) => x.copyWith(enhanceVideo: b)),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: p.guidePath == null || busy ? null : _generate,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(p.choirPath == null ? 'Gerar coral' : 'Gerar de novo (outro ambiente/variação)'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ]),
                _section('3. Timeline', [
                  Timeline(project: p, position: _position),
                  const SizedBox(height: 12),
                  _slider('Áudio original', p.originalVolume, 0, 1.5,
                      enabled: p.videoHasAudio, onChanged: (x) {
                    _update((q) => q.copyWith(originalVolume: x));
                    _video?.setVolume(math.min(1, x));
                  }),
                  if (p.choirPath != null) ...[
                    _slider('Coral — volume', p.choirVolume, 0, 1.5, onChanged: (x) {
                      _update((q) => q.copyWith(choirVolume: x));
                      _choir.setVolume(math.min(1, x));
                    }),
                    _slider('Coral — fade in (s)', p.choirFadeIn, 0, 3,
                        onChanged: (x) => _update((q) => q.copyWith(choirFadeIn: x))),
                    _slider('Coral — fade out (s)', p.choirFadeOut, 0, 5,
                        onChanged: (x) => _update((q) => q.copyWith(choirFadeOut: x))),
                    _slider('Coral — sincronia (s)', p.choirNudge, -1, 1,
                        onChanged: (x) => _update((q) => q.copyWith(choirNudge: x))),
                  ],
                  Row(children: [
                    Expanded(
                      child: Text(p.extraPath == null
                          ? 'Trilha extra: nenhuma'
                          : 'Trilha extra: ${p.extraPath!.split(Platform.pathSeparator).last}'),
                    ),
                    if (p.extraPath == null)
                      TextButton.icon(
                          onPressed: busy ? null : _pickExtra, icon: const Icon(Icons.add), label: const Text('Música'))
                    else
                      IconButton(
                        tooltip: 'Remover trilha',
                        onPressed: busy
                            ? null
                            : () async {
                                await _extra.stop();
                                _update((q) => q.copyWith(extraPath: null));
                              },
                        icon: const Icon(Icons.close),
                      ),
                  ]),
                  if (p.extraPath != null)
                    _slider('Trilha extra — volume', p.extraVolume, 0, 1.5, onChanged: (x) {
                      _update((q) => q.copyWith(extraVolume: x));
                      _extra.setVolume(math.min(1, x));
                    }),
                ]),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy ? null : _export,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Exportar para a galeria'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                ),
              ],
            ),
    );
  }

  Widget _preview(VideoPlayerController v) {
    final dur = v.value.duration.inMilliseconds / 1000;
    return Column(children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
        child: AspectRatio(
          aspectRatio: v.value.aspectRatio,
          child: Stack(alignment: Alignment.center, children: [
            VideoPlayer(v),
            if (!_playing && !_recording)
              IconButton.filled(
                iconSize: 40,
                onPressed: _busy == null ? _togglePreview : null,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            if (_playing)
              Positioned.fill(child: GestureDetector(onTap: _togglePreview, behavior: HitTestBehavior.opaque)),
            if (_recording)
              const Positioned(
                top: 8,
                right: 8,
                child: Chip(avatar: Icon(Icons.fiber_manual_record, color: Colors.red), label: Text('Gravando')),
              ),
          ]),
        ),
      ),
      Row(children: [
        Text(_fmt(_position)),
        Expanded(
          child: Slider(
            value: _position.clamp(0, math.max(dur, 0.001)).toDouble(),
            max: math.max(dur, 0.001),
            onChanged: _recording ? null : (x) => _video!.seekTo(Duration(milliseconds: (x * 1000).round())),
            onChangeEnd: _recording ? null : _seek,
          ),
        ),
        Text(_fmt(dur)),
      ]),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _slider(String label, double value, double min, double max,
          {required ValueChanged<double> onChanged, bool enabled = true}) =>
      Row(children: [
        SizedBox(width: 150, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: enabled ? onChanged : null),
        ),
        SizedBox(width: 44, child: Text(value.toStringAsFixed(1), textAlign: TextAlign.end)),
      ]);
}

String _fmt(double s) {
  final m = s ~/ 60;
  final sec = (s % 60).floor();
  return '$m:${sec.toString().padLeft(2, '0')}';
}
