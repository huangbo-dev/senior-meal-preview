import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

void main() => runApp(const MealPreviewApp());

class MealPreviewApp extends StatelessWidget {
  const MealPreviewApp({super.key, this.api});
  final MealApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meal preview',
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
  static const _steps = ['Choose a meal', 'Choose changes', 'Review request'];

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
      : 'Something went wrong. Please try again.';

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

  bool get _pinAction =>
      textScaleOf(context) <= 1.3 && MediaQuery.sizeOf(context).height >= 640;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _step > 0) _goTo(_step - 1);
    },
    child: Scaffold(
      bottomNavigationBar:
          !_loading && _catalog != null && _pinAction && _step > 0
          ? SafeArea(top: false, child: _actionBar())
          : null,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppLayout.maxOuterWidth,
            ),
            child: Column(
              children: [
                if (_step > 0) _header(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: AppLayout.pagePadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_loading)
                                _loadingView()
                              else if (_catalog == null)
                                _catalogFailure()
                              else ...[
                                if (_step == 0)
                                  ..._chooseMeal()
                                else if (_step == 1)
                                  ..._chooseChanges()
                                else
                                  ..._showPreview(),
                                if (!_pinAction && _step > 0) ...[
                                  const SizedBox(height: 24),
                                  _primaryAction(),
                                ],
                              ],
                              const SizedBox(height: 24),
                              if (_step == 0)
                                TextButton(
                                  onPressed: _showPhotoCredits,
                                  key: const Key('photo-credits'),
                                  child: const Text('About'),
                                ),
                              SizedBox(
                                height: MediaQuery.paddingOf(context).bottom,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header() => CupertinoNavigationBar(
    automaticallyImplyLeading: false,
    backgroundColor: AppColors.background,
    border: const Border(
      bottom: BorderSide(color: AppColors.divider, width: .5),
    ),
    leading: NativeNavigationButton(
      key: Key(_step == 1 ? 'back' : 'nav-back'),
      label: _step == 1 ? 'Back to meals' : 'Back to changes',
      visibleLabel: _step == 1 ? 'Meals' : 'Changes',
      onPressed: () => _goTo(_step - 1),
      back: true,
    ),
    middle: Text(
      _step == 1 ? 'Edit meal' : 'Review',
      style: AppTypography.style(17, weight: FontWeight.w600),
    ),
    trailing: _step == 1
        ? CupertinoButton(
            key: const Key('reset'),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(48, 48),
            onPressed: _confirmClearChoices,
            child: Text(
              'Clear',
              style: AppTypography.style(17, color: AppColors.accent),
            ),
          )
        : null,
  );

  Future<void> _confirmClearChoices() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Clear your choices?'),
        content: Text(
          'Remove the changes and preferences for ${_dish!.name.toLowerCase()}? Your meal stays selected.',
        ),
        actions: [
          CupertinoDialogAction(
            key: const Key('clear-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep choices'),
          ),
          CupertinoDialogAction(
            key: const Key('clear-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear choices'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ++_requestVersion;
    setState(() {
      _changes.clear();
      _preferences = const MealPreferences();
      _preview = null;
      _submitting = false;
      _error = null;
      _step = 1;
    });
    _transitionToStep();
  }

  Widget _actionBar() => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.divider, width: .5)),
    ),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxOuterWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: _primaryAction(),
        ),
      ),
    ),
  );

  Widget _primaryAction() => _step == 1
      ? AppPrimaryButton(
          key: const Key('submit'),
          onPressed:
              _submitting || _changes.length < _catalog!.selection.minChanges
              ? null
              : _submit,
          busy: _submitting,
          label: _submitting
              ? 'Preparing…'
              : _error != null
              ? 'Try again'
              : _renderMode == 'gpu_assisted'
              ? 'Generate preview'
              : _changes.isEmpty
              ? 'Choose a change'
              : 'Review ${_changes.length} ${_changes.length == 1 ? 'change' : 'changes'}',
        )
      : AppPrimaryButton(
          key: const Key('edit'),
          onPressed: () => _goTo(1),
          label: 'Edit choices',
        );

  Future<void> _showPhotoCredits() async {
    final credits = await rootBundle.loadString('assets/meals/ATTRIBUTION.md');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: AppColors.background,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeading('About'),
              const SizedBox(height: 10),
              const Text(
                'Meal photos are reference photos, not your meal. Not nutrition, allergen or medical advice.',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    credits.replaceAll(RegExp(r'^#+ ', multiLine: true), ''),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppPrimaryButton(
                onPressed: () => Navigator.pop(sheetContext),
                label: 'Done',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingView() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 80),
    child: Column(
      children: [
        Semantics(
          label: 'Loading meals',
          child: const CupertinoActivityIndicator(radius: 14),
        ),
        const SizedBox(height: 24),
        const Text('Getting the meal choices…'),
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
      AppPrimaryButton(
        key: const Key('retry-catalog'),
        onPressed: _loadCatalog,
        label: 'Try again',
      ),
      const SizedBox(height: 12),
      const Text('Check your internet connection, then try again.'),
    ],
  );

  List<Widget> _chooseMeal() => [
    const SizedBox(height: 10),
    StepHeading('Meals', focusNode: _headingFocus),
    const SizedBox(height: 8),
    Text(
      'Choose a meal to personalise.',
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    const SizedBox(height: 8),
    Text(
      '${_catalog!.dishes.length} meals · Reference photos',
      key: const Key('demo-callout'),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
    StepProgress(step: _step, labels: _steps),
    const SizedBox(height: 24),
    for (final dish in _catalog!.dishes)
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: MealCard(
          dish: dish,
          selected: _dish?.id == dish.id,
          onSelect: () {
            setState(() {
              if (_dish?.id != dish.id) {
                _changes.clear();
                _preferences = const MealPreferences();
                _renderMode = 'illustrative_only';
              }
              _dish = dish;
              _error = null;
            });
            _goTo(1);
          },
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
        ? (singleChoiceDish ? 'Choose this change' : 'Choose 1 or $maxForDish')
        : singleChoiceDish
        ? '1 selected'
        : 'Choose 1 or $maxForDish · ${_changes.length} selected';
    return [
      StepProgress(step: _step, labels: _steps),
      const SizedBox(height: 8),
      MealContext(dish: _dish!),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Divider(height: 1),
      ),
      StepHeading(
        'Choose your changes',
        focusNode: _headingFocus,
        style: AppTypography.style(25, weight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      const SizedBox(height: 5),
      Semantics(
        liveRegion: true,
        label:
            'Choose at least ${rules.minChanges} and at most $maxForDish changes. $statusText',
        child: Text(
          statusText,
          key: const Key('change-selection-status'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.changeCard),
        child: ColoredBox(
          color: AppColors.surface,
          child: Column(
            children: [
              for (final change in changes) ...[
                ChangeOption(
                  key: Key('change-${change.id}'),
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
                if (change != changes.last)
                  const Divider(height: 1, indent: 18, endIndent: 18),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      const SectionHeading('Preferences'),
      const SizedBox(height: 10),
      CupertinoButton(
        key: const Key('preferences-open'),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        minimumSize: const Size(double.infinity, 64),
        onPressed: _submitting ? null : _showPreferences,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Texture & flavour', style: AppTypography.style(18)),
                  const SizedBox(height: 4),
                  Text(
                    _preferenceSummary,
                    key: const Key('preference-summary'),
                    style: AppTypography.style(
                      16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const AppChevron(),
          ],
        ),
      ),
      if (_renderMode == 'gpu_assisted') ...[
        const SizedBox(height: 16),
        Text(
          'AI preview · Not clinically verified.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
      const SizedBox(height: 20),
      if (_error != null) ...[
        NoticeCard(_error!, key: const Key('submit-error'), error: true),
        const SizedBox(height: 14),
      ],
    ];
  }

  String get _preferenceSummary {
    final values = <String>[
      if (_preferences.texture != 'any') 'Soft texture',
      if (_preferences.flavour != 'any') 'Mild flavour',
    ];
    if (_catalog!.capabilities.gpuPreview) {
      values.add(_renderMode == 'gpu_assisted' ? 'AI preview' : 'Summary only');
    }
    return values.isEmpty ? 'Optional · No preference' : values.join(' · ');
  }

  Future<void> _showPreferences() async {
    var draftPreferences = _preferences;
    var draftMode = _renderMode;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: AppColors.background,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) {
          return FractionallySizedBox(
            heightFactor:
                textScaleOf(context) > 1.3 || _catalog!.capabilities.gpuPreview
                ? .9
                : .78,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    child: textScaleOf(context) > 1.3
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: _cancelPreferences(sheetContext),
                              ),
                              Text(
                                'Preferences',
                                style: AppTypography.style(
                                  24,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Preferences',
                                  style: AppTypography.style(
                                    24,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              _cancelPreferences(sheetContext),
                            ],
                          ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: _preferenceControls(
                        draftPreferences,
                        draftMode,
                        (value) => refresh(() => draftPreferences = value),
                        (value) => refresh(() => draftMode = value),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: AppPrimaryButton(
                      key: const Key('preferences-done'),
                      label: 'Use preferences',
                      onPressed: () {
                        setState(() {
                          _preferences = draftPreferences;
                          _renderMode = draftMode;
                        });
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cancelPreferences(BuildContext sheetContext) => CupertinoButton(
    key: const Key('preferences-cancel'),
    minimumSize: const Size(48, 48),
    onPressed: () => Navigator.pop(sheetContext),
    child: Text(
      'Cancel',
      style: AppTypography.style(17, color: AppColors.accent),
    ),
  );

  Widget _preferenceControls(
    MealPreferences preferences,
    String renderMode,
    ValueChanged<MealPreferences> onPreferences,
    ValueChanged<String> onMode,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.changeCard),
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
              selected: preferences.texture == 'any',
              onSelect: () =>
                  onPreferences(MealPreferences(flavour: preferences.flavour)),
            ),
            PreferenceOption(
              label: 'Soft',
              key: 'texture-soft',
              selected: preferences.texture == 'soft',
              onSelect: () => onPreferences(
                MealPreferences(texture: 'soft', flavour: preferences.flavour),
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
          helper: 'Ingredients are not checked.',
          enabled: !_submitting,
          options: [
            PreferenceOption(
              label: 'No preference',
              key: 'flavour-any',
              selected: preferences.flavour == 'any',
              onSelect: () =>
                  onPreferences(MealPreferences(texture: preferences.texture)),
            ),
            PreferenceOption(
              label: 'Mild',
              key: 'flavour-mild',
              selected: preferences.flavour == 'mild',
              onSelect: () => onPreferences(
                MealPreferences(texture: preferences.texture, flavour: 'mild'),
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
            title: 'Preview mode',
            helper:
                'AI preview makes a picture from a stock meal photo. If it fails, no picture is shown.',
            enabled: !_submitting,
            options: [
              PreferenceOption(
                label: 'Summary only',
                key: 'render-illustrative',
                selected: renderMode == 'illustrative_only',
                onSelect: () => onMode('illustrative_only'),
              ),
              PreferenceOption(
                label: 'AI preview',
                key: 'render-gpu',
                selected: renderMode == 'gpu_assisted',
                onSelect: () => onMode('gpu_assisted'),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  List<Widget> _showPreview() {
    final preview = _preview!;
    return [
      StepProgress(step: _step, labels: _steps),
      const SizedBox(height: 8),
      StepHeading(
        preview.gpuArtifact == null ? 'Your meal request' : 'Your preview',
        focusNode: _headingFocus,
        style: AppTypography.editorial,
      ),
      const SizedBox(height: 12),
      Text(
        preview.gpuArtifact == null
            ? 'Request summary · No picture generated'
            : 'AI-generated preview',
        key: const Key('preview-disclosure'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      if (preview.gpuArtifact != null) ...[
        GpuPreviewCard(artifact: preview.gpuArtifact!),
        const SizedBox(height: 20),
      ] else ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 2.1,
            child: MealArtwork(dish: preview.dish),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Reference photo · Unchanged',
          key: const Key('reference-unchanged'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text(
          preview.dish.name,
          style: AppTypography.style(24, weight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
      ],
      RequestSummary(
        targets: preview.targets,
        preferences: preview.preferences,
      ),
      const SizedBox(height: 18),
      Text(
        preview.notices.join(' '),
        key: const Key('preview-notices'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 10),
      CupertinoButton(
        key: const Key('new-meal'),
        onPressed: () => _goTo(0),
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.button),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        minimumSize: const Size(double.infinity, 56),
        child: Text(
          'Choose another meal',
          style: AppTypography.style(17, color: AppColors.accent),
        ),
      ),
    ];
  }
}
