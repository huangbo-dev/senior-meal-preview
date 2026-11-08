import 'package:senior_meal_preview/models.dart';

final catalogJson = <String, dynamic>{
  'schema_version': 1,
  'mode': 'illustrative_only',
  'dishes': [
    {
      'id': 'chicken_rice',
      'name': 'Chicken rice',
      'description': 'A familiar rice meal',
      'color': '#E6AD63',
    },
    {
      'id': 'fish_soup',
      'name': 'Fish soup',
      'description': 'A light soup meal',
      'color': '#8DBCC3',
    },
    {
      'id': 'tofu_rice',
      'name': 'Tofu rice',
      'description': 'A plant-based rice meal',
      'color': '#A7BA85',
    },
  ],
  'changes': [
    {
      'id': 'extra_vegetables',
      'label': 'Add vegetables',
      'description': 'An illustrative extra vegetable side',
      'dish_ids': ['chicken_rice', 'fish_soup', 'tofu_rice'],
    },
    {
      'id': 'brown_rice',
      'label': 'Try brown rice',
      'description': 'An illustrative rice swap',
      'dish_ids': ['chicken_rice', 'tofu_rice'],
    },
    {
      'id': 'sauce_on_side',
      'label': 'Sauce on the side',
      'description': 'An illustrative serving change',
      'dish_ids': ['chicken_rice', 'tofu_rice'],
    },
  ],
  'notice':
      'Prototype only. Illustrations are not model results or nutrition advice.',
};

final catalog = Catalog.fromJson(catalogJson);

Map<String, dynamic> previewJson({
  String dishId = 'chicken_rice',
  List<String> changes = const ['extra_vegetables'],
  MealPreferences preferences = const MealPreferences(),
}) => {
  'schema_version': 1,
  'mode': 'illustrative_only',
  'dish': (catalogJson['dishes'] as List).firstWhere((d) => d['id'] == dishId),
  'edit_targets': catalog.changes
      .where((c) => changes.contains(c.id))
      .map((c) => {'id': c.id, 'label': c.label, 'description': c.description})
      .toList(),
  'preferences': preferences.toJson(),
  'summary': 'An illustrative meal idea based on your choices.',
  'notices': [
    'Prototype only. No model was run.',
    'Preferences are requests, not verified properties.',
  ],
};
