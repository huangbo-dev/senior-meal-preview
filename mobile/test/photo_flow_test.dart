import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:senior_meal_preview/main.dart';
import 'package:senior_meal_preview/photo_flow.dart';

import 'widget_test.dart' show FakeApi, fakeCameraPng;

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Future<void> _openPhotoPage(WidgetTester tester, FakeApi api) async {
  await tester.pumpWidget(MealPreviewApp(api: api));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('open-photo-edit')));
  await tester.tap(find.byKey(const Key('open-photo-edit')));
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
}
