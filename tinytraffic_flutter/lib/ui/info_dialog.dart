import 'package:flutter/material.dart';

import '../game/controller.dart';
import 'kit.dart';

Future<void> showInfo(BuildContext context, GameController game) {
  game.audio.play('ui_tap', volume: 0.5);
  return showDialog(
    context: context,
    barrierColor: const Color(0xAA14213D),
    builder: (context) => const _InfoDialog(),
  );
}

class _InfoDialog extends StatelessWidget {
  const _InfoDialog();

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400 * u),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: EdgeInsets.all(16 * u),
            child: Sticker(
              tilt: 0.015,
              padding: EdgeInsets.fromLTRB(20 * u, 14 * u, 14 * u, 18 * u),
              radius: 26 * u,
              border: 4 * u,
              depth: 8 * u,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StrokeText(
                            'TINY TRAFFIC',
                            style: display(28 * u, color: Palette.coin),
                            strokeWidth: 7 * u,
                            shadow: Offset(0, 3 * u),
                            align: TextAlign.left,
                          ),
                        ),
                        RoundButton(
                          icon: Icons.close_rounded,
                          size: 0.8 * u,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    SizedBox(height: 14 * u),
                    Text.rich(
                      TextSpan(
                        style: body(17 * u),
                        children: [
                          const TextSpan(text: 'Built with '),
                          TextSpan(
                            text: 'Flutter',
                            style: body(17 * u, color: Palette.blue),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Serverpod',
                            style: body(17 * u, color: Palette.blue),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
