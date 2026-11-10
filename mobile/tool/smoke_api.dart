import 'dart:io';

import 'package:senior_meal_preview/api.dart';
import 'package:senior_meal_preview/models.dart';

/// Run against an already-started local Rust API. No server is spawned here.
Future<void> main() async {
  final api = HttpMealApi(
    baseUrl: Platform.environment['API_BASE_URL'] ?? 'http://127.0.0.1:8787',
  );
  try {
    final catalog = await api.fetchCatalog();
    if (catalog.dishes.length != 3 ||
        catalog.selection.minChanges != 1 ||
        catalog.selection.maxChanges != 2) {
      throw StateError('Expected three demo meals and 1–2 selection rules.');
    }
    stdout.writeln(
      'PASS: Production client decoded catalog (${catalog.dishes.length} meals).',
    );
    final preview = await api.preview(
      dishId: 'chicken_rice',
      changeIds: ['extra_vegetables', 'brown_rice'],
      preferences: const MealPreferences(texture: 'soft', flavour: 'mild'),
    );
    if (preview.dish.id != 'chicken_rice' ||
        preview.targets.length != 2 ||
        preview.preferences.texture != 'soft' ||
        preview.preferences.flavour != 'mild') {
      throw StateError('Preview did not match the request.');
    }
    stdout.writeln('PASS: Production client decoded preview and preferences.');
    await _expectBackendError(
      () => api.preview(
        dishId: 'not_a_dish',
        changeIds: ['extra_vegetables'],
        preferences: const MealPreferences(),
      ),
      'unknown dish',
      'Choose a meal from the catalog.',
    );
    await _expectBackendError(
      () => api.preview(
        dishId: 'fish_soup',
        changeIds: ['brown_rice'],
        preferences: const MealPreferences(),
      ),
      'incompatible change',
      'That change is not available for this meal.',
    );
    if (catalog.capabilities.gpuPreview) {
      final gpuPreview = await api.preview(
        dishId: 'chicken_rice',
        changeIds: ['extra_vegetables', 'brown_rice'],
        preferences: const MealPreferences(texture: 'soft', flavour: 'mild'),
        renderMode: 'gpu_assisted',
      );
      if (gpuPreview.gpuArtifact == null ||
          !gpuPreview.gpuArtifact!.imageDataUrl.startsWith(
            'data:image/png;base64,',
          )) {
        throw StateError('Expected valid GPU artifact from worker bridge.');
      }
      stdout.writeln(
        'PASS: Production client decoded Tailscale GPU worker artifact (${gpuPreview.gpuArtifact!.promptId}).',
      );
    }
    stdout.writeln('All live Rust/Flutter API smoke checks passed.');
  } catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  } finally {
    api.close();
  }
}

Future<void> _expectBackendError(
  Future<MealPreview> Function() request,
  String label,
  String expectedMessage,
) async {
  try {
    await request();
  } on ApiException catch (error) {
    // A timeout, generic server failure or different validation error must fail.
    if (error.message != expectedMessage) {
      throw StateError('Unexpected error for $label: ${error.message}');
    }
    stdout.writeln('PASS: Backend rejected $label: ${error.message}');
    return;
  }
  throw StateError('Backend accepted $label.');
}
