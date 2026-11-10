import 'dart:convert';

import 'package:flutter/material.dart';

import 'models.dart';
import 'plate.dart';
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
    final color = error ? AppColors.errorText : AppColors.ink;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(color: color);
    return Semantics(
      liveRegion: error,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: error ? AppColors.errorSurface : AppColors.noticeSurface,
          borderRadius: BorderRadius.circular(AppRadius.notice),
          border: Border.all(
            color: error ? AppColors.errorIcon : AppColors.divider,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  error ? Icons.error_outline : Icons.info_outline,
                  color: error ? AppColors.errorIcon : AppColors.ink,
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

/// "Step 2 of 3 · Make it yours" plus a three-segment bar. Read as one phrase.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.labels});
  final int step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final text = 'Step ${step + 1} of ${labels.length} · ${labels[step]}';
    return Semantics(
      label: 'Step ${step + 1} of ${labels.length}: ${labels[step]}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              key: const Key('progress-label'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                labels.length,
                (i) => Expanded(
                  child: Container(
                    height: 6,
                    margin: EdgeInsets.only(
                      right: i == labels.length - 1 ? 0 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: i <= step
                          ? AppColors.ink
                          : AppColors.progressInactive,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// Selectable meal. Narrow widths use a compact horizontal card; large text stacks the
/// illustration above the text; wide layouts keep a larger side illustration.
class MealCard extends StatefulWidget {
  const MealCard({
    super.key,
    required this.dish,
    required this.selected,
    required this.onSelect,
  });
  final Dish dish;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<MealCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final dish = widget.dish;
    final selected = widget.selected;
    final textScale = textScaleOf(context);
    return Semantics(
      key: Key('meal-semantics-${dish.id}'),
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${dish.name}. ${dish.description}',
      // Visible focus ring outside the card edge, independent of selection.
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused ? AppColors.ink : Colors.transparent,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(AppRadius.mealCard + 4),
        ),
        child: Material(
          color: selected ? AppColors.cardSelected : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.mealCard),
            side: BorderSide(
              color: selected ? AppColors.ink : AppColors.strongOutline,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('dish-${dish.id}'),
            onTap: widget.onSelect,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final info = _info(context, selected);
                    if (constraints.maxWidth >=
                        AppLayout.mealRowMinInnerWidth) {
                      return Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: PlateIllustration(
                              dish: dish,
                              label: 'Demo meal',
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: info),
                        ],
                      );
                    }
                    if (textScale <= AppLayout.compactMealMaxTextScale) {
                      return Row(
                        key: Key('meal-compact-${dish.id}'),
                        children: [
                          SizedBox.square(
                            dimension: AppLayout.compactMealIllustration,
                            child: PlateIllustration(
                              dish: dish,
                              label: 'Demo meal',
                              aspectRatio: 1,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: info),
                        ],
                      );
                    }
                    return Column(
                      key: Key('meal-stacked-${dish.id}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            height: 92,
                            child: PlateIllustration(
                              dish: dish,
                              label: 'Demo meal',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        info,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(BuildContext context, bool selected) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              widget.dish.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? AppColors.ink : AppColors.strongOutline,
            size: 26,
          ),
        ],
      ),
      const SizedBox(height: 3),
      Text(widget.dish.description),
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

  /// Null disables the row.
  final ValueChanged<bool>? onChanged;

  /// Visible explanation shown when the row is disabled because of the limit.
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.cardSelected : AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.changeCard),
      side: BorderSide(
        color: selected ? AppColors.ink : AppColors.strongOutline,
        width: selected ? 2 : 1,
      ),
    ),
    child: CheckboxListTile(
      key: Key('change-${change.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      controlAffinity: ListTileControlAffinity.leading,
      value: selected,
      onChanged: onChanged == null
          ? null
          : (checked) => onChanged!(checked == true),
      title: Text(change.label, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(change.description),
            if (unavailableReason != null) ...[
              const SizedBox(height: 4),
              Text(
                unavailableReason!,
                key: Key('unavailable-${change.id}'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
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
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: '$title, optional',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final option in options)
              Semantics(
                inMutuallyExclusiveGroup: true,
                child: ChoiceChip(
                  key: Key(option.key),
                  label: Text(option.label),
                  selected: option.selected,
                  onSelected: enabled ? (_) => option.onSelect() : null,
                  selectedColor: AppColors.chipSelected,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(helper),
      ],
    ),
  );
}

/// The exact requested changes and preferences, shown before the illustrations.
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
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.changeCard),
      border: Border.all(color: AppColors.strongOutline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('What you requested'),
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
                  Text(target.description),
                ],
              ),
            ),
          ),
        _bulleted(context, Text(preferences.textureLabel)),
        const SizedBox(height: 3),
        _bulleted(context, Text(preferences.flavourLabel)),
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

/// One labelled illustration in the original/requested comparison.
class PlateCard extends StatelessWidget {
  const PlateCard({
    super.key,
    required this.title,
    required this.dish,
    this.changeIds = const [],
  });
  final String title;
  final Dish dish;
  final List<String> changeIds;

  @override
  Widget build(BuildContext context) {
    final isRequested = changeIds.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRequested
            ? AppColors.cardSelected
            : AppColors.plateCardSurface,
        borderRadius: BorderRadius.circular(AppRadius.plateCard),
        border: Border.all(
          color: isRequested ? AppColors.ink : AppColors.strongOutline,
          width: isRequested ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.notice),
              border: Border.all(color: AppColors.divider),
            ),
            child: PlateIllustration(
              dish: dish,
              changeIds: changeIds,
              label: title,
            ),
          ),
          const SizedBox(height: 10),
          Text(dish.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          const Text('Simulated plate illustration'),
        ],
      ),
    );
  }
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
        border: Border.all(color: AppColors.strongOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tailscale GPU model preview',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.notice),
            child: Image.memory(
              bytes,
              height: 170,
              width: double.infinity,
              fit: BoxFit.cover,
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
