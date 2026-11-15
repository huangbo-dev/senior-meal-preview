import 'package:flutter/material.dart';

import 'theme.dart';

/// Offline examples. All images are prepared before the presentation.
class ShowcasePage extends StatefulWidget {
  const ShowcasePage({super.key, required this.openMealApp});
  final VoidCallback openMealApp;

  @override
  State<ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<ShowcasePage> {
  bool _retry = false;
  int _detail = 1;

  Widget _photo(String name, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: Image.asset(
            'assets/meals/sample_$name.jpg',
            semanticLabel: label,
            fit: BoxFit.contain,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: Theme.of(context).textTheme.titleMedium),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final original = _photo(_retry ? 'tofu_0' : 'original', 'Original meal');
    final detail = _photo(
      _retry ? 'tofu_${_detail + 1}' : (_detail == 0 ? 'region' : 'edited'),
      _retry
          ? (_detail == 0
                ? 'First attempt · selected, failed'
                : 'Second attempt · failed')
          : (_detail == 0 ? 'Hand-marked rice' : 'Recoloured rice'),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('SG Food Edit'),
        actions: [
          TextButton(
            onPressed: widget.openMealApp,
            child: const Text('Try meal choices'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Meal edit walkthrough',
                      style: AppTypography.editorial,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Explore two saved examples from Singapore meals. Both work offline.',
                      style: theme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final item in [false, true])
                          ChoiceChip(
                            label: Text(
                              item
                                  ? 'Tofu rice · retry'
                                  : 'Chicken rice · colour',
                            ),
                            selected: _retry == item,
                            onSelected: (_) => setState(() {
                              _retry = item;
                              _detail = item ? 0 : 1;
                            }),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      _retry
                          ? 'What did the retry change?'
                          : 'How would brown rice look?',
                      style: theme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _retry
                          ? 'BrushNet edited a small rice patch twice. Qwen rejected both attempts. The selected patch looks like a separate piece of food.'
                          : 'The app shifts the colour of the marked rice while retaining the photographed grain shapes. Switch views to inspect its boundary.',
                      style: theme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(_retry ? 'Attempt 1' : 'Rice region'),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(_retry ? 'Attempt 2' : 'Colour edit'),
                          ),
                        ],
                        selected: {_detail},
                        onSelectionChanged: (v) =>
                            setState(() => _detail = v.single),
                      ),
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, box) {
                        if (box.maxWidth < 580) {
                          return Column(
                            children: [
                              detail,
                              const SizedBox(height: 12),
                              original,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: original),
                            const SizedBox(width: 16),
                            Expanded(child: detail),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _retry
                          ? 'Spark 02 fixture run · BrushNet + Qwen · Both candidates failed the requested edit. The tofu meal also contains fish cake.'
                          : 'Local replay · The app’s CIELAB colour-transfer function ran once with a hand-drawn mask. Automatic segmentation and Qwen were outside this run.',
                      style: theme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _retry
                          ? 'Photo by Walter Lim · CC BY 2.0 · Cropped and edited for this comparison. Source: Wikimedia Commons, “Teochew rice with vegetables, fish cake and tofu” (8351561669).'
                          : 'Photo by Misaochan · CC BY 4.0 · Cropped, marked and recoloured. Source: Wikimedia Commons, “Hainanese chicken rice.jpg”.',
                      style: theme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
