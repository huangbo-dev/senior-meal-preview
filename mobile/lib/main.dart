import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'plate.dart';
import 'theme.dart';
import 'widgets.dart';

void main() => runApp(const MealPreviewApp());

class MealPreviewApp extends StatelessWidget {
  const MealPreviewApp({super.key, this.api});
  final MealApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'A little change',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: MealFlow(api: api),
  );
}

class MealFlow extends StatefulWidget {
  const MealFlow({super.key, this.api});
  final MealApi? api;
  @override
  State<MealFlow> createState() => _MealFlowState();
}

class _MealFlowState extends State<MealFlow> {
  static const _steps = ['Choose a meal', 'Make it yours', 'See the idea'];

  late final MealApi _api;
  late final bool _ownsApi;
  final ScrollController _scroll = ScrollController();
  final FocusNode _headingFocus = FocusNode(debugLabel: 'step-heading');
  Catalog? _catalog;
  Dish? _dish;
  final Set<String> _changes = {};
  MealPreferences _preferences = const MealPreferences();
  String _renderMode = 'illustrative_only';
  MealPreview? _preview;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  int _step = 0;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? HttpMealApi();
    _loadCatalog();
  }

  @override
  void dispose() {
    _requestVersion++;
    _headingFocus.dispose();
    _scroll.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _api.fetchCatalog();
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) => error is ApiException
      ? error.message
      : 'Something went wrong with the local service. Please try again.';

  void _goTo(int step) {
    ++_requestVersion;
    setState(() {
      _step = step;
      _submitting = false;
      _error = null;
      _preview = step < 2 ? null : _preview;
    });
    _transitionToStep();
  }

  void _transitionToStep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _headingFocus.requestFocus();
    });
  }

  void _reset() {
    ++_requestVersion;
    setState(() {
      _step = 0;
      _dish = null;
      _changes.clear();
      _preferences = const MealPreferences();
      _renderMode = 'illustrative_only';
      _preview = null;
      _submitting = false;
      _error = null;
    });
    _transitionToStep();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final dish = _dish;
    final rules = _catalog?.selection ?? const SelectionRules();
    if (dish == null ||
        _changes.length < rules.minChanges ||
        _changes.length > rules.maxChanges) {
      setState(() {
        _error = 'Choose one or two changes before making a preview.';
      });
      return;
    }
    final version = ++_requestVersion;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _api.preview(
        dishId: dish.id,
        changeIds: _changes.toList(),
        preferences: _preferences,
        renderMode: _renderMode,
      );
      if (!mounted || version != _requestVersion) return;
      if (result.dish.id != dish.id ||
          result.targets
              .map((t) => t.id)
              .toSet()
              .difference(_changes)
              .isNotEmpty ||
          result.targets.map((t) => t.id).toSet().length != _changes.length ||
          result.targets.length != _changes.length ||
          result.preferences.texture != _preferences.texture ||
          result.preferences.flavour != _preferences.flavour) {
        throw const ApiException(
          'The preview did not match your choices. Please try again.',
        );
      }
      setState(() {
        _preview = result;
        _submitting = false;
        _step = 2;
      });
      _transitionToStep();
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _error = _friendlyError(error);
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _step > 0) _goTo(_step - 1);
    },
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxOuterWidth,
            ),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: AppLayout.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  if (_loading)
                    _loadingView()
                  else if (_catalog == null)
                    _catalogFailure()
                  else ...[
                    StepProgress(step: _step, labels: _steps),
                    const SizedBox(height: 16),
                    if (_step == 0)
                      ..._chooseMeal()
                    else if (_step == 1)
                      ..._chooseChanges()
                    else
                      ..._showPreview(),
                  ],
                  const SizedBox(height: 24),
                  const Divider(color: AppColors.divider),
                  const SizedBox(height: 10),
                  Text(
                    'A local prototype · Not for coursework submission',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header() => textScaleOf(context) <= AppLayout.compactMealMaxTextScale
      ? Row(
          children: [
            _brandIcon(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'A little change',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (_dish != null) _resetButton(),
          ],
        )
      : Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _brandIcon(),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'A little change',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            if (_dish != null) _resetButton(),
          ],
        );

  Widget _brandIcon() => const ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(9),
        child: Icon(Icons.restaurant_rounded, color: Colors.white, size: 20),
      ),
    ),
  );

  Widget _resetButton() => TextButton.icon(
    key: const Key('reset'),
    onPressed: _reset,
    icon: const Icon(Icons.restart_alt, size: 20),
    label: const Text('Start over'),
  );

  Widget _loadingView() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 80),
    child: Column(
      children: [
        CircularProgressIndicator(semanticsLabel: 'Loading meals'),
        SizedBox(height: 24),
        Text('Getting the meal choices…'),
      ],
    ),
  );

  Widget _catalogFailure() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StepHeading('Let’s reconnect', focusNode: _headingFocus),
      const SizedBox(height: 16),
      NoticeCard(_error ?? 'Cannot load meals.', error: true),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('retry-catalog'),
        onPressed: _loadCatalog,
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
      const SizedBox(height: 12),
      const Text(
        'Meal choices come from the local Rust service. There is no offline fallback.',
      ),
    ],
  );

  List<Widget> _chooseMeal() => [
    StepHeading('Choose a familiar meal', focusNode: _headingFocus),
    const SizedBox(height: 6),
    Text(
      'Pick a demo meal, then explore one or two small serving changes.',
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    const SizedBox(height: 12),
    const NoticeCard(
      'These drawings are not AI results or nutrition advice.',
      key: Key('demo-callout'),
      title: 'Demo only',
    ),
    const SizedBox(height: 14),
    for (final dish in _catalog!.dishes)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: MealCard(
          dish: dish,
          selected: _dish?.id == dish.id,
          onSelect: () => setState(() {
            if (_dish?.id != dish.id) {
              _changes.clear();
              _preferences = const MealPreferences();
              _renderMode = 'illustrative_only';
            }
            _dish = dish;
            _error = null;
          }),
        ),
      ),
    const SizedBox(height: 6),
    FilledButton.icon(
      key: const Key('continue'),
      onPressed: _dish == null ? null : () => _goTo(1),
      icon: const Icon(Icons.arrow_forward_rounded),
      label: const Text('Choose my changes'),
    ),
    const SizedBox(height: 8),
    Semantics(
      liveRegion: true,
      child: Text(
        _dish == null
            ? 'Choose one meal to continue.'
            : '${_dish!.name} selected.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ),
  ];

  List<Widget> _chooseChanges() {
    final changes = _catalog!.changesFor(_dish!.id);
    final rules = _catalog!.selection;
    final maxForDish = rules.maxFor(changes.length);
    final singleChoiceDish = maxForDish == 1;
    final atLimit = _changes.length >= maxForDish;
    final statusText = _changes.isEmpty
        ? '0 of $maxForDish selected. '
              '${singleChoiceDish ? 'Choose this change to continue.' : 'Choose at least one change to continue.'}'
        : atLimit && !singleChoiceDish
        ? '${_changes.length} of $maxForDish selected. Remove one to choose another.'
        : '${_changes.length} of $maxForDish selected.';
    return [
      StepHeading('Make it yours', focusNode: _headingFocus),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(AppRadius.notice),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: 40,
                child: PlateIllustration(
                  dish: _dish!,
                  label: _dish!.name,
                  aspectRatio: 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'For your ${_dish!.name.toLowerCase()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      SectionHeading(
        singleChoiceDish
            ? 'Choose this change to see an idea'
            : 'Choose ${rules.minChanges} or $maxForDish changes',
      ),
      const SizedBox(height: 4),
      Semantics(
        liveRegion: true,
        child: Text(
          statusText,
          key: const Key('change-selection-status'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      const SizedBox(height: 12),
      for (final change in changes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ChangeOption(
            change: change,
            selected: _changes.contains(change.id),
            unavailableReason: !_changes.contains(change.id) && atLimit
                ? 'Remove a selected change to choose this one.'
                : null,
            onChanged:
                !_submitting && (_changes.contains(change.id) || !atLimit)
                ? (checked) => setState(() {
                    checked
                        ? _changes.add(change.id)
                        : _changes.remove(change.id);
                    _error = null;
                  })
                : null,
          ),
        ),
      const SizedBox(height: 18),
      const SectionHeading('Any preferences?'),
      const SizedBox(height: 4),
      const Text(
        'Optional. These are requests only, not checks that a meal is safe or suitable.',
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.changeCard),
          border: Border.all(color: AppColors.strongOutline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PreferenceGroup(
              title: 'Texture',
              helper:
                  'A texture request only. This does not check swallowing safety.',
              enabled: !_submitting,
              options: [
                PreferenceOption(
                  label: 'No preference',
                  key: 'texture-any',
                  selected: _preferences.texture == 'any',
                  onSelect: () => setState(
                    () => _preferences = MealPreferences(
                      flavour: _preferences.flavour,
                    ),
                  ),
                ),
                PreferenceOption(
                  label: 'Soft',
                  key: 'texture-soft',
                  selected: _preferences.texture == 'soft',
                  onSelect: () => setState(
                    () => _preferences = MealPreferences(
                      texture: 'soft',
                      flavour: _preferences.flavour,
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: AppColors.divider, height: 1),
            ),
            PreferenceGroup(
              title: 'Flavour',
              helper: 'A seasoning request only. Ingredients are not checked.',
              enabled: !_submitting,
              options: [
                PreferenceOption(
                  label: 'No preference',
                  key: 'flavour-any',
                  selected: _preferences.flavour == 'any',
                  onSelect: () => setState(
                    () => _preferences = MealPreferences(
                      texture: _preferences.texture,
                    ),
                  ),
                ),
                PreferenceOption(
                  label: 'Mild',
                  key: 'flavour-mild',
                  selected: _preferences.flavour == 'mild',
                  onSelect: () => setState(
                    () => _preferences = MealPreferences(
                      texture: _preferences.texture,
                      flavour: 'mild',
                    ),
                  ),
                ),
              ],
            ),
            if (_catalog!.capabilities.gpuPreview) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: AppColors.divider, height: 1),
              ),
              PreferenceGroup(
                title: 'Preview engine',
                helper:
                    'GPU mode routes only meal IDs over Tailscale to the model worker; errors never fall back to fake photos.',
                enabled: !_submitting,
                options: [
                  PreferenceOption(
                    label: 'Symbolic drawing',
                    key: 'render-illustrative',
                    selected: _renderMode == 'illustrative_only',
                    onSelect: () =>
                        setState(() => _renderMode = 'illustrative_only'),
                  ),
                  PreferenceOption(
                    label: 'Tailscale GPU model',
                    key: 'render-gpu',
                    selected: _renderMode == 'gpu_assisted',
                    onSelect: () =>
                        setState(() => _renderMode = 'gpu_assisted'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (_error != null) ...[
        NoticeCard(_error!, key: const Key('submit-error'), error: true),
        const SizedBox(height: 14),
      ],
      FilledButton.icon(
        key: const Key('submit'),
        onPressed: _submitting || _changes.length < rules.minChanges
            ? null
            : _submit,
        icon: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: 'Preparing your meal idea',
                ),
              )
            : const Icon(Icons.visibility_outlined),
        label: Text(
          _submitting
              ? 'Preparing your meal idea…'
              : _error != null
              ? 'Try preview again'
              : 'See my meal idea',
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('back'),
        onPressed: () => _goTo(0),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back to meals'),
      ),
    ];
  }

  List<Widget> _showPreview() {
    final preview = _preview!;
    final requestedIds = preview.targets.map((t) => t.id).toList();
    return [
      StepHeading('Your requested meal idea', focusNode: _headingFocus),
      const SizedBox(height: 6),
      Text(preview.summary, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 14),
      const NoticeCard(
        'These drawings do not show a real meal or an AI result. Nutrition, texture, allergens and clinical safety have not been checked.',
        key: Key('preview-disclosure'),
        title: 'Illustration only',
      ),
      const SizedBox(height: 14),
      RequestSummary(
        targets: preview.targets,
        preferences: preview.preferences,
      ),
      const SizedBox(height: 14),
      if (preview.gpuArtifact != null) ...[
        GpuPreviewCard(artifact: preview.gpuArtifact!),
        const SizedBox(height: 14),
      ],
      LayoutBuilder(
        builder: (context, constraints) {
          final original = PlateCard(
            key: const Key('plate-original'),
            title: 'Original idea',
            dish: preview.dish,
          );
          final requested = PlateCard(
            key: const Key('plate-requested'),
            title: 'Requested idea',
            dish: preview.dish,
            changeIds: requestedIds,
          );
          return constraints.maxWidth >=
                  AppLayout.comparisonColumnsMinInnerWidth
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: original),
                    const SizedBox(width: 16),
                    Expanded(child: requested),
                  ],
                )
              : Column(
                  children: [original, const SizedBox(height: 14), requested],
                );
        },
      ),
      const SizedBox(height: 18),
      for (final notice in preview.notices)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NoticeCard(notice),
        ),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const Key('edit'),
        onPressed: () => _goTo(1),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Change my choices'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('new-meal'),
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt),
        label: const Text('Try another meal'),
      ),
    ];
  }
}
