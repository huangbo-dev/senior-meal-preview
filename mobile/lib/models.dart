import 'dart:collection';

/// A catalog meal that can be previewed with one or two serving changes.
class Dish {
  /// Creates a [Dish] with its catalog identifier, display text, and accent hex.
  const Dish({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
  });

  /// Stable catalog identifier (for example, `'chicken_rice'`).
  final String id;

  /// Human-readable dish title shown on meal cards.
  final String name;

  /// Short plain-language summary of the dish.
  final String description;

  /// Hex colour token associated with the dish in the catalog.
  final String color;

  /// Decodes a [Dish] from a validated catalog or preview JSON object.
  factory Dish.fromJson(Map<String, dynamic> json) => Dish(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    color: json['color'] as String,
  );
}

/// A selectable serving modification supported by one or more catalog dishes.
class MealChange {
  /// Creates a [MealChange] option.
  const MealChange({
    required this.id,
    required this.label,
    required this.description,
    required this.dishIds,
  });

  /// Stable change identifier (for example, `'extra_vegetables'`).
  final String id;

  /// Short action label shown on the checkbox card.
  final String label;

  /// Plain-language explanation of the illustrative change.
  final String description;

  /// Dish identifiers compatible with this serving change.
  final List<String> dishIds;

  /// Decodes a [MealChange] from the catalog JSON payload.
  factory MealChange.fromJson(Map<String, dynamic> json) => MealChange(
    id: json['id'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
    dishIds: List<String>.unmodifiable(
      (json['dish_ids'] as List<dynamic>).cast<String>(),
    ),
  );
}

/// Bounds on how many serving changes a single preview request may include.
///
/// Published by the API catalog under `selection`; servers that predate the
/// field default to 1–2 changes.
class SelectionRules {
  /// Creates [SelectionRules] with minimum and maximum change counts.
  const SelectionRules({this.minChanges = 1, this.maxChanges = maxSupported});

  /// Maximum number of edit targets supported by the v1 preview contract.
  static const maxSupported = 2;

  /// Minimum number of changes required to request a preview.
  final int minChanges;

  /// Maximum number of changes allowed in a single preview request.
  final int maxChanges;

  /// Decodes [SelectionRules] from the optional `selection` catalog field.
  factory SelectionRules.fromJson(Object? json) => switch (json) {
    null => const SelectionRules(),
    {'min_changes': final int min, 'max_changes': final int max}
        when min >= 1 && max >= min && max <= maxSupported =>
      SelectionRules(minChanges: min, maxChanges: max),
    _ => throw const FormatException('Unsupported selection rules.'),
  };

  /// Returns the effective maximum changes for a dish with [available] options.
  int maxFor(int available) => available < maxChanges ? available : maxChanges;
}

/// Preview rendering capabilities advertised by `GET /api/v1/catalog`.
class CatalogCapabilities {
  /// Creates [CatalogCapabilities] flags.
  const CatalogCapabilities({
    this.symbolicPreview = true,
    this.gpuPreview = false,
    this.photoUpload = false,
  });

  /// Whether deterministic symbolic plate illustrations are available.
  final bool symbolicPreview;

  /// Whether the private Tailscale GPU model worker is configured.
  final bool gpuPreview;

  /// Whether `POST /api/v1/photo-preview` can edit a photo the user takes.
  final bool photoUpload;

  /// Decodes [CatalogCapabilities] from the optional `capabilities` JSON map.
  factory CatalogCapabilities.fromJson(Object? json) => switch (json) {
    null => const CatalogCapabilities(),
    {'symbolic_preview': true, 'gpu_preview': final bool gpu} =>
      CatalogCapabilities(
        gpuPreview: gpu,
        photoUpload: (json as Map)['photo_upload'] == true,
      ),
    _ => throw const FormatException('Symbolic preview must remain enabled.'),
  };
}

/// Complete meal and change catalog returned by `GET /api/v1/catalog`.
class Catalog {
  /// Creates an immutable [Catalog].
  Catalog({
    required List<Dish> dishes,
    required List<MealChange> changes,
    required this.notice,
    this.selection = const SelectionRules(),
    this.capabilities = const CatalogCapabilities(),
  }) : dishes = UnmodifiableListView(dishes),
       changes = UnmodifiableListView(changes);

  /// Available dishes in display order.
  final List<Dish> dishes;

  /// Available serving changes across all dishes.
  final List<MealChange> changes;

  /// Mandatory non-clinical disclosure notice attached to the catalog.
  final String notice;

