/// A data model representing a cooking recipe.
/// 
/// Contains all the necessary information to display, schedule, and
/// generate shopping list items for a recipe.
class Recipe {
  final String title;
  final List<String> ingredients;
  final List<String> instructions;
  final String mealType;
  final DateTime date;
  final String link;
  bool isBookmarked;

  Recipe({
    required this.title,
    required this.ingredients,
    required this.instructions,
    required this.mealType,
    required this.date,
    this.link = '',
    this.isBookmarked = false,
  });

  /// Converts the [Recipe] instance to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'title': title,
    'ingredients': ingredients,
    'instructions': instructions,
    'mealType': mealType,
    'date': date.toIso8601String(),
    'link': link,
    'isBookmarked': isBookmarked,
  };

  /// Creates a [Recipe] instance from a JSON map.
  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
    title: json['title'],
    ingredients: List<String>.from(json['ingredients']),
    instructions: List<String>.from(json['instructions']),
    mealType: json['mealType'],
    date: DateTime.parse(json['date']),
    link: json['link'] ?? '',
    isBookmarked: json['isBookmarked'] ?? false,
  );
}
