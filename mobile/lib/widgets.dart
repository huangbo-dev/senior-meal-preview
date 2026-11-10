import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// Plain-language information or error box. Errors are live regions so they are
/// announced once when they appear.
class NoticeCard extends StatelessWidget {
  const NoticeCard(this.text, {super.key, this.error = false, this.title});
  final String text;
  final bool error;

  /// Optional short bold lead-in, e.g. "Illustration only".
  final String? title;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.errorText : AppColors.textSecondary;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(color: color);
    return Semantics(
      liveRegion: error,
      container: true,
      child: Container(
        padding: error
            ? const EdgeInsets.all(14)
            : const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: error ? AppColors.errorSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.notice),
          border: error ? Border.all(color: AppColors.errorIcon) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  error ? Icons.error_outline : Icons.info_outline,
                  color: error ? AppColors.errorIcon : AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: title == null
                  ? Text(text, style: style)
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$title. ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: text),
                        ],
                      ),
                      style: style,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress remains available to assistive technology without repeating the title.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.labels});
  final int step;
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step ${step + 1} of ${labels.length}: ${labels[step]}',
    child: const SizedBox.shrink(),
  );
}

/// Cupertino press behavior with a single, consistent primary-action treatment.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    onPressed: onPressed,
    color: AppColors.accent,
    disabledColor: const Color(0xFFE0E4DC),
    borderRadius: BorderRadius.circular(AppRadius.button),
    minimumSize: const Size(double.infinity, 56),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          const CupertinoActivityIndicator(),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.style(
              18,
              weight: FontWeight.w500,
              color: onPressed == null ? AppColors.textSecondary : Colors.white,
            ),
          ),
        ),
      ],
    ),
  );
}

class NativeNavigationButton extends StatelessWidget {
  const NativeNavigationButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.back = false,
    this.onPhoto = false,
    this.visibleLabel,
  });
  final String? visibleLabel;
  final String label;
  final VoidCallback onPressed;
  final bool back;
  final bool onPhoto;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: CupertinoButton(
        onPressed: onPressed,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: back ? 12 : 18, vertical: 12),
        color: onPhoto ? Colors.white.withValues(alpha: .95) : null,
        borderRadius: BorderRadius.circular(28),
        child: back
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 24,
                    child: CustomPaint(painter: _ChevronPainter()),
                  ),
                  if (!onPhoto) ...[
                    const SizedBox(width: 5),
                    Text(visibleLabel ?? label, style: AppTypography.style(17)),
                  ],
                ],
              )
            : Text(
                label == 'Start over' ? 'Reset' : label,
                style: AppTypography.style(17, color: AppColors.textSecondary),
              ),
      ),
    ),
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({this.forward = false, this.color = AppColors.ink});
  final bool forward;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (forward) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(15, 4)
        ..lineTo(7, 12)
        ..lineTo(15, 20),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) =>
      oldDelegate.forward != forward || oldDelegate.color != color;
}

class AppChevron extends StatelessWidget {
  const AppChevron({super.key, this.color = AppColors.textSecondary});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 24,
    child: CustomPaint(painter: _ChevronPainter(forward: true, color: color)),
  );
}

/// A semantic heading that can receive keyboard focus programmatically (when a new
/// step opens) without becoming an extra Tab stop.
class StepHeading extends StatelessWidget {
  const StepHeading(this.text, {super.key, this.focusNode, this.style});
  final String text;
  final FocusNode? focusNode;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focusNode,
    skipTraversal: true,
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: style ?? Theme.of(context).textTheme.displaySmall,
      ),
    ),
  );
}

/// Section heading inside a step, exposed to assistive technology as a header.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: style ?? Theme.of(context).textTheme.headlineSmall,
    ),
  );
}

