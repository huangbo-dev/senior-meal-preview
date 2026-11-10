import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_meal_preview/api.dart';
import 'package:senior_meal_preview/main.dart';
import 'package:senior_meal_preview/models.dart';
import 'package:senior_meal_preview/widgets.dart';

import 'fixtures.dart';

class FakeApi implements MealApi {
  bool failCatalog = false;
  bool failPreview = false;
  bool gpuPreviewEnabled = false;
  int catalogCalls = 0;
  int previewCalls = 0;
  String? sentDish;
  List<String>? sentChanges;
  MealPreferences? sentPreferences;
  String? sentRenderMode;
  Completer<MealPreview>? pending;

  @override
  Future<Catalog> fetchCatalog() async {
    catalogCalls++;
    if (failCatalog) {
      throw const ApiException('Cannot reach the local service.');
    }
    if (gpuPreviewEnabled) {
      return Catalog.fromJson({
        ...catalogJson,
        'capabilities': {'symbolic_preview': true, 'gpu_preview': true},
      });
    }
    return catalog;
  }

  @override
  Future<MealPreview> preview({
    required String dishId,
    required List<String> changeIds,
    required MealPreferences preferences,
    String renderMode = 'illustrative_only',
  }) async {
    previewCalls++;
    sentDish = dishId;
    sentChanges = changeIds;
    sentPreferences = preferences;
    sentRenderMode = renderMode;
    if (failPreview) {
      throw const ApiException('The local service took too long.');
    }
    if (pending != null) return pending!.future;
    final body = previewJson(
      dishId: dishId,
      changes: changeIds,
      preferences: preferences,
    );
    if (renderMode == 'gpu_assisted') {
      body['gpu_artifact'] = {
        'provider': 'tailscale-gpu-worker',
        'model': 'brushnet-sdxl+qwen2.5-vl-7b-4bit',
        'prompt_id': 't2_r1_hawker',
        'seed': 7,
        'attempts': 2,
        'checker_passed': true,
        'image_data_url':
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        'generated_label':
            'AI-generated preview · Not a real meal or clinical verification',
      };
    }
    return MealPreview.fromJson(body);
  }

  @override
  void close() {}
}