  /// Enforced min/max change selection bounds.
  final SelectionRules selection;

  /// Server-advertised preview rendering capabilities.
  final CatalogCapabilities capabilities;

  /// Filters [changes] to those compatible with [dishId], preserving order.
  List<MealChange> changesFor(String dishId) =>
      changes.where((change) => change.dishIds.contains(dishId)).toList();

  /// Validates and decodes a [Catalog] response from `GET /api/v1/catalog`.
  factory Catalog.fromJson(Map<String, dynamic> json) {
    _requireIllustrativeSchema(json);
    final dishes = (json['dishes'] as List<dynamic>)
        .map((e) => Dish.fromJson(e as Map<String, dynamic>))
        .toList();
    final changes = (json['changes'] as List<dynamic>)
        .map((e) => MealChange.fromJson(e as Map<String, dynamic>))
        .toList();
    if (dishes.isEmpty ||
        dishes.map((d) => d.id).toSet().length != dishes.length ||
        changes.map((c) => c.id).toSet().length != changes.length) {
      throw const FormatException('Invalid catalog.');
    }
    return Catalog(
      dishes: dishes,
      changes: changes,
      notice: json['notice'] as String,
      selection: SelectionRules.fromJson(json['selection']),
      capabilities: CatalogCapabilities.fromJson(json['capabilities']),
    );
  }
}

/// In-memory texture and seasoning preferences sent with a preview request.
class MealPreferences {
  /// Creates [MealPreferences] defaulting to `'any'` for both dimensions.
  const MealPreferences({this.texture = 'any', this.flavour = 'any'});

  /// Requested texture preference (`'any'` or `'soft'`).
  final String texture;

  /// Requested seasoning preference (`'any'` or `'mild'`).
  final String flavour;

  /// Serializes preferences for `POST /api/v1/preview`.
  Map<String, String> toJson() => {'texture': texture, 'flavour': flavour};

  /// Human-readable summary of [texture] for the request summary card.
  String get textureLabel =>
      texture == 'soft' ? 'Soft texture requested' : 'No texture preference';

  /// Human-readable summary of [flavour] for the request summary card.
  String get flavourLabel =>
      flavour == 'mild' ? 'Mild flavour requested' : 'No flavour preference';
}

/// A resolved serving modification echoed back in a [MealPreview] response.
class EditTarget {
  /// Creates an [EditTarget].
  const EditTarget({
    required this.id,
    required this.label,
    required this.description,
  });

  /// Stable change identifier matching [MealChange.id].
  final String id;

  /// Short title of the requested change.
  final String label;

  /// Plain-language description of the requested change.
  final String description;

  /// Decodes an [EditTarget] from a JSON map.
  factory EditTarget.fromJson(Map<String, dynamic> json) => EditTarget(
    id: json['id'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
  );
}

/// Provenance and image payload returned by the private Tailscale GPU worker.
class GpuArtifact {
  /// Creates a validated [GpuArtifact].
  const GpuArtifact({
    required this.provider,
    required this.model,
    required this.promptId,
    required this.seed,
    required this.attempts,
    required this.checkerPassed,
    required this.imageDataUrl,
    required this.generatedLabel,
  });

  /// Worker provider identifier (for example, `'tailscale-gpu-worker'`).
  final String provider;

  /// Diffusion + VLM selector pipeline identifier.
  final String model;

  /// Locked prompt template identifier selected by the worker.
  final String promptId;

  /// Deterministic generation seed.
  final int seed;

  /// Number of check-and-retry attempts executed (`1..=8`).
  final int attempts;

  /// Whether the automatic VLM selector accepted the candidate.
  ///
  /// Reported strictly for provenance and never as clinical ground truth.
  final bool checkerPassed;

  /// Base64-encoded PNG data URL (`data:image/png;base64,...`).
  final String imageDataUrl;

  /// Mandatory non-clinical disclosure attached to the generated preview.
  final String generatedLabel;

