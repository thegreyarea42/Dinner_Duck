import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class RecipeService {
  /// Cleans ingredient names by removing quantities and units.
  static String cleanIngredientName(String input) {
    String cleaned = input.toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r'\d+\s*x\s*\d+[a-z]*|\d+[a-z]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\d+(/\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞]|\d+'), '');
    final noisePattern = RegExp(
      r'\b(tbsp|tsp|tablespoon|tablespoons|teaspoon|teaspoons|clove|cloves|can|cans|cup|cups|g|gram|grams|ml|l|lb|oz|pinch|small bunch|large bunch|finely chopped|chopped|crushed|sliced into strips|shredded|of)\b',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(noisePattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'[,.*•▢\-\$\(\)]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return "";
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  static String cleanText(String text) {
    return text
        .replaceAll(RegExp(r'▢'), '')
        .replaceAll(RegExp(r'Print Recipe|Checkboxes|Advertisements?', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future<Map<String, dynamic>> scrapeRecipe(String url) async {
    String urlText = url.trim();
    if (urlText.isEmpty) throw Exception('Enter a link to begin');
    if (!urlText.startsWith('http')) {
      urlText = 'https://$urlText';
    }

    final response = await http.get(Uri.parse(urlText), headers: {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) throw Exception('Failed to load page');

    final document = parser.parse(response.body);
    String? scrapedTitle;
    List<String> scrapedIngredients = [];
    List<String> scrapedInstructions = [];

    // Try JSON-LD first
    final scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (var script in scripts) {
      try {
        final json = jsonDecode(script.text);
        void findRecipe(dynamic data) {
          if (scrapedIngredients.isNotEmpty && scrapedInstructions.isNotEmpty) return;
          if (data is Map) {
            bool isRecipe = data['@type'] == 'Recipe' ||
                (data['@type'] is List && data['@type'].contains('Recipe'));
            if (isRecipe) {
              scrapedTitle ??= data['name']?.toString();
              if (data['recipeIngredient'] is List) {
                scrapedIngredients = List<String>.from(
                        data['recipeIngredient'].map((e) => cleanText(e.toString())))
                    .where((e) => e.isNotEmpty)
                    .toList();
              }
              final inst = data['recipeInstructions'];
              if (inst is List) {
                for (var step in inst) {
                  if (step is String) {
                    scrapedInstructions.add(cleanText(step));
                  } else if (step is Map) {
                    if (step['text'] != null) {
                      scrapedInstructions.add(cleanText(step['text'].toString()));
                    } else if (step['itemListElement'] != null) {
                      for (var subStep in step['itemListElement']) {
                        if (subStep is Map && subStep['text'] != null) {
                          scrapedInstructions.add(cleanText(subStep['text'].toString()));
                        } else if (subStep is Map && subStep['name'] != null) {
                          scrapedInstructions.add(cleanText(subStep['name'].toString()));
                        }
                      }
                    }
                  }
                }
              } else if (inst is String) {
                scrapedInstructions.add(cleanText(inst));
              }
            } else {
              data.forEach((key, value) => findRecipe(value));
            }
          } else if (data is List) {
            for (var item in data) {
              findRecipe(item);
            }
          }
        }
        findRecipe(json);
      } catch (_) {}
    }

    // CSS Selectors if JSON-LD fails
    if (scrapedIngredients.isEmpty) {
      final sel = [
        '.wprm-recipe-ingredient',
        '.tasty-recipe-ingredients li',
        '.mv-create-ingredients li',
        '[itemprop="recipeIngredient"]'
      ];
      for (var s in sel) {
        final el = document.querySelectorAll(s);
        if (el.isNotEmpty) {
          scrapedIngredients = el.map((e) => cleanText(e.text)).where((e) => e.isNotEmpty).toList();
          break;
        }
      }
    }
    if (scrapedInstructions.isEmpty) {
      final sel = [
        '.wprm-recipe-instruction-text',
        '.tasty-recipe-ingredients li',
        '.mv-create-ingredients li',
        '[itemprop="recipeInstructions"] li',
        '.instruction-step',
        '.recipe-steps li'
      ];
      for (var s in sel) {
        final el = document.querySelectorAll(s);
        if (el.isNotEmpty) {
          scrapedInstructions = el.map((e) => cleanText(e.text)).where((e) => e.isNotEmpty).toList();
          break;
        }
      }
    }

    // Heuristics
    if (scrapedIngredients.isEmpty || scrapedInstructions.isEmpty) {
      final headers = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
      for (var header in headers) {
        final text = header.text.toLowerCase();
        if (scrapedIngredients.isEmpty && text.contains('ingredients')) {
          var next = header.nextElementSibling;
          while (next != null && !['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].contains(next.localName)) {
            final items = next.querySelectorAll('li');
            if (items.isNotEmpty) {
              scrapedIngredients = items.map((e) => cleanText(e.text)).where((e) => e.isNotEmpty).toList();
              break;
            }
            next = next.nextElementSibling;
          }
        }
        if (scrapedInstructions.isEmpty && (text.contains('instructions') || text.contains('directions'))) {
          var next = header.nextElementSibling;
          while (next != null && !['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].contains(next.localName)) {
            final items = next.querySelectorAll('li, p');
            if (items.isNotEmpty) {
              final candidates = items.map((e) => cleanText(e.text)).where((e) => e.length > 10).toList();
              if (candidates.isNotEmpty) {
                scrapedInstructions.addAll(candidates);
                break;
              }
            }
            next = next.nextElementSibling;
          }
        }
      }
    }

    scrapedTitle ??= document.querySelector('h1')?.text.trim() ?? document.querySelector('title')?.text.trim();

    return {
      'title': scrapedTitle != null ? cleanText(scrapedTitle!) : '',
      'ingredients': scrapedIngredients,
      'instructions': scrapedInstructions,
      'link': urlText,
    };
  }
}