Future<void> tapKey(WidgetTester tester, String key) async {
  if ((key.startsWith('texture-') ||
          key.startsWith('flavour-') ||
          key.startsWith('render-')) &&
      find.byKey(Key(key)).evaluate().isEmpty) {
    await tapKey(tester, 'preferences-open');
  }
  if (key == 'submit' &&
      find.byKey(const Key('preferences-done')).evaluate().isNotEmpty) {
    await tapKey(tester, 'preferences-done');
  }
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> selectMeal(
  WidgetTester tester, {
  String id = 'chicken_rice',
}) async {
  await tapKey(tester, 'dish-$id');
}

void main() {
  testWidgets('primary action stays reachable while choices scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await tapKey(tester, 'dish-chicken_rice');
    await tapKey(tester, 'change-extra_vegetables');
    final before = tester.getRect(find.byKey(const Key('submit')));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('submit'))), before);
    expect(before.bottom, lessThanOrEqualTo(852));
    if (find.byKey(const Key('dish-chicken_rice')).evaluate().isNotEmpty) {
      await selectMeal(tester);
    }
    expect(tester.widget<StepProgress>(find.byType(StepProgress)).step, 1);
  });

  testWidgets(
    '200 percent text puts the primary action in scrollable content',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
        isNull,
      );
      await tapKey(tester, 'dish-chicken_rice');
      if (find.byKey(const Key('dish-chicken_rice')).evaluate().isNotEmpty) {
        await selectMeal(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('licensed reference-photo credits open and dismiss', (
    tester,
  ) async {
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await tapKey(tester, 'photo-credits');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(text, contains('Misaochan'));
    expect(text, contains('PaulMondal'));
    expect(text, contains('https://creativecommons.org/licenses/'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('screen reader can activate meal, back and change controls', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const Key('meal-semantics-chicken_rice')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await selectMeal(tester);
      expect(
        tester
            .getSemantics(find.byKey(const Key('back')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('change-extra_vegetables')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('floating navigation and action respect phone safe areas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    expect(
      tester.getTopLeft(find.byKey(const Key('back'))).dy,
      greaterThanOrEqualTo(59),
    );
    expect(
      tester.getBottomRight(find.byKey(const Key('submit'))).dy,
      lessThanOrEqualTo(818),
    );
  });

  testWidgets('catalog failure has retry and no fake fallback', (tester) async {
    final api = FakeApi()..failCatalog = true;
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Let’s reconnect'), findsOneWidget);
    expect(find.byKey(const Key('dish-chicken_rice')), findsNothing);
    api.failCatalog = false;
    await tapKey(tester, 'retry-catalog');
    expect(api.catalogCalls, 2);
    expect(find.byKey(const Key('dish-chicken_rice')), findsOneWidget);
  });

  testWidgets('meal and 1–2 change validation with compatibility filtering', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('continue')), findsNothing);
    await selectMeal(tester);
    expect(
      tester
          .widget<AppPrimaryButton>(find.byKey(const Key('submit')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'change-extra_vegetables');
    await tapKey(tester, 'change-brown_rice');
    expect(
      tester
          .widget<ChangeOption>(find.byKey(const Key('change-sauce_on_side')))
          .onChanged,
      isNull,
    );
    await tapKey(tester, 'back');
    await selectMeal(tester, id: 'fish_soup');
    expect(find.byKey(const Key('change-brown_rice')), findsNothing);
    expect(
      tester
          .widget<ChangeOption>(
            find.byKey(const Key('change-extra_vegetables')),
          )
          .value,
      false,
    );
    expect(
      tester
          .widget<AppPrimaryButton>(find.byKey(const Key('submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'submission shows honest demo summary, edit retains and reset clears',
    (tester) async {
      final api = FakeApi();
      await tester.pumpWidget(MealPreviewApp(api: api));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'texture-soft');
      await tapKey(tester, 'flavour-mild');
      await tapKey(tester, 'submit');
      expect(api.previewCalls, 1);
      expect(api.sentDish, 'chicken_rice');
      expect(api.sentChanges, ['extra_vegetables']);
      expect(api.sentPreferences!.texture, 'soft');
      expect(api.sentPreferences!.flavour, 'mild');
      expect(find.text('Demo summary · No model was run'), findsOneWidget);
      expect(find.text('Reference photo · Unchanged'), findsOneWidget);
      expect(find.text('Requested changes'), findsOneWidget);
      expect(find.text('Soft texture requested'), findsOneWidget);
      await tapKey(tester, 'edit');
      expect(
        tester
            .widget<ChangeOption>(
              find.byKey(const Key('change-extra_vegetables')),
            )
            .value,
        true,
      );
      await tapKey(tester, 'reset');
      await tapKey(tester, 'clear-confirm');
      expect(find.byKey(const Key('continue')), findsNothing);
      expect(find.text('Chicken rice'), findsOneWidget);
      await tapKey(tester, 'preferences-open');
      expect(
        tester
            .widget<PreferenceChoice>(find.byKey(const Key('texture-any')))
            .selected,
        true,
      );
    },
  );

  testWidgets('submission error keeps choices and can retry', (tester) async {
    final api = FakeApi()..failPreview = true;
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-extra_vegetables');
    await tapKey(tester, 'submit');
    expect(find.text('Try again'), findsOneWidget);
    expect(
      tester
          .widget<ChangeOption>(
            find.byKey(const Key('change-extra_vegetables')),
          )
          .value,
      true,
    );
    api.failPreview = false;
    await tapKey(tester, 'submit');
    expect(api.previewCalls, 2);
    expect(find.text('Requested changes'), findsOneWidget);
  });

  testWidgets('repeated submit is disabled and back ignores late responses', (
    tester,
  ) async {
    final api = FakeApi()..pending = Completer<MealPreview>();
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-extra_vegetables');
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(
      tester
          .widget<AppPrimaryButton>(find.byKey(const Key('submit')))
          .onPressed,
      isNull,
    );
    expect(api.previewCalls, 1);
    await tester.ensureVisible(find.byKey(const Key('back')));
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    api.pending!.complete(MealPreview.fromJson(previewJson()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dish-chicken_rice')), findsOneWidget);
    expect(find.text('Requested changes'), findsNothing);
  });

  testWidgets('reset during an in-flight request ignores its result', (
    tester,
  ) async {
    final api = FakeApi()..pending = Completer<MealPreview>();
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-extra_vegetables');
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('reset')));
    await tester.tap(find.byKey(const Key('reset')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('clear-confirm')));
    await tester.pumpAndSettle();
    api.pending!.complete(MealPreview.fromJson(previewJson()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('continue')), findsNothing);
    expect(find.text('Requested changes'), findsNothing);
  });

  testWidgets('wrong-dish response is rejected', (tester) async {
    final api = FakeApi()..pending = Completer<MealPreview>();
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-extra_vegetables');
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    api.pending!.complete(
      MealPreview.fromJson(previewJson(dishId: 'fish_soup')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The preview did not match your choices. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Requested changes'), findsNothing);
  });

  testWidgets('duplicate targets cannot replace a distinct requested change', (
    tester,
  ) async {
    final api = FakeApi()..pending = Completer<MealPreview>();
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-extra_vegetables');
    await tapKey(tester, 'change-brown_rice');
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    final valid = MealPreview.fromJson(previewJson());
    api.pending!.complete(
      MealPreview(
        dish: valid.dish,
        targets: [valid.targets.single, valid.targets.single],
        preferences: valid.preferences,
        summary: valid.summary,
        notices: valid.notices,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The preview did not match your choices. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Requested changes'), findsNothing);
  });

  testWidgets('all steps fit a narrow screen at 200 percent text scale', (
    tester,
  ) async {
    final previousFatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = previousFatal,
    );
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = FakeApi();
    await tester.pumpWidget(MealPreviewApp(api: api));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await selectMeal(tester);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'change-extra_vegetables');
    await tapKey(tester, 'texture-soft');
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'submit');
    expect(api.sentPreferences?.texture, 'soft');
    expect(find.text('Your meal request'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'new-meal');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visible meal controls have labels and accessible touch targets',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await selectMeal(tester);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets(
    'sentence-case progress, fish soup one-choice copy, and disabled reason',
    (tester) async {
      final api = FakeApi();
      await tester.pumpWidget(MealPreviewApp(api: api));
      await tester.pumpAndSettle();

      expect(tester.widget<StepProgress>(find.byType(StepProgress)).step, 0);
      expect(find.text('Choose a meal to personalise.'), findsOneWidget);

      await selectMeal(tester);
      expect(tester.widget<StepProgress>(find.byType(StepProgress)).step, 1);
      expect(find.text('Choose 1 or 2'), findsOneWidget);
      expect(find.text('Choose 1 or 2'), findsOneWidget);

      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'change-brown_rice');
      expect(find.text('Choose 1 or 2 · 2 selected'), findsOneWidget);
      expect(
        find.byKey(const Key('unavailable-sauce_on_side')),
        findsOneWidget,
      );

      // Going back to the same meal preserves selections; switching meals clears them.
      await tapKey(tester, 'back');
      if (find.byKey(const Key('dish-chicken_rice')).evaluate().isNotEmpty) {
        await selectMeal(tester);
      }
      expect(
        tester
            .widget<ChangeOption>(
              find.byKey(const Key('change-extra_vegetables')),
            )
            .value,
        true,
      );

      await tapKey(tester, 'back');
      await selectMeal(tester, id: 'fish_soup');
      expect(find.text('Choose this change'), findsOneWidget);
      expect(find.text('Choose this change'), findsOneWidget);
      expect(find.text('Choose 1 or 2'), findsNothing);
    },
  );

  testWidgets(
    'compact meal card at narrow width switches to stacked at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('meal-compact-chicken_rice')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('meal-stacked-chicken_rice')), findsNothing);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('meal-stacked-chicken_rice')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('meal-compact-chicken_rice')), findsNothing);
    },
  );

  testWidgets(
    'demo result labels unchanged reference and requests without synthetic plate output',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'preferences-open');
      expect(
        find.text(
          'A texture request only. This does not check swallowing safety.',
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'preferences-done');
      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'submit');

      expect(tester.widget<StepProgress>(find.byType(StepProgress)).step, 2);
      expect(find.text('Your meal request'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      final summaryTop = tester
          .getTopLeft(find.byKey(const Key('request-summary')))
          .dy;
      final plateTop = tester
          .getTopLeft(find.byKey(const Key('reference-unchanged')))
          .dy;
      expect(summaryTop, greaterThan(plateTop));

      // System back returns to Step 2 with choices intact, then Step 1.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<StepProgress>(find.byType(StepProgress)).step, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<StepProgress>(find.byType(StepProgress)).step, 0);
    },
  );

  testWidgets(
    'Tailscale GPU preview mode appears when server advertises capability and renders provenance card',
    (tester) async {
      final api = FakeApi()..gpuPreviewEnabled = true;
      await tester.pumpWidget(MealPreviewApp(api: api));
      await tester.pumpAndSettle();
      await selectMeal(tester);

      await tapKey(tester, 'preferences-open');
      expect(find.byKey(const Key('render-gpu')), findsOneWidget);
      await tapKey(tester, 'preferences-done');
      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'render-gpu');
      await tapKey(tester, 'submit');

      expect(api.sentRenderMode, 'gpu_assisted');
      expect(find.byKey(const Key('gpu-preview-card')), findsOneWidget);
      expect(find.text('Generated preview'), findsOneWidget);
      expect(
        find.text(
          'AI-generated preview · Not a real meal or clinical verification',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('compact catalog shows all three meals on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    for (final id in ['chicken_rice', 'fish_soup', 'tofu_rice']) {
      final rect = tester.getRect(find.byKey(Key('dish-$id')));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(852));
    }
  });

  testWidgets(
    'editing shows changes and optional preferences above the action',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      expect(
        tester.getBottomRight(find.byKey(const Key('preferences-open'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('submit'))).dy),
      );
      expect(find.byKey(const Key('texture-soft')), findsNothing);
    },
  );

  testWidgets(
    'preference sheet applies explicitly and discards drafts on system-back dismissal',
    (tester) async {
      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'preferences-open');
      await tapKey(tester, 'texture-soft');
      await tapKey(tester, 'preferences-done');
      expect(find.text('Soft texture'), findsOneWidget);
      await tapKey(tester, 'preferences-open');
      expect(
        tester
            .widget<PreferenceChoice>(find.byKey(const Key('texture-soft')))
            .selected,
        isTrue,
      );
      await tapKey(tester, 'flavour-mild');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('preferences-done')), findsNothing);
      expect(find.text('Soft texture'), findsOneWidget);
      expect(find.text('Soft texture · Mild flavour'), findsNothing);
      expect(tester.widget<StepProgress>(find.byType(StepProgress)).step, 1);
    },
  );
  testWidgets('preferences sheet has labeled accessible tap targets', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'preferences-open');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  });
  testWidgets('clear choices requires confirmation and retains the meal', (
    tester,
  ) async {
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-extra_vegetables');
    await tapKey(tester, 'reset');
    await tapKey(tester, 'clear-cancel');
    expect(
      tester
          .widget<ChangeOption>(
            find.byKey(const Key('change-extra_vegetables')),
          )
          .selected,
      isTrue,
    );
    await tapKey(tester, 'reset');
    await tapKey(tester, 'clear-confirm');
    expect(find.text('Chicken rice'), findsOneWidget);
    expect(
      tester
          .widget<ChangeOption>(
            find.byKey(const Key('change-extra_vegetables')),
          )
          .selected,
      isFalse,
    );
    expect(find.text('Choose a change'), findsOneWidget);
  });

  testWidgets('selection has visible feedback and screen reader limit reason', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'change-extra_vegetables');
      expect(
        find.byKey(const Key('selected-feedback-extra_vegetables')),
        findsOneWidget,
      );
      expect(find.text('Review 1 change'), findsOneWidget);
      await tapKey(tester, 'change-brown_rice');
      expect(find.text('Review 2 changes'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const Key('change-sauce_on_side')))
            .getSemanticsData()
            .hint,
        contains('Remove a selected change'),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('Cancel preferences leaves the applied choices unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'texture-soft');
    await tapKey(tester, 'preferences-cancel');
    expect(find.text('Optional · No preference'), findsOneWidget);
    await tapKey(tester, 'preferences-open');
    expect(
      tester
          .widget<PreferenceChoice>(find.byKey(const Key('texture-any')))
          .selected,
      isTrue,
    );
  });
  testWidgets('incidental sheet gestures do not discard a preference draft', (
    tester,
  ) async {
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'texture-soft');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preferences-done')), findsOneWidget);
    await tester.drag(find.byType(BottomSheet), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preferences-done')), findsOneWidget);
    await tapKey(tester, 'preferences-done');
    expect(find.text('Soft texture'), findsOneWidget);
  });

  testWidgets(
    'choosing another meal preserves choices until a different meal is chosen',
    (tester) async {
      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'texture-soft');
      await tapKey(tester, 'submit');
      await tapKey(tester, 'new-meal');
      await selectMeal(tester);
      expect(
        tester
            .widget<ChangeOption>(
              find.byKey(const Key('change-extra_vegetables')),
            )
            .selected,
        isTrue,
      );
      expect(find.text('Soft texture'), findsOneWidget);
      await tapKey(tester, 'back');
      await tapKey(tester, 'dish-fish_soup');
      expect(find.text('Choose this change'), findsOneWidget);
      expect(find.text('Optional · No preference'), findsOneWidget);
    },
  );
}
