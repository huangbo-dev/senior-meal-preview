import 'dart:collection';

class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
  });
  final String id;
  final String name;
  final String description;
  final String color;

  factory Dish.fromJson(Map<String, dynamic> json) => Dish(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    color: json['color'] as String,
  );
}

class MealChange {
  const MealChange({
    required this.id,
    required this.label,
    required this.description,
    required this.dishIds,
  });
  final String id;
  final String label;
  final String description;
  final List<String> dishIds;

  factory MealChange.fromJson(Map<String, dynamic> json) => MealChange(
    id: json['id'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
    dishIds: List<String>.unmodifiable(json['dish_ids'] as List),
  );
}

class Catalog {
  Catalog({
    required List<Dish> dishes,
    required List<MealChange> changes,
    required this.notice,
  }) : dishes = UnmodifiableListView(dishes),
       changes = UnmodifiableListView(changes);
  final List<Dish> dishes;
  final List<MealChange> changes;
  final String notice;

  factory Catalog.fromJson(Map<String, dynamic> json) {
    _requireIllustrativeSchema(json);
    final dishes = (json['dishes'] as List)
        .map((e) => Dish.fromJson(e as Map<String, dynamic>))
        .toList();
    final changes = (json['changes'] as List)
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
    );
  }
}

class MealPreferences {
  const MealPreferences({this.texture = 'any', this.flavour = 'any'});
  final String texture;
  final String flavour;
  Map<String, String> toJson() => {'texture': texture, 'flavour': flavour};
  String get textureLabel =>
      texture == 'soft' ? 'Soft texture requested' : 'No texture preference';
  String get flavourLabel =>
      flavour == 'mild' ? 'Mild flavour requested' : 'No flavour preference';
}

class EditTarget {
  const EditTarget({
    required this.id,
    required this.label,
    required this.description,
  });
  final String id;
  final String label;
  final String description;

  factory EditTarget.fromJson(Map<String, dynamic> json) => EditTarget(
    id: json['id'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
  );
}

class MealPreview {
  const MealPreview({
    required this.dish,
    required this.targets,
    required this.preferences,
    required this.summary,
    required this.notices,
  });
  final Dish dish;
  final List<EditTarget> targets;
  final MealPreferences preferences;
  final String summary;
  final List<String> notices;

  factory MealPreview.fromJson(Map<String, dynamic> json) {
    _requireIllustrativeSchema(json);
    final preferences = json['preferences'] as Map<String, dynamic>;
    final texture = preferences['texture'] as String;
    final flavour = preferences['flavour'] as String;
    final targets = (json['edit_targets'] as List)
        .map((e) => EditTarget.fromJson(e as Map<String, dynamic>))
        .toList();
    if (!['any', 'soft'].contains(texture) ||
        !['any', 'mild'].contains(flavour) ||
        targets.isEmpty ||
        targets.length > 2 ||
        targets.map((t) => t.id).toSet().length != targets.length) {
      throw const FormatException('Invalid preview.');
    }
    return MealPreview(
      dish: Dish.fromJson(json['dish'] as Map<String, dynamic>),
      targets: List<EditTarget>.unmodifiable(targets),
      preferences: MealPreferences(texture: texture, flavour: flavour),
      summary: json['summary'] as String,
      notices: List<String>.unmodifiable(json['notices'] as List),
    );
  }
}

void _requireIllustrativeSchema(Map<String, dynamic> json) {
  if (json['schema_version'] != 1 || json['mode'] != 'illustrative_only') {
    throw const FormatException('Unsupported response.');
  }
}
