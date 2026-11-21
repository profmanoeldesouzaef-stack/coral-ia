import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../project/project.dart';

/// Visão das 4 faixas (vídeo, áudio original, coral, trilha extra) com o cursor de reprodução.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.project, required this.position});

  final Project project;
  final double position;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final total = math.max(p.videoSeconds, 0.001);
    final scheme = Theme.of(context).colorScheme;
    final rows = <(String, double, double, Color?)>[
      ('Vídeo', 0, p.videoSeconds, scheme.primary),
      ('Original', 0, p.videoHasAudio ? p.videoSeconds : 0, scheme.secondary),
      ('Coral', p.choirStart, p.choirPath == null ? 0 : p.choirSeconds, scheme.tertiary),
      ('Extra', 0, p.extraPath == null ? 0 : p.videoSeconds, scheme.outline),
    ];
    return LayoutBuilder(builder: (context, c) {
      const labelW = 64.0;
      final w = c.maxWidth - labelW;
      return Stack(children: [
        Column(children: [
          for (final (label, start, len, color) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: labelW, child: Text(label, style: Theme.of(context).textTheme.labelSmall)),
                SizedBox(
                  width: w,
                  height: 26,
                  child: Stack(children: [
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    if (len > 0)
                      Positioned(
                        left: (start.clamp(0, total) / total) * w,
                        width: math.max(4.0, (math.min(len, total - start.clamp(0, total).toDouble()) / total) * w),
                        top: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color?.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
        ]),
        Positioned(
          left: labelW + (position.clamp(0, total) / total) * w - 1,
          top: 0,
          bottom: 0,
          child: Container(width: 2, color: scheme.error),
        ),
      ]);
    });
  }
}