  /// Validates and decodes a [GpuArtifact] from `gpu_artifact` JSON.
  factory GpuArtifact.fromJson(Map<String, dynamic> json) {
    if (json
        case {
          'provider': final String provider,
          'model': final String model,
          'prompt_id': final String promptId,
          'seed': final int seed,
          'attempts': final int attempts,
          'checker_passed': final bool checkerPassed,
          'image_data_url': final String imageDataUrl,
          'generated_label': final String generatedLabel,
        }
        when provider.isNotEmpty &&
            model.isNotEmpty &&
            promptId.isNotEmpty &&
            attempts >= 1 &&
            attempts <= 8 &&
            imageDataUrl.startsWith('data:image/png;base64,') &&
            generatedLabel.toLowerCase().contains('not')) {
      return GpuArtifact(
        provider: provider,
        model: model,
        promptId: promptId,
        seed: seed,
        attempts: attempts,
        checkerPassed: checkerPassed,
        imageDataUrl: imageDataUrl,
        generatedLabel: generatedLabel,
      );
    }
    throw const FormatException('Invalid GPU artifact.');
  }
}

/// Validated response from `POST /api/v1/preview`.
class MealPreview {
  /// Creates a [MealPreview] response model.
  const MealPreview({
    required this.dish,
    required this.targets,
    required this.preferences,
    required this.summary,
    required this.notices,
    this.gpuArtifact,
  });

  /// Selected dish echoed by the backend.
  final Dish dish;

  /// Requested serving modifications in selection order.
  final List<EditTarget> targets;

  /// Echoed texture and seasoning preferences.
  final MealPreferences preferences;

  /// Plain-language summary of the requested meal idea.
  final String summary;

  /// Mandatory safety and scope notices to display alongside the preview.
  final List<String> notices;

  /// Optional GPU-generated artifact when `render_mode` is `'gpu_assisted'`.
  final GpuArtifact? gpuArtifact;

  /// Validates and decodes a [MealPreview] from `POST /api/v1/preview`.
  factory MealPreview.fromJson(Map<String, dynamic> json) {
    _requireIllustrativeSchema(json);
    final preferences = json['preferences'] as Map<String, dynamic>;
    final texture = preferences['texture'] as String;
    final flavour = preferences['flavour'] as String;
    final targets = (json['edit_targets'] as List<dynamic>)
        .map((e) => EditTarget.fromJson(e as Map<String, dynamic>))
        .toList();
    if (!['any', 'soft'].contains(texture) ||
        !['any', 'mild'].contains(flavour) ||
        targets.isEmpty ||
        targets.length > SelectionRules.maxSupported ||
        targets.map((t) => t.id).toSet().length != targets.length) {
      throw const FormatException('Invalid preview.');
    }
    final rawArtifact = json['gpu_artifact'];
    return MealPreview(
      dish: Dish.fromJson(json['dish'] as Map<String, dynamic>),
      targets: List<EditTarget>.unmodifiable(targets),
      preferences: MealPreferences(texture: texture, flavour: flavour),
      summary: json['summary'] as String,
      notices: List<String>.unmodifiable(
        (json['notices'] as List<dynamic>).cast<String>(),
      ),
      gpuArtifact: rawArtifact == null
          ? null
          : GpuArtifact.fromJson(rawArtifact as Map<String, dynamic>),
    );
  }
}

void _requireIllustrativeSchema(Map<String, dynamic> json) {
  if (json['schema_version'] != 1 || json['mode'] != 'illustrative_only') {
    throw const FormatException('Unsupported response.');
  }
}

/// A change the model can make to a user's own photo (research tasks only).
class PhotoChange {
  const PhotoChange(this.id, this.label, this.paintHint);

  /// Catalog change identifier sent to the API.
  final String id;

  /// Short label shown on the choice.
  final String label;

  /// What the user should paint over.
  final String paintHint;

  static const all = [
    PhotoChange(
      'brown_rice',
      'Swap white rice for brown rice',
      'Paint over the white rice.',
    ),
    PhotoChange(
      'extra_vegetables',
      'Add some broccoli',
      'Paint over the rice where the broccoli should go.',
    ),
  ];
}

/// Validated response from `POST /api/v1/photo-preview`.
class PhotoEditResult {
  const PhotoEditResult({
    required this.editTarget,
    required this.notices,
    required this.artifact,
  });

  final EditTarget editTarget;
  final List<String> notices;
  final GpuArtifact artifact;

  factory PhotoEditResult.fromJson(Map<String, dynamic> json) {
    if (json case {
      'schema_version': 1,
      'edit_target': final Map<String, dynamic> target,
      'notices': final List<dynamic> notices,
      'gpu_artifact': final Map<String, dynamic> artifact,
    }) {
      return PhotoEditResult(
        editTarget: EditTarget.fromJson(target),
        notices: notices.cast<String>(),
        artifact: GpuArtifact.fromJson(artifact),
      );
    }
    throw const FormatException('Invalid photo edit response.');
  }
}
