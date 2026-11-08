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
  int catalogCalls = 0;
  int previewCalls = 0;
  String? sentDish;
  List<String>? sentChanges;
  MealPreferences? sentPreferences;
  Completer<MealPreview>? pending;

  @override
  Future<Catalog> fetchCatalog() async {
    catalogCalls++;
    if (failCatalog) {
      throw const ApiException('Cannot reach the local service.');
    }
    return catalog;
  }

  @override
  Future<MealPreview> preview({
    required String dishId,
    required List<String> changeIds,
    required MealPreferences preferences,
  }) async {
    previewCalls++;
    sentDish = dishId;
    sentChanges = changeIds;
    sentPreferences = preferences;
    if (failPreview) {
      throw const ApiException('The local service took too long.');
    }
    if (pending != null) return pending!.future;
    return MealPreview.fromJson(
      previewJson(dishId: dishId, changes: changeIds, preferences: preferences),
    );
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
}
