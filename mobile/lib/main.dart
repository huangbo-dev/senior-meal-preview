import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'plate.dart';

void main() => runApp(const MealPreviewApp());

const _ink = Color(0xFF163D34);
const _cream = Color(0xFFF8F6EF);
const _muted = Color(0xFF52655C);

class MealPreviewApp extends StatelessWidget {
  const MealPreviewApp({super.key, this.api});
  final MealApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'A little change',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: _ink,
        primary: _ink,
        surface: _cream,
        error: const Color(0xFF9C2520),
      ),
      scaffoldBackgroundColor: _cream,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 38,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          color: _ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 27,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
        titleMedium: TextStyle(
          fontSize: 19,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
        bodyLarge: TextStyle(fontSize: 19, height: 1.5, color: _ink),
        bodyMedium: TextStyle(fontSize: 17, height: 1.45, color: _muted),
        labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 58),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          side: const BorderSide(color: _ink),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      chipTheme: const ChipThemeData(
        padding: EdgeInsets.all(12),
        labelStyle: TextStyle(fontSize: 18),
        side: BorderSide(color: Color(0xFF99A99D)),
      ),
    ),
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
  late final MealApi _api;
  late final bool _ownsApi;
  final ScrollController _scroll = ScrollController();
  Catalog? _catalog;
  Dish? _dish;
  final Set<String> _changes = {};
  MealPreferences _preferences = const MealPreferences();
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
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _reset() {
    ++_requestVersion;
    setState(() {
      _step = 0;
      _dish = null;
      _changes.clear();
      _preferences = const MealPreferences();
      _preview = null;
      _submitting = false;
      _error = null;
    });
    _scrollToTop();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final dish = _dish;
    if (dish == null || _changes.isEmpty || _changes.length > 2) {
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
      _scrollToTop();
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
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 24),
                  if (_loading)
                    _loadingView()
                  else if (_catalog == null)
                    _catalogFailure()
                  else ...[
                    _progress(),
                    const SizedBox(height: 30),
                    if (_step == 0)
                      ..._chooseMeal()
                    else if (_step == 1)
                      ..._chooseChanges()
                    else
                      ..._showPreview(),
                  ],
                  const SizedBox(height: 32),
                  const Divider(color: Color(0xFFCCD3C7)),
                  const SizedBox(height: 12),
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

  Widget _header() => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 8,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(color: _ink, shape: BoxShape.circle),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Icon(
                Icons.restaurant_rounded,
                color: Colors.white,
                size: 25,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'A little change',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
      if (_dish != null)
        TextButton.icon(
          key: const Key('reset'),
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Start over'),
        ),
    ],
  );

  Widget _progress() => Semantics(
    label:
        'Step ${_step + 1} of 3: ${['Choose a meal', 'Make it yours', 'See the idea'][_step]}',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_step + 1} OF 3  ·  ${['CHOOSE A MEAL', 'MAKE IT YOURS', 'SEE THE IDEA'][_step]}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: _muted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsets.only(right: i == 2 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: i <= _step ? _ink : const Color(0xFFDEE4D8),
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
      Text('Let’s reconnect', style: Theme.of(context).textTheme.displaySmall),
      const SizedBox(height: 20),
      _notice(_error ?? 'Cannot load meals.', error: true),
      const SizedBox(height: 20),
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
    Text(
      'A familiar meal.\nA new possibility.',
      style: Theme.of(context).textTheme.displaySmall,
    ),
    const SizedBox(height: 14),
    const Text(
      'Pick a demo meal, then explore one or two small serving changes.',
    ),
    const SizedBox(height: 22),
    _notice(
      'Illustrative only. No food photos, nutrition assessment or AI model results.',
    ),
    const SizedBox(height: 24),
    ..._catalog!.dishes.map(
      (dish) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _mealCard(dish),
      ),
    ),
    const SizedBox(height: 10),
    FilledButton.icon(
      key: const Key('continue'),
      onPressed: _dish == null ? null : () => _goTo(1),
      icon: const Icon(Icons.arrow_forward_rounded),
      label: const Text('Choose my changes'),
    ),
    const SizedBox(height: 10),
    Text(
      _dish == null
          ? 'Choose one meal to continue.'
          : '${_dish!.name} selected.',
      textAlign: TextAlign.center,
    ),
  ];

  Widget _mealCard(Dish dish) {
    final selected = _dish?.id == dish.id;
    return Semantics(
      selected: selected,
      button: true,
      label: '${dish.name}. ${dish.description}',
      child: Material(
        color: selected ? const Color(0xFFEAF0E2) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: selected ? _ink : const Color(0xFFD7DDD1),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('dish-${dish.id}'),
          onTap: () => setState(() {
            if (_dish?.id != dish.id) {
              _changes.clear();
              _preferences = const MealPreferences();
            }
            _dish = dish;
            _error = null;
          }),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            dish.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: _ink,
                          size: 28,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(dish.description),
                  ],
                );
                return constraints.maxWidth >= 500
                    ? Row(
                        children: [
                          SizedBox(
                            width: 148,
                            child: PlateIllustration(
                              dish: dish,
                              label: 'Demo meal',
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: info),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 128,
                            child: PlateIllustration(
                              dish: dish,
                              label: 'Demo meal',
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
    );
  }

  List<Widget> _chooseChanges() {
    final changes = _catalog!.changes.where(
      (c) => c.dishIds.contains(_dish!.id),
    );
    return [
      Text('Make it yours.', style: Theme.of(context).textTheme.displaySmall),
      const SizedBox(height: 12),
      Text(
        'For your ${_dish!.name.toLowerCase()}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 22),
      Text(
        'Choose 1 or 2 changes',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Semantics(
        liveRegion: true,
        child: Text(
          '${_changes.length} of 2 selected${_changes.length == 2 ? '. Unselect one to choose another.' : '.'}',
        ),
      ),
      const SizedBox(height: 16),
      ...changes.map((change) {
        final selected = _changes.contains(change.id);
        final enabled = !_submitting && (selected || _changes.length < 2);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: selected ? const Color(0xFFEAF0E2) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: selected ? _ink : const Color(0xFFD7DDD1),
              ),
            ),
            child: CheckboxListTile(
              key: Key('change-${change.id}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              controlAffinity: ListTileControlAffinity.leading,
              value: selected,
              onChanged: enabled
                  ? (checked) => setState(() {
                      checked == true
                          ? _changes.add(change.id)
                          : _changes.remove(change.id);
                      _error = null;
                    })
                  : null,
              title: Text(
                change.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(change.description),
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 24),
      Text(
        'Any preferences?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Optional. These are requests only, not checks that a meal is safe or suitable.',
      ),
      const SizedBox(height: 18),
      Text('Texture', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _preferenceChip(
            'No preference',
            'texture-any',
            _preferences.texture == 'any',
            () => setState(
              () =>
                  _preferences = MealPreferences(flavour: _preferences.flavour),
            ),
          ),
          _preferenceChip(
            'Soft',
            'texture-soft',
            _preferences.texture == 'soft',
            () => setState(
              () => _preferences = MealPreferences(
                texture: 'soft',
                flavour: _preferences.flavour,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Text('Flavour', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _preferenceChip(
            'No preference',
            'flavour-any',
            _preferences.flavour == 'any',
            () => setState(
              () =>
                  _preferences = MealPreferences(texture: _preferences.texture),
            ),
          ),
          _preferenceChip(
            'Mild',
            'flavour-mild',
            _preferences.flavour == 'mild',
            () => setState(
              () => _preferences = MealPreferences(
                texture: _preferences.texture,
                flavour: 'mild',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      if (_error != null) ...[
        _notice(_error!, error: true),
        const SizedBox(height: 18),
      ],
      FilledButton.icon(
        key: const Key('submit'),
        onPressed: _submitting || _changes.isEmpty ? null : _submit,
        icon: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: 'Making preview',
                ),
              )
            : const Icon(Icons.auto_awesome_outlined),
        label: Text(
          _submitting
              ? 'Making your preview…'
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

  Widget _preferenceChip(
    String label,
    String key,
    bool selected,
    VoidCallback onPressed,
  ) => ChoiceChip(
    key: Key(key),
    label: Text(label),
    selected: selected,
    onSelected: _submitting ? null : (_) => onPressed(),
    selectedColor: const Color(0xFFE1EBD7),
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  List<Widget> _showPreview() {
    final preview = _preview!;
    return [
      Text(
        'Your meal,\na little different.',
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 14),
      Text(preview.summary),
      const SizedBox(height: 22),
      _notice(
        'SIMULATED ILLUSTRATION\nThese are symbolic drawings, not photographs or AI model output. They do not verify nutrition, texture, allergens or clinical safety.',
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) {
          final original = _plateCard('Original idea', preview.dish, const []);
          final requested = _plateCard(
            'Requested idea',
            preview.dish,
            preview.targets.map((t) => t.id).toList(),
          );
          return constraints.maxWidth >= 600
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: original),
                    const SizedBox(width: 16),
                    Expanded(child: requested),
                  ],
                )
              : Column(
                  children: [original, const SizedBox(height: 16), requested],
                );
        },
      ),
      const SizedBox(height: 26),
      Text(
        'What you requested',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      ...preview.targets.map(
        (target) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.check_circle_outline, color: _ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
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
            ],
          ),
        ),
      ),
      Text(preview.preferences.textureLabel),
      const SizedBox(height: 4),
      Text(preview.preferences.flavourLabel),
      const SizedBox(height: 22),
      ...preview.notices.map(
        (notice) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _notice(notice),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('edit'),
        onPressed: () => _goTo(1),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Change my choices'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('new-meal'),
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt),
        label: const Text('Try another meal'),
      ),
    ];
  }

  Widget _plateCard(String title, Dish dish, List<String> changes) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFEAEDE2),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        PlateIllustration(dish: dish, changeIds: changes, label: title),
        Text(dish.name, style: Theme.of(context).textTheme.titleMedium),
        const Text('Simulated plate illustration'),
      ],
    ),
  );

  Widget _notice(String text, {bool error = false}) => Semantics(
    liveRegion: error,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFBE9E3) : const Color(0xFFEEE8D5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline : Icons.info_outline,
            color: error ? const Color(0xFF9C2520) : _ink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 17,
                height: 1.45,
                color: error ? const Color(0xFF7E211E) : _ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
