import 'package:flutter_test/flutter_test.dart';
import 'package:senior_meal_preview/models.dart';

Map<String, dynamic> _artifact(String model) => {
  'provider': 'tailscale-gpu-worker',
  'model': model,
  'prompt_id': 'p',
  'seed': 0,
  'attempts': 1,
  'checker_passed': false,
  'image_data_url': 'data:image/png;base64,AA==',
  'generated_label':
      'Recoloured, not reviewed by a person · Not nutrition, allergen or clinical verification',
};

void main() {
  test('a recolour-only result is recognised, an AI edit is not', () {
    expect(
      GpuArtifact.fromJson(
        _artifact(
          'lab-recolour (no generative model)+Qwen/Qwen2.5-VL-7B-Instruct',
        ),
      ).recolourOnly,
      isTrue,
    );
    expect(
      GpuArtifact.fromJson(
        _artifact(
          'sdxl-base-1.0 masked image-to-image + lab-recolour (no generative model)+Qwen',
        ),
      ).recolourOnly,
      isFalse,
    );
  });
}