/// Catalog artwork is reference material, never the result of a meal edit.
/// The schematic fallback remains explicit and does not fake a model response.
class MealArtwork extends StatelessWidget {
  const MealArtwork({super.key, required this.dish});
  final Dish dish;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/meals/${dish.id}.jpg',
    fit: BoxFit.cover,
    filterQuality: FilterQuality.high,
    width: double.infinity,
    semanticLabel:
        'Reference photo of ${dish.id == 'tofu_rice' ? 'tofu and vegetables' : dish.name}. Not a meal-preview result.',
    errorBuilder: (context, error, stackTrace) => ColoredBox(
      color: AppColors.surfaceSubtle,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Photo unavailable',
            textAlign: TextAlign.center,
            style: AppTypography.style(16, color: AppColors.textSecondary),
          ),
        ),
      ),
    ),
  );
}

/// Compact photo collection, with a dark scrim that guarantees title contrast.
/// All three demo meals fit on an ordinary phone; large text uses natural height.
class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.dish,
    required this.selected,
    required this.onSelect,
  });
  final Dish dish;
  final bool selected;
  final VoidCallback onSelect;

  String get subtitle => switch (dish.id) {
    'chicken_rice' => 'Chicken, rice & cucumber',
    'fish_soup' => 'Fish, greens & broth',
    'tofu_rice' => 'Tofu & vegetables pictured',
    _ => 'Reference photo',
  };

  @override
  Widget build(BuildContext context) {
    final large = textScaleOf(context) > 1.3;
    final caption = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dish.name,
                  style: AppTypography.style(
                    20,
                    weight: FontWeight.w600,
                    color: large ? AppColors.ink : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.style(
                    16,
                    color: large ? AppColors.textSecondary : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppChevron(color: large ? AppColors.ink : Colors.white),
        ],
      ),
    );
    return Semantics(
      key: Key('meal-semantics-${dish.id}'),
      button: true,
      onTap: onSelect,
      label: '${dish.name}. $subtitle. Reference photo. Open demo meal.',
      child: ExcludeSemantics(
        child: CupertinoButton(
          key: Key('dish-${dish.id}'),
          padding: EdgeInsets.zero,
          onPressed: onSelect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.mealCard),
            child: large
                ? Column(
                    key: Key('meal-stacked-${dish.id}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 2.4,
                        child: MealArtwork(dish: dish),
                      ),
                      ColoredBox(color: AppColors.surface, child: caption),
                    ],
                  )
                : SizedBox(
                    key: Key('meal-compact-${dish.id}'),
                    height: 156,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MealArtwork(dish: dish),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00000000),
                                Color(0x1A000000),
                                Color(0xB3000000),
                                Color(0xE6000000),
                              ],
                              stops: [0, .38, .6, 1],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: caption,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Stable selected-meal context; image scale never competes with editing controls.
class MealContext extends StatelessWidget {
  const MealContext({super.key, required this.dish});
  final Dish dish;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 76, height: 76, child: MealArtwork(dish: dish)),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dish.name,
              style: AppTypography.style(22, weight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              'Reference photo',
              style: AppTypography.style(16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    ],
  );
}

