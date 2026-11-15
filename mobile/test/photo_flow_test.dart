import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:senior_meal_preview/main.dart';
import 'package:senior_meal_preview/photo_flow.dart';
import 'package:senior_meal_preview/picture_store.dart';

import 'widget_test.dart' show FakeApi, fakeCameraPng, selectMeal, tapKey;

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Future<void> _openPhotoPage(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(MealPreviewApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

Future<void> _scrollTo(WidgetTester tester, Key key, {bool up = false}) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    up ? -150 : 150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  test('progress estimate rises with time and never shows complete', () {
    expect(photoEditProgress(0, 15), 0);
    var last = 0.0;
    for (var s = 1; s <= 120; s++) {
      final p = photoEditProgress(s, 15);
      expect(p, greaterThanOrEqualTo(last));
      expect(p, lessThan(1));
      last = p;
    }
    for (final typical in [4, 15]) {
      expect(photoEditProgress(typical, typical), inInclusiveRange(0.7, 0.85));
    }
  });

  testWidgets(
    'photo edit is reachable from Meals and off when server says so',
    (tester) async {
      await _openPhotoPage(tester, FakeApi()..photoUpload = false);
      expect(find.text('Change your own meal photo'), findsOneWidget);
      expect(find.textContaining('switched off'), findsOneWidget);
      final camera = tester.widget<Widget>(
        find.byKey(const Key('photo-camera')),
      );
      expect((camera as dynamic).onPressed, isNull);
    },
  );

  testWidgets('the app opens on the own-photo tab; Meals is a side tab', (
    tester,
  ) async {
    await _openPhotoPage(tester, FakeApi());
    expect(find.text('Change your own meal photo'), findsOneWidget);
    expect(
      find.byKey(const Key('dish-chicken_rice')).hitTestable(),
      findsNothing,
    );
    final bar = tester.widget<NavigationBar>(find.byKey(const Key('tab-bar')));
    expect(bar.selectedIndex, 0);
    expect((bar.destinations.first as NavigationDestination).label, 'My photo');
    await tester.tap(find.byKey(const Key('tab-meals')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('dish-chicken_rice')).hitTestable(),
      findsOneWidget,
    );
    // System back from a side tab returns to the home tab instead of leaving.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.text('Change your own meal photo').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('take photo, paint rice, get before and after back', (
    tester,
  ) async {
    final api = FakeApi();
    tester.view.physicalSize = const Size(700, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final png = (await tester.runAsync(fakeCameraPng))!;
    ImageSource? asked;
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoEditPage(
          api: api,
          available: true,
          picker: (source) async {
            asked = source;
            return png;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('photo-change-brown_rice')));
    await tester.tap(find.byKey(const Key('photo-camera')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('paint-area')));
    expect(asked, ImageSource.camera);

    // Nothing painted yet: cannot submit.
    await _scrollTo(tester, const Key('photo-submit'));
    expect(find.text('Paint the rice first'), findsOneWidget);

    await _scrollTo(tester, const Key('paint-area'), up: true);
    final area = tester.getRect(find.byKey(const Key('paint-area')));
    await tester.dragFrom(area.center, const Offset(60, 20));
    await tester.pump();
    await _scrollTo(tester, const Key('photo-submit'));
    await tester.tap(find.byKey(const Key('photo-submit')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('photo-result-label')));

    expect(api.sentPhotoChange, 'brown_rice');
    expect(api.sentPhoto!.sublist(0, 8), _pngSignature);
    expect(api.sentMask!.sublist(0, 8), _pngSignature);
    final sizes = await tester.runAsync(() async {
      Future<(int, int, int)> info(Uint8List bytes) async {
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        var white = 0;
        for (var i = 0; i < data!.lengthInBytes; i += 4) {
          if (data.getUint8(i) > 127) white++;
        }
        return (image.width, image.height, white);
      }

      return (await info(api.sentPhoto!), await info(api.sentMask!));
    });
    // Landscape photo was centre-cropped to the model's square working size.
    expect((sizes!.$1.$1, sizes.$1.$2), (photoSide, photoSide));
    expect((sizes.$2.$1, sizes.$2.$2), (photoSide, photoSide));
    // Painted area is a small part of the mask, not empty and not everything.
    final fraction = sizes.$2.$3 / (photoSide * photoSide);
    expect(fraction, greaterThan(0.005));
    expect(fraction, lessThan(0.5));

    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.textContaining('not reviewed by a person'), findsWidgets);
    expect(find.textContaining('not a human review'), findsOneWidget);
  });

  testWidgets('server refusal keeps the photo and painting for another try', (
    tester,
  ) async {
    final api = FakeApi()..photoError = 'Paint over the rice only.';
    tester.view.physicalSize = const Size(700, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final png = (await tester.runAsync(fakeCameraPng))!;
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoEditPage(
          api: api,
          available: true,
          picker: (_) async => png,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('paint-area')));
    final area = tester.getRect(find.byKey(const Key('paint-area')));
    await tester.tapAt(area.center);
    await tester.pump();
    await _scrollTo(tester, const Key('photo-submit'));
    await tester.tap(find.byKey(const Key('photo-submit')));
    await tester.pump();
    await _pumpUntil(tester, find.text('Paint over the rice only.'));
    expect(find.byKey(const Key('paint-area')), findsOneWidget);
    expect(find.text('Make the change'), findsOneWidget);
  });

  Future<FakeApi> openAuto(
    WidgetTester tester, {
    bool autoMask = true,
    void Function(FakeApi)? setUp,
  }) async {
    final api = FakeApi();
    setUp?.call(api);
    tester.view.physicalSize = const Size(700, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final png = (await tester.runAsync(fakeCameraPng))!;
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoEditPage(
          api: api,
          available: true,
          autoMask: autoMask,
          picker: (_) async => png,
        ),
      ),
    );
    return api;
  }

  testWidgets('with automatic rice finding a chosen photo is edited with '
      'no painting, and both changes can be made at once', (tester) async {
    final api = await openAuto(tester);
    await tester.tap(
      find.byKey(const Key('photo-change-brown_rice+extra_vegetables')),
    );
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('photo-auto-submit')));
    await tester.ensureVisible(find.byKey(const Key('photo-auto-submit')));
    await tester.tap(find.byKey(const Key('photo-auto-submit')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('photo-result-label')));

    expect(api.sentPhotoChange, 'brown_rice+extra_vegetables');
    expect(api.sentPhoto!.sublist(0, 8), _pngSignature);
    expect(api.sentMask, isNull);
    expect(find.byKey(const Key('paint-area')), findsNothing);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    // Two changes cannot be painted as one area, so no manual fallback.
    expect(find.byKey(const Key('photo-paint-instead')), findsNothing);
  });

  testWidgets('when the rice is not found the user can paint it instead', (
    tester,
  ) async {
    final api = await openAuto(
      tester,
      setUp: (api) => api
        ..photoError = 'We could not find rice in this photo.'
        ..photoErrorCode = 'rice_not_found',
    );
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('photo-auto-submit')));
    await tester.ensureVisible(find.byKey(const Key('photo-auto-submit')));
    await tester.tap(find.byKey(const Key('photo-auto-submit')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('paint-area')));
    expect(find.textContaining('could not find the rice'), findsOneWidget);
    expect(api.sentMask, isNull);

    api.photoError = null;
    final area = tester.getRect(find.byKey(const Key('paint-area')));
    await tester.tapAt(area.center);
    await tester.pump();
    await _scrollTo(tester, const Key('photo-submit'));
    await tester.tap(find.byKey(const Key('photo-submit')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('photo-result-label')));
    expect(api.sentMask!.sublist(0, 8), _pngSignature);
    expect(api.photoCalls, 2);
  });

  testWidgets('an automatic result can be redone by marking the rice by hand', (
    tester,
  ) async {
    await openAuto(tester);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('photo-auto-submit')));
    await tester.ensureVisible(find.byKey(const Key('photo-auto-submit')));
    await tester.tap(find.byKey(const Key('photo-auto-submit')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('photo-paint-instead')));
    await tester.tap(find.byKey(const Key('photo-paint-instead')));
    await tester.pump();
    expect(find.byKey(const Key('paint-area')), findsOneWidget);
    expect(find.text('Paint the rice first'), findsOneWidget);
  });

  testWidgets('a failed upload keeps the crop and allows a different edit', (
    tester,
  ) async {
    final api = await openAuto(
      tester,
      setUp: (api) => api.photoError = 'Server busy',
    );
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await _pumpUntil(tester, find.byKey(const Key('photo-auto-submit')));
    expect(api.photoCalls, 0);
    await tester.tap(find.byKey(const Key('photo-auto-submit')));
    await _pumpUntil(tester, find.text('Server busy'));
    final firstPhoto = api.sentPhoto;
    api.photoError = null;
    await tester.tap(find.byKey(const Key('photo-change-extra_vegetables')));
    await tester.tap(find.byKey(const Key('photo-auto-submit')));
    await _pumpUntil(tester, find.byKey(const Key('photo-result-label')));
    expect(api.sentPhoto, firstPhoto);
    expect(api.sentPhotoChange, 'extra_vegetables');
  });

  testWidgets(
    'summary only skips the image even if both methods are available',
    (tester) async {
      final api = FakeApi()
        ..autoMask = true
        ..gpuPreviewEnabled = true;
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MealPreviewApp(api: api, initialTab: AppTab.meals),
      );
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'change-brown_rice');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(find.text('Your meal request'), findsOneWidget);
      expect(api.photoCalls, 0);
    },
  );

  testWidgets(
    'fish soup with added vegetables returns a summary without a rice edit',
    (tester) async {
      final api = FakeApi()..autoMask = true;
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MealPreviewApp(api: api, initialTab: AppTab.meals),
      );
      await tester.pumpAndSettle();
      await selectMeal(tester, id: 'fish_soup');
      await tapKey(tester, 'change-extra_vegetables');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(find.text('Your meal request'), findsOneWidget);
      expect(api.photoCalls, 0);
    },
  );

  testWidgets('painting on the photo does not scroll the page', (tester) async {
    await openAuto(tester, autoMask: false);
    tester.view.physicalSize = const Size(400, 700);
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('paint-area')));
    final before = tester.getRect(find.byKey(const Key('paint-area')));
    await tester.dragFrom(before.center, const Offset(0, -120));
    await tester.pump();
    expect(tester.getRect(find.byKey(const Key('paint-area'))), before);
    expect(find.text('Make the change'), findsOneWidget);
  });

  testWidgets('servers without automatic rice finding keep the painted flow '
      'and do not offer two changes', (tester) async {
    await openAuto(tester, autoMask: false);
    expect(
      find.byKey(const Key('photo-change-brown_rice+extra_vegetables')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('photo-gallery')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('paint-area')));
  });

  testWidgets('Meals review shows a real edited picture of the meal when the '
      'server finds the rice itself', (tester) async {
    final api = FakeApi()..autoMask = true;
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MealPreviewApp(api: api, initialTab: AppTab.meals));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-brown_rice');
    await tapKey(tester, 'change-sauce_on_side');
    expect(find.text('Generate preview'), findsOneWidget);
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('meal-picture')));

    expect(api.sentPhotoChange, 'brown_rice');
    expect(api.sentMask, isNull);
    expect(api.sentPhoto!.sublist(0, 8), _pngSignature);
    expect(find.text('Your preview'), findsOneWidget);
    expect(find.textContaining('No picture'), findsNothing);
    expect(find.textContaining('not reviewed by a person'), findsOneWidget);
    expect(find.byKey(const Key('picture-not-shown')), findsOneWidget);
    expect(find.byKey(const Key('before-after')), findsOneWidget);
  });

  testWidgets('Meals review falls back to the honest summary when no picture '
      'can be made', (tester) async {
    final api = FakeApi()
      ..autoMask = true
      ..photoError = 'We could not find rice in this photo.'
      ..photoErrorCode = 'rice_not_found';
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MealPreviewApp(api: api, initialTab: AppTab.meals));
    await tester.pumpAndSettle();
    await selectMeal(tester);
    await tapKey(tester, 'change-brown_rice');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    await _pumpUntil(tester, find.byKey(const Key('picture-note')));
    expect(find.text('Your meal request'), findsOneWidget);
    expect(find.byKey(const Key('meal-picture')), findsNothing);
    expect(find.textContaining('No picture'), findsWidgets);
  });

  testWidgets('a meal picture is saved and shown again at once, and a new '
      'one can be asked for', (tester) async {
    final api = FakeApi()..autoMask = true;
    final store = MemoryPictureStore();
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> review() async {
      await tester.pumpWidget(
        MealPreviewApp(api: api, initialTab: AppTab.meals, pictures: store),
      );
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'change-brown_rice');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      await _pumpUntil(tester, find.byKey(const Key('meal-picture')));
    }

    await review();
    expect(api.photoCalls, 1);
    expect(find.byKey(const Key('picture-saved')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await review();
    expect(api.photoCalls, 1, reason: 'the saved picture is reused');
    expect(find.byKey(const Key('picture-saved')), findsOneWidget);

    await tester.tap(find.byKey(const Key('picture-new')));
    await tester.pump();
    for (var i = 0; i < 50 && api.photoCalls < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(api.photoCalls, 2);
  });

  testWidgets(
    'a saved meal picture is shown even while the server is failing',
    (tester) async {
      final api = FakeApi()..autoMask = true;
      final store = MemoryPictureStore();
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MealPreviewApp(api: api, initialTab: AppTab.meals, pictures: store),
      );
      await tester.pumpAndSettle();
      await selectMeal(tester);
      await tapKey(tester, 'change-brown_rice');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      await _pumpUntil(tester, find.byKey(const Key('meal-picture')));
      api.photoError = 'Another picture is being made right now.';
      await tester.ensureVisible(find.byKey(const Key('meal-picture')));
      // No saved notice yet, so ask again through the review step's own flow.
      await tester.tap(find.byKey(const Key('edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      await _pumpUntil(tester, find.byKey(const Key('picture-saved')));
      expect(find.byKey(const Key('meal-picture')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('picture-new')));
      await tester.tap(find.byKey(const Key('picture-new')));
      await _pumpUntil(
        tester,
        find.textContaining('The new picture could not be made'),
      );
      expect(find.byKey(const Key('meal-picture')), findsOneWidget);
    },
  );
}
