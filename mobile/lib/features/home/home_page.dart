import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../editor/editor_page.dart';
import '../project/project.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref, ImageSource source) async {
    final file = await ImagePicker().pickVideo(source: source);
    if (file == null || !context.mounted) return;
    ref.read(projectProvider.notifier).newVideo(file.path);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditorPage()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.groups_rounded, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Coral IA', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Grave ou escolha um vídeo, cante o trecho do coro uma vez e o app transforma sua voz em um coral de 8 vozes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _pick(context, ref, ImageSource.camera),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Gravar vídeo'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _pick(context, ref, ImageSource.gallery),
                icon: const Icon(Icons.video_library_rounded),
                label: const Text('Escolher da galeria'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
