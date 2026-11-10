import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_meal_preview/api.dart';
import 'package:senior_meal_preview/main.dart';
import 'package:senior_meal_preview/models.dart';

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
  await tapKey(tester, 'continue');
}

void main() {
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
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('continue'))).onPressed,
      isNull,
    );
    await selectMeal(tester);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
      isNull,
    );
    await tapKey(tester, 'change-extra_vegetables');
    await tapKey(tester, 'change-brown_rice');
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('change-sauce_on_side')),
          )
          .onChanged,
      isNull,
    );
    await tapKey(tester, 'back');
    await selectMeal(tester, id: 'fish_soup');
    expect(find.byKey(const Key('change-brown_rice')), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('change-extra_vegetables')),
          )
          .value,
      false,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
      isNull,
    );
  });

  testWidgets(
    'submission shows simulated preview, edit retains and reset clears',
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
      expect(find.text('Simulated plate illustration'), findsNWidgets(2));
      expect(find.text('Original idea'), findsOneWidget);
      expect(find.text('Requested idea'), findsOneWidget);
      expect(find.text('Soft texture requested'), findsOneWidget);
      await tapKey(tester, 'edit');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('change-extra_vegetables')),
            )
            .value,
        true,
      );
      await tapKey(tester, 'reset');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('continue')))
            .onPressed,
        isNull,
      );
      await selectMeal(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('texture-any')))
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
    expect(find.text('Try preview again'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('change-extra_vegetables')),
          )
          .value,
      true,
    );
    api.failPreview = false;
    await tapKey(tester, 'submit');
    expect(api.previewCalls, 2);
    expect(find.text('Requested idea'), findsOneWidget);
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
      tester.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
      isNull,
    );
    expect(api.previewCalls, 1);
    await tester.ensureVisible(find.byKey(const Key('back')));
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    api.pending!.complete(MealPreview.fromJson(previewJson()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dish-chicken_rice')), findsOneWidget);
    expect(find.text('Requested idea'), findsNothing);
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
    await tester.pumpAndSettle();
    api.pending!.complete(MealPreview.fromJson(previewJson()));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('continue'))).onPressed,
      isNull,
    );
    expect(find.text('Requested idea'), findsNothing);
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
    expect(find.text('Requested idea'), findsNothing);
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
    expect(find.text('Requested idea'), findsNothing);
  });

  testWidgets('all steps fit a narrow screen at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await selectMeal(tester);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'change-extra_vegetables');
    await tapKey(tester, 'texture-soft');
    await tapKey(tester, 'submit');
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

      expect(find.text('Step 1 of 3 · Choose a meal'), findsOneWidget);
      expect(find.text('Choose a familiar meal'), findsOneWidget);

      await selectMeal(tester);
      expect(find.text('Step 2 of 3 · Make it yours'), findsOneWidget);
      expect(find.text('Choose 1 or 2 changes'), findsOneWidget);
      expect(
        find.text('0 of 2 selected. Choose at least one change to continue.'),
        findsOneWidget,
      );

      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'change-brown_rice');
      expect(
        find.text('2 of 2 selected. Remove one to choose another.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unavailable-sauce_on_side')),
        findsOneWidget,
      );

      // Going back to the same meal preserves selections; switching meals clears them.
      await tapKey(tester, 'back');
      await tapKey(tester, 'continue');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('change-extra_vegetables')),
            )
            .value,
        true,
      );

      await tapKey(tester, 'back');
      await selectMeal(tester, id: 'fish_soup');
      expect(find.text('Choose this change to see an idea'), findsOneWidget);
      expect(
        find.text('0 of 1 selected. Choose this change to continue.'),
        findsOneWidget,
      );
      expect(find.text('Choose 1 or 2 changes'), findsNothing);
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
    'preview places request summary before plates with neutral bullets and supports back navigation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MealPreviewApp(api: FakeApi()));
      await tester.pumpAndSettle();
      await selectMeal(tester);
      expect(
        find.text(
          'A texture request only. This does not check swallowing safety.',
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'submit');

      expect(find.text('Step 3 of 3 · See the idea'), findsOneWidget);
      expect(find.text('Your requested meal idea'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      final summaryTop = tester
          .getTopLeft(find.byKey(const Key('request-summary')))
          .dy;
      final plateTop = tester
          .getTopLeft(find.byKey(const Key('plate-original')))
          .dy;
      expect(summaryTop, lessThan(plateTop));

      // System back returns to Step 2 with choices intact, then Step 1.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3 · Make it yours'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 3 · Choose a meal'), findsOneWidget);
    },
  );

  testWidgets(
    'Tailscale GPU preview mode appears when server advertises capability and renders provenance card',
    (tester) async {
      final api = FakeApi()..gpuPreviewEnabled = true;
      await tester.pumpWidget(MealPreviewApp(api: api));
      await tester.pumpAndSettle();
      await selectMeal(tester);

      expect(find.byKey(const Key('render-gpu')), findsOneWidget);
      await tapKey(tester, 'change-extra_vegetables');
      await tapKey(tester, 'render-gpu');
      await tapKey(tester, 'submit');

      expect(api.sentRenderMode, 'gpu_assisted');
      expect(find.byKey(const Key('gpu-preview-card')), findsOneWidget);
      expect(find.text('Tailscale GPU model preview'), findsOneWidget);
      expect(
        find.text(
          'AI-generated preview · Not a real meal or clinical verification',
        ),
        findsOneWidget,
      );
    },
  );
}