/// One requested serving change, as a checkbox row.
class ChangeOption extends StatelessWidget {
  const ChangeOption({
    super.key,
    required this.change,
    required this.selected,
    required this.onChanged,
    this.unavailableReason,
  });
  final MealChange change;
  final bool selected;
  bool get value => selected;
  final ValueChanged<bool>? onChanged;
  final String? unavailableReason;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    enabled: onChanged != null,
    onTap: onChanged == null ? null : () => onChanged!(!selected),
    label: '${change.label}. ${change.description}',
    hint: selected
        ? 'Remove this change.'
        : (unavailableReason ?? 'Select this change.'),
    child: ExcludeSemantics(
      child: ColoredBox(
        key: Key('choice-surface-${change.id}'),
        color: selected ? AppColors.cardSelected : AppColors.surface,
        child: CupertinoButton(
          onPressed: onChanged == null ? null : () => onChanged!(!selected),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          minimumSize: const Size(double.infinity, 76),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent
                        : AppColors.strongOutline,
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 22,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      change.label,
                      style: AppTypography.style(
                        18,
                        weight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: onChanged == null
                            ? AppColors.textSecondary
                            : AppColors.ink,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Selected · Tap to remove',
                        key: Key('selected-feedback-${change.id}'),
                        style: AppTypography.style(16, color: AppColors.accent),
                      ),
                    ] else if (unavailableReason != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        unavailableReason!,
                        key: Key('unavailable-${change.id}'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PreferenceOption {
  const PreferenceOption({
    required this.label,
    required this.key,
    required this.selected,
    required this.onSelect,
  });
  final String label;
  final String key;
  final bool selected;
  final VoidCallback onSelect;
}

/// An optional single-choice preference (e.g. texture) with a contextual helper.
class PreferenceGroup extends StatelessWidget {
  const PreferenceGroup({
    super.key,
    required this.title,
    required this.helper,
    required this.options,
    required this.enabled,
  });
  final String title;
  final String helper;
  final List<PreferenceOption> options;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AppTypography.style(18, weight: FontWeight.w600)),
      const SizedBox(height: 10),
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: textScaleOf(context) <= 1.3
              ? Row(
                  children: [
                    for (final option in options)
                      Expanded(
                        child: PreferenceChoice(
                          key: Key(option.key),
                          option: option,
                          enabled: enabled,
                        ),
                      ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final option in options)
                      PreferenceChoice(
                        key: Key(option.key),
                        option: option,
                        enabled: enabled,
                      ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 8),
      Text(helper, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class PreferenceChoice extends StatelessWidget {
  const PreferenceChoice({
    super.key,
    required this.option,
    required this.enabled,
  });
  final PreferenceOption option;
  final bool enabled;
  bool get selected => option.selected;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    label: option.label,
    child: CupertinoButton(
      onPressed: enabled ? option.onSelect : null,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: selected ? AppColors.accent : null,
      borderRadius: BorderRadius.circular(10),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 19, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  18,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The exact requested changes and preferences, with no claim they were applied.
/// Neutral bullets: nothing here has been verified, only requested.
class RequestSummary extends StatelessWidget {
  const RequestSummary({
    super.key,
    required this.targets,
    required this.preferences,
  });
  final List<EditTarget> targets;
  final MealPreferences preferences;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('request-summary'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.changeCard),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Requested changes'),
        const SizedBox(height: 10),
        for (final target in targets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _bulleted(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        if (preferences.texture != 'any')
          _bulleted(context, Text(preferences.textureLabel)),
        if (preferences.flavour != 'any') ...[
          const SizedBox(height: 3),
          _bulleted(context, Text(preferences.flavourLabel)),
        ],
      ],
    ),
  );

  Widget _bulleted(BuildContext context, Widget child) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.only(top: 8, right: 10),
          child: Icon(Icons.circle, size: 8, color: AppColors.ink),
        ),
      ),
      Expanded(child: child),
    ],
  );
}

/// Displays an optional GPU worker preview returned over Tailscale, with full
/// model/prompt/attempt provenance and mandatory non-clinical disclosure.
class GpuPreviewCard extends StatelessWidget {
  const GpuPreviewCard({super.key, required this.artifact});
  final GpuArtifact artifact;

  @override
  Widget build(BuildContext context) {
    final encoded = artifact.imageDataUrl.substring(
      'data:image/png;base64,'.length,
    );
    final bytes = base64Decode(encoded);
    return Container(
      key: const Key('gpu-preview-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.plateCardSurface,
        borderRadius: BorderRadius.circular(AppRadius.plateCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Generated preview',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.notice),
            child: Image.memory(
              bytes,
              width: double.infinity,
              fit: BoxFit.contain,
              semanticLabel: artifact.generatedLabel,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            artifact.generatedLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Model: ${artifact.model} · Prompt: ${artifact.promptId} · '
            'Attempts: ${artifact.attempts} · '
            'Selector diagnostic: ${artifact.checkerPassed ? "passed" : "unverified"}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
