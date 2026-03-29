/// Dinner Duck - A Flutter application for meal planning, recipe management, and grocery listing.
///
/// This file contains the main entry point and all the core UI components and logic
/// for the Dinner Duck app, including meal scheduling, a personal cookbook,
/// and an automated grocery list generator.
library;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const DinnerDuckApp());
}

/// The root widget of the Dinner Duck application.
/// 
/// It initializes the [MaterialApp] with custom themes and handles
/// the persistence of global settings like dark mode and font size.
class DinnerDuckApp extends StatefulWidget {
  const DinnerDuckApp({super.key});

  @override
  State<DinnerDuckApp> createState() => _DinnerDuckAppState();
}

class _DinnerDuckAppState extends State<DinnerDuckApp> {
  bool _isDarkMode = false;
  double _fontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Loads the user's saved theme and font size preferences from [SharedPreferences].
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontSize = prefs.getDouble('fontSize') ?? 18.0;
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  /// Updates the application's global settings and triggers a rebuild.
  void _updateSettings(bool isDarkMode, double fontSize) {
    setState(() {
      _isDarkMode = isDarkMode;
      _fontSize = fontSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dinner Duck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF064E40),
          secondary: const Color(0xFFFFCC99), // Cream Orange
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF064E40),
          secondary: const Color(0xFF00C853), // Emerald
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MainScreen(
        initialFontSize: _fontSize,
        initialIsDarkMode: _isDarkMode,
        onSettingsChanged: _updateSettings,
      ),
    );
  }
}

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

/// The main application screen containing the navigation and primary state.
/// 
/// It manages the lifecycle of the meal plan, cookbook, and grocery list
/// and coordinates between the different feature screens.
class MainScreen extends StatefulWidget {
  final double initialFontSize;
  final bool initialIsDarkMode;
  final Function(bool, double) onSettingsChanged;
  const MainScreen({
    super.key,
    required this.initialFontSize,
    required this.initialIsDarkMode,
    required this.onSettingsChanged,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  List<Recipe> _mealPlans = [];
  List<Recipe> _cookbook = [];
  List<String> _groceryList = [];
  List<String> _staples = [];
  List<String> _categoryOrder = ['Produce', 'Dairy & Eggs', 'Meat & Seafood', 'Pantry', 'Other'];
  Map<String, int> _purchaseHistory = {};
  int _selectedIndex = 0;

  // Settings
  late double _fontSize;
  late bool _isDarkMode;
  bool _keepScreenOn = false;
  bool _isCompactView = false;
  bool _showFrequentlyBought = true;
  double _speechRate = 0.5;
  String? _currentlySpeakingText;

  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fontSize = widget.initialFontSize;
    _isDarkMode = widget.initialIsDarkMode;
    _loadData();

    _flutterTts.setCompletionHandler(() {
      setState(() => _currentlySpeakingText = null);
    });
    _flutterTts.setCancelHandler(() {
      setState(() => _currentlySpeakingText = null);
    });
    _flutterTts.setErrorHandler((msg) {
      setState(() => _currentlySpeakingText = null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      _updateWakelock();
    }
  }

  /// Loads all application data (meal plans, cookbook, etc.) from local storage.
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final plannerJson = prefs.getString('mealPlans');
    final cookbookJson = prefs.getString('cookbook');
    final groceryJson = prefs.getString('groceryList');
    final staplesJson = prefs.getString('staples');
    final orderJson = prefs.getString('categoryOrder');
    final historyJson = prefs.getString('purchaseHistory');

    // Load Settings
    _keepScreenOn = prefs.getBool('keepScreenOn') ?? false;
    _isCompactView = prefs.getBool('isCompactView') ?? false;
    _showFrequentlyBought = prefs.getBool('showFrequentlyBought') ?? true;
    _speechRate = prefs.getDouble('speechRate') ?? 0.5;

    setState(() {
      if (plannerJson != null) {
        _mealPlans = List<Recipe>.from(jsonDecode(plannerJson).map((x) => Recipe.fromJson(x)));
      }
      if (cookbookJson != null) {
        _cookbook = List<Recipe>.from(jsonDecode(cookbookJson).map((x) => Recipe.fromJson(x)));
      }
      if (groceryJson != null) {
        _groceryList = List<String>.from(jsonDecode(groceryJson));
      }
      if (staplesJson != null) {
        _staples = List<String>.from(jsonDecode(staplesJson));
      }
      if (orderJson != null) {
        _categoryOrder = List<String>.from(jsonDecode(orderJson));
      }
      if (historyJson != null) {
        _purchaseHistory = Map<String, int>.from(jsonDecode(historyJson));
      }
    });
    _updateWakelock();
  }

  /// Persists all current application data to local storage.
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mealPlans', jsonEncode(_mealPlans.map((x) => x.toJson()).toList()));
    await prefs.setString('cookbook', jsonEncode(_cookbook.map((x) => x.toJson()).toList()));
    await prefs.setString('groceryList', jsonEncode(_groceryList));
    await prefs.setString('staples', jsonEncode(_staples));
    await prefs.setString('categoryOrder', jsonEncode(_categoryOrder));
    await prefs.setString('purchaseHistory', jsonEncode(_purchaseHistory));
  }

  /// Saves user settings and notifies the parent widget of changes.
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', _fontSize);
    await prefs.setBool('isDarkMode', _isDarkMode);
    await prefs.setBool('keepScreenOn', _keepScreenOn);
    await prefs.setBool('isCompactView', _isCompactView);
    await prefs.setBool('showFrequentlyBought', _showFrequentlyBought);
    await prefs.setDouble('speechRate', _speechRate);
    widget.onSettingsChanged(_isDarkMode, _fontSize);
    _updateWakelock();
  }

  /// Toggles the device's wakelock based on current screen and settings.
  void _updateWakelock() {
    bool shouldBeOn = _keepScreenOn && (_selectedIndex == 0 || _selectedIndex == 1);
    WakelockPlus.toggle(enable: shouldBeOn);
  }

  /// Cleans ingredient names by removing quantities and units.
  String _cleanIngredientName(String input) {
    String cleaned = input.toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r'\d+\s*x\s*\d+[a-z]*|\d+[a-z]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\d+(/\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞]|\d+'), '');
    final noisePattern = RegExp(
      r'\b(tbsp|tsp|tablespoon|tablespoons|teaspoon|teaspoons|clove|cloves|can|cans|cup|cups|g|gram|grams|ml|l|lb|oz|pinch|small bunch|large bunch|finely chopped|chopped|crushed|sliced into strips|shredded|of)\b',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceAll(noisePattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'[,.*•▢\-]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return "";
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  void _addRecipe(Recipe recipe) {
    setState(() {
      _mealPlans.add(recipe);
      if (recipe.isBookmarked) {
        if (!_cookbook.any((r) => r.title == recipe.title)) {
          _cookbook.add(recipe);
        }
      }
      _saveData();
    });
  }

  void _updatePlanner(int index, Recipe recipe) {
    setState(() {
      final oldRecipe = _mealPlans[index];
      _mealPlans[index] = recipe;
      _updateCookbookRef(oldRecipe, recipe);
      _saveData();
    });
  }

  void _deleteFromPlanner(int index) {
    setState(() {
      _mealPlans.removeAt(index);
      _saveData();
    });
  }

  void _addToCookbook(Recipe recipe) {
    setState(() {
      if (!_cookbook.any((r) => r.title == recipe.title)) {
        _cookbook.add(recipe);
        _saveData();
      }
    });
  }

  void _removeFromCookbook(String title) {
    setState(() {
      _cookbook.removeWhere((r) => r.title == title);
      for (var p in _mealPlans) {
        if (p.title == title) p.isBookmarked = false;
      }
      _saveData();
    });
  }

  void _toggleBookmark(Recipe recipe) {
    setState(() {
      recipe.isBookmarked = !recipe.isBookmarked;
      if (recipe.isBookmarked) {
        if (!_cookbook.any((r) => r.title == recipe.title)) {
          _cookbook.add(recipe);
        }
      } else {
        _cookbook.removeWhere((r) => r.title == recipe.title);
      }
      _saveData();
    });
  }

  void _updateCookbookRef(Recipe oldR, Recipe newR) {
    int idx = _cookbook.indexWhere((r) => r.title == oldR.title);
    if (idx != -1) {
      _cookbook[idx] = newR;
    }
  }

  void _addToGroceryList(List<String> items) {
    setState(() {
      final Set<String> currentItems = _groceryList.toSet();
      for (var item in items) {
        String cleaned = _cleanIngredientName(item);
        if (cleaned.isNotEmpty) {
          currentItems.add(cleaned);
        }
      }
      _groceryList = currentItems.toList();
      _saveData();
    });
  }

  void _removeFromGroceryList(String item) {
    setState(() {
      _groceryList.remove(item);
      _purchaseHistory[item] = (_purchaseHistory[item] ?? 0) + 1;
      _saveData();
    });
  }

  void _updateGroceryItem(String oldItem, String newItem) {
    setState(() {
      int index = _groceryList.indexOf(oldItem);
      if (index != -1) {
        String cleaned = _cleanIngredientName(newItem);
        if (cleaned.isNotEmpty) {
          _groceryList[index] = cleaned;
        } else {
          _groceryList.removeAt(index);
        }
        _saveData();
      }
    });
  }

  void _clearGroceryList() {
    setState(() {
      _groceryList.clear();
      _saveData();
    });
  }

  void _addStaplesToGroceries() {
    if (_staples.isEmpty) {
      _showSettingsAndManageStaples();
      return;
    }
    setState(() {
      final Set<String> currentItems = _groceryList.toSet();
      currentItems.addAll(_staples);
      _groceryList = currentItems.toList();
      _saveData();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staples added to list!')));
  }

  void _showSettingsAndManageStaples() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          fontSize: _fontSize,
          isDarkMode: _isDarkMode,
          keepScreenOn: _keepScreenOn,
          isCompactView: _isCompactView,
          showFrequentlyBought: _showFrequentlyBought,
          speechRate: _speechRate,
          staples: _staples,
          categoryOrder: _categoryOrder,
          onSettingsChanged: (fontSize, isDarkMode, keepScreenOn, isCompactView, showFrequentlyBought, speechRate) {
            setState(() {
              _fontSize = fontSize;
              _isDarkMode = isDarkMode;
              _keepScreenOn = keepScreenOn;
              _isCompactView = isCompactView;
              _showFrequentlyBought = showFrequentlyBought;
              _speechRate = speechRate;
            });
            _saveSettings();
          },
          onStaplesChanged: (newStaples) {
            setState(() {
              _staples = newStaples;
            });
            _saveData();
          },
          onCategoryOrderChanged: (newOrder) {
            setState(() {
              _categoryOrder = newOrder;
            });
            _saveData();
          },
          onExport: () {
            String json = jsonEncode(_cookbook.map((e) => e.toJson()).toList());
            Share.share(json, subject: 'My Dinner Duck Cookbook');
          },
          onImport: (jsonStr) {
            try {
              final List<dynamic> list = jsonDecode(jsonStr);
              final List<Recipe> imported = list.map((x) => Recipe.fromJson(x)).toList();
              setState(() {
                for (var r in imported) {
                  if (!_cookbook.any((existing) => existing.title == r.title)) {
                    _cookbook.add(r);
                  }
                }
              });
              _saveData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cookbook items imported!')));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import failed: Invalid format')));
            }
          },
          autoOpenManageStaples: true,
        ),
      ),
    );
  }

  List<String> get _topFrequentSuggestions {
    var entries = _purchaseHistory.entries.where((e) => !_groceryList.contains(e.key)).toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).map((e) => e.key).toList();
  }

  /// Displays a dialog to review and add recipe ingredients to the shopping list.
  void _showAddToCartDialog(Recipe recipe) {
    final controller = TextEditingController(text: recipe.ingredients.join('\n'));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add to Shopping List',
            style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: SingleChildScrollView(
            child: TextField(
              controller: controller,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Review items...',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF064E40), foregroundColor: Colors.white),
            onPressed: () {
              final items = controller.text.split('\n').where((s) => s.trim().isNotEmpty).toList();
              _addToGroceryList(items);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items added!')));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Displays a dialog for creating or editing a recipe, including web scraping functionality.
  void _showRecipeDialog({Recipe? existingRecipe, int? index, bool isSchedulingFromCookbook = false}) {
    final titleController = TextEditingController(text: existingRecipe?.title ?? '');
    final ingredientsController = TextEditingController(text: existingRecipe?.ingredients.join('\n') ?? '');
    final instructionsController = TextEditingController(text: existingRecipe?.instructions.join('\n') ?? '');
    final linkController = TextEditingController(text: existingRecipe?.link ?? '');
    String selectedMealType = existingRecipe?.mealType ?? 'Dinner';
    DateTime selectedDate = existingRecipe?.date ?? DateTime.now();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> scrapeRecipe() async {
              String urlText = linkController.text.trim();
              if (urlText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a link to begin')));
                return;
              }
              if (!urlText.startsWith('http')) {
                urlText = 'https://$urlText';
                linkController.text = urlText;
              }
              setModalState(() => isLoading = true);

              String cleanText(String text) {
                return text
                    .replaceAll(RegExp(r'▢'), '')
                    .replaceAll(RegExp(r'Print Recipe|Checkboxes|Advertisements?', caseSensitive: false), '')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
              }

              try {
                final response = await http.get(Uri.parse(urlText), headers: {
                  'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
                }).timeout(const Duration(seconds: 15));

                if (response.statusCode == 200) {
                  final document = parser.parse(response.body);
                  String? scrapedTitle;
                  List<String> scrapedIngredients = [];
                  List<String> scrapedInstructions = [];

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

                  setModalState(() {
                    if (scrapedTitle != null) titleController.text = cleanText(scrapedTitle!);
                    if (scrapedIngredients.isNotEmpty) ingredientsController.text = scrapedIngredients.join('\n');
                    if (scrapedInstructions.isNotEmpty) instructionsController.text = scrapedInstructions.join('\n');
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Details captured!')));
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              } finally {
                setModalState(() => isLoading = false);
              }
            }

            return Dialog(
              backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text(existingRecipe == null || isSchedulingFromCookbook ? 'New Meal' : 'Edit Meal',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                            tooltip: 'Close dialog',
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: linkController,
                        decoration: InputDecoration(
                          labelText: 'Recipe Link',
                          border: const OutlineInputBorder(),
                          suffixIcon: isLoading
                              ? const Padding(
                              padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed: scrapeRecipe,
                            tooltip: 'Scrape recipe',
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Dish Title', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ingredientsController,
                        decoration:
                        const InputDecoration(labelText: 'Ingredients (one per line)', border: OutlineInputBorder()),
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: instructionsController,
                        decoration:
                        const InputDecoration(labelText: 'Instructions (one per line)', border: OutlineInputBorder()),
                        maxLines: 4,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedMealType,
                        decoration: const InputDecoration(labelText: 'Meal Type', border: OutlineInputBorder()),
                        items: ['Breakfast', 'Lunch', 'Dinner', 'Snack', 'Dessert', 'Cookbook']
                            .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                            .toList(),
                        onChanged: (value) => setModalState(() => selectedMealType = value!),
                      ),
                      const SizedBox(height: 12),
                      if (selectedMealType != 'Cookbook')
                        ListTile(
                          title: const Text('Date'),
                          subtitle: Text(
                              "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}"),
                          trailing: const Icon(Icons.calendar_today),
                          onTap: () async {
                            final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime(2101));
                            if (picked != null) setModalState(() => selectedDate = picked);
                          },
                        ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF064E40),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          if (titleController.text.isNotEmpty) {
                            final newRecipe = Recipe(
                              title: titleController.text,
                              ingredients:
                              ingredientsController.text.split('\n').where((s) => s.trim().isNotEmpty).toList(),
                              instructions:
                              instructionsController.text.split('\n').where((s) => s.trim().isNotEmpty).toList(),
                              mealType: selectedMealType,
                              date: selectedDate,
                              link: linkController.text,
                              isBookmarked: existingRecipe?.isBookmarked ?? false,
                            );
                            if (selectedMealType == 'Cookbook') {
                              _addToCookbook(newRecipe);
                            } else {
                              if (existingRecipe != null && !isSchedulingFromCookbook) {
                                _updatePlanner(index!, newRecipe);
                              } else {
                                _addRecipe(newRecipe);
                              }
                            }
                            Navigator.pop(context);
                          }
                        },
                        child: Text(existingRecipe == null || isSchedulingFromCookbook ? 'Save' : 'Apply Changes',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          fontSize: _fontSize,
          isDarkMode: _isDarkMode,
          keepScreenOn: _keepScreenOn,
          isCompactView: _isCompactView,
          showFrequentlyBought: _showFrequentlyBought,
          speechRate: _speechRate,
          staples: _staples,
          categoryOrder: _categoryOrder,
          onSettingsChanged: (fontSize, isDarkMode, keepScreenOn, isCompactView, showFrequentlyBought, speechRate) {
            setState(() {
              _fontSize = fontSize;
              _isDarkMode = isDarkMode;
              _keepScreenOn = keepScreenOn;
              _isCompactView = isCompactView;
              _showFrequentlyBought = showFrequentlyBought;
              _speechRate = speechRate;
            });
            _saveSettings();
          },
          onStaplesChanged: (newStaples) {
            setState(() {
              _staples = newStaples;
            });
            _saveData();
          },
          onCategoryOrderChanged: (newOrder) {
            setState(() {
              _categoryOrder = newOrder;
            });
            _saveData();
          },
          onExport: () {
            String json = jsonEncode(_cookbook.map((e) => e.toJson()).toList());
            Share.share(json, subject: 'My Dinner Duck Cookbook');
          },
          onImport: (jsonStr) {
            try {
              final List<dynamic> list = jsonDecode(jsonStr);
              final List<Recipe> imported = list.map((x) => Recipe.fromJson(x)).toList();
              setState(() {
                for (var r in imported) {
                  if (!_cookbook.any((existing) => existing.title == r.title)) {
                    _cookbook.add(r);
                  }
                }
              });
              _saveData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cookbook items imported!')));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import failed: Invalid format')));
            }
          },
        ),
      ),
    );
  }

  /// Triggers text-to-speech for the given text.
  void _speak(String text) async {
    if (_currentlySpeakingText == text) {
      await _flutterTts.stop();
      setState(() => _currentlySpeakingText = null);
    } else {
      await _flutterTts.stop();
      await _flutterTts.setSpeechRate(_speechRate);
      setState(() => _currentlySpeakingText = text);
      await _flutterTts.speak(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', height: 40, errorBuilder: (ctx, err, stack) => const Icon(Icons.flatware)),
            const SizedBox(width: 8),
            const Text('Dinner Duck', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF064E40))),
          ],
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
            tooltip: 'Settings',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ScheduleScreen(
            mealPlans: _mealPlans,
            onBookmarkToggled: _toggleBookmark,
            onEdit: (r) => _showRecipeDialog(existingRecipe: r, index: _mealPlans.indexOf(r)),
            onAddToCart: _showAddToCartDialog,
            onDelete: (index) => _deleteFromPlanner(index),
            fontSize: _fontSize,
            onSpeak: _speak,
            currentlySpeakingText: _currentlySpeakingText,
          ),
          CookbookScreen(
            cookbook: _cookbook,
            onRemove: _removeFromCookbook,
            onSchedule: (r) => _showRecipeDialog(existingRecipe: r, isSchedulingFromCookbook: true),
            onAddToCart: _showAddToCartDialog,
            fontSize: _fontSize,
            onSpeak: _speak,
            currentlySpeakingText: _currentlySpeakingText,
          ),
          GroceryListScreen(
            groceryList: _groceryList,
            onRemove: _removeFromGroceryList,
            onUpdate: _updateGroceryItem,
            onAddManual: (item) => _addToGroceryList([item]),
            onClearAll: _clearGroceryList,
            onAddStaples: _addStaplesToGroceries,
            onLongPressAddStaples: _showSettingsAndManageStaples,
            isCompactView: _isCompactView,
            showFrequentlyBought: _showFrequentlyBought,
            frequentSuggestions: _topFrequentSuggestions,
            fontSize: _fontSize,
            categoryOrder: _categoryOrder,
          ),
        ],
      ),
      floatingActionButton: Semantics(
        label: 'Add a new meal',
        button: true,
        child: FloatingActionButton(
          backgroundColor: const Color(0xFF064E40),
          foregroundColor: Colors.white,
          onPressed: () => _showRecipeDialog(),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() => _selectedIndex = i);
          _updateWakelock();
        },
        indicatorColor: const Color(0xFFFFCC99),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Planner'),
          NavigationDestination(icon: Icon(Icons.book), label: 'Cookbook'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Groceries'),
        ],
      ),
    );
  }
}

/// A button that toggles a bookmark state with a scale animation.
class AnimatedBookmarkButton extends StatefulWidget {
  final bool isBookmarked;
  final VoidCallback onTap;
  const AnimatedBookmarkButton({super.key, required this.isBookmarked, required this.onTap});

  @override
  State<AnimatedBookmarkButton> createState() => _AnimatedBookmarkButtonState();
}

class _AnimatedBookmarkButtonState extends State<AnimatedBookmarkButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _scaleAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.6), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.6, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.bounceOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool disableMotion = MediaQuery.of(context).disableAnimations;

    return Semantics(
      label: widget.isBookmarked ? 'Remove from cookbook' : 'Save to cookbook',
      button: true,
      child: ScaleTransition(
        scale: disableMotion ? const AlwaysStoppedAnimation(1.0) : _scaleAnimation,
        child: IconButton(
          icon: Icon(
            widget.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            color: widget.isBookmarked ? Colors.orange : Colors.grey,
            size: 40,
          ),
          onPressed: () {
            if (!disableMotion) _controller.forward(from: 0);
            widget.onTap();
          },
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ),
    );
  }
}

/// The settings screen where users can customize the application.
///
/// Provides controls for accessibility, theme, kitchen tools (converters),
/// and data management (export/import).
class SettingsScreen extends StatefulWidget {
  final double fontSize;
  final bool isDarkMode;
  final bool keepScreenOn;
  final bool isCompactView;
  final bool showFrequentlyBought;
  final double speechRate;
  final List<String> staples;
  final List<String> categoryOrder;
  final Function(double, bool, bool, bool, bool, double) onSettingsChanged;
  final Function(List<String>) onStaplesChanged;
  final Function(List<String>) onCategoryOrderChanged;
  final VoidCallback onExport;
  final Function(String) onImport;
  final bool autoOpenManageStaples;

  const SettingsScreen({
    super.key,
    required this.fontSize,
    required this.isDarkMode,
    required this.keepScreenOn,
    required this.isCompactView,
    required this.showFrequentlyBought,
    required this.speechRate,
    required this.staples,
    required this.categoryOrder,
    required this.onSettingsChanged,
    required this.onStaplesChanged,
    required this.onCategoryOrderChanged,
    required this.onExport,
    required this.onImport,
    this.autoOpenManageStaples = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _fontSize;
  late bool _isDarkMode;
  late bool _keepScreenOn;
  late bool _isCompactView;
  late bool _showFrequentlyBought;
  late double _speechRate;
  late List<String> _staples;
  late List<String> _categoryOrder;

  // Conversion Tool State
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();
  String _conversionType = 'Cups to ml';

  @override
  void initState() {
    super.initState();
    _fontSize = widget.fontSize;
    _isDarkMode = widget.isDarkMode;
    _keepScreenOn = widget.keepScreenOn;
    _isCompactView = widget.isCompactView;
    _showFrequentlyBought = widget.showFrequentlyBought;
    _speechRate = widget.speechRate;
    _staples = List.from(widget.staples);
    _categoryOrder = List.from(widget.categoryOrder);
    _loadConversionToolState();

    if (widget.autoOpenManageStaples) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showManageStaples());
    }
  }

  Future<void> _loadConversionToolState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _conversionType = prefs.getString('lastConversionType') ?? 'Cups to ml';
    });
  }

  Future<void> _saveConversionToolState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastConversionType', _conversionType);
  }

  void _notify() {
    widget.onSettingsChanged(_fontSize, _isDarkMode, _keepScreenOn, _isCompactView, _showFrequentlyBought, _speechRate);
  }

  /// Displays a dialog for managing standard pantry staple items.
  void _showManageStaples() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manage Staples'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Add staple (e.g. Milk)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          setDialogState(() {
                            _staples.add(controller.text.trim());
                            controller.clear();
                          });
                          widget.onStaplesChanged(_staples);
                        }
                      },
                      tooltip: 'Add item',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _staples.length,
                    itemBuilder: (context, index) => ListTile(
                      title: Text(_staples[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setDialogState(() {
                            _staples.removeAt(index);
                          });
                          widget.onStaplesChanged(_staples);
                        },
                        tooltip: 'Remove item',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Cookbook'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Paste JSON string here...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 48)),
            onPressed: () {
              widget.onImport(controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  /// Calculates cooking measurement conversions based on selected type and input.
  void _performConversion() {
    if (_inputController.text.isEmpty) {
      _resultController.text = '';
      return;
    }
    double input = double.tryParse(_inputController.text) ?? 0;
    double result = 0;

    switch (_conversionType) {
      case 'Cups to ml':
        result = input * 236.588;
        break;
      case 'tbsp to ml':
        result = input * 14.7868;
        break;
      case 'tsp to ml':
        result = input * 4.92892;
        break;
      case 'oz to g':
        result = input * 28.3495;
        break;
      case 'lbs to kg':
        result = input * 0.453592;
        break;
      case 'F to C':
        result = (input - 32) * 5 / 9;
        break;
    }

    _resultController.text = result.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final borderStyle = OutlineInputBorder(
      borderSide: BorderSide(color: Theme.of(context).primaryColor),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Readability Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Font Size: ${_fontSize.toInt()}pt'),
                Slider(
                  value: _fontSize,
                  min: 14,
                  max: 24,
                  divisions: 10,
                  onChanged: (val) {
                    setState(() => _fontSize = val);
                    _notify();
                  },
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Emerald High Contrast Theme'),
            value: _isDarkMode,
            onChanged: (val) {
              setState(() => _isDarkMode = val);
              _notify();
            },
          ),
          const Divider(),
          const ListTile(
            title: Text('Accessibility & Performance', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Speech Rate: ${_speechRate.toStringAsFixed(1)}x'),
                Slider(
                  value: _speechRate,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (val) {
                    setState(() => _speechRate = val);
                    _notify();
                  },
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Keep Screen On'),
            subtitle: const Text('Prevent sleeping while cooking'),
            value: _keepScreenOn,
            onChanged: (val) {
              setState(() => _keepScreenOn = val);
              _notify();
            },
          ),
          SwitchListTile(
            title: const Text('Compact Grocery List'),
            subtitle: const Text('Excellent for single long list view'),
            value: _isCompactView,
            onChanged: (val) {
              setState(() => _isCompactView = val);
              _notify();
            },
          ),
          SwitchListTile(
            title: const Text('Show Frequently Bought'),
            subtitle: const Text('Suggest top items at the head of your shopping list.'),
            value: _showFrequentlyBought,
            onChanged: (val) {
              setState(() => _showFrequentlyBought = val);
              _notify();
            },
          ),
          const Divider(),
          const ListTile(
            title: Text('Kitchen Toolkit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Semantics(
            label: 'Unit converter for cooking measurements',
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _inputController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Input',
                            border: borderStyle,
                            enabledBorder: borderStyle,
                          ),
                          onChanged: (_) => _performConversion(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _conversionType,
                          decoration: InputDecoration(
                            labelText: 'Type',
                            border: borderStyle,
                            enabledBorder: borderStyle,
                          ),
                          items: [
                            'Cups to ml',
                            'tbsp to ml',
                            'tsp to ml',
                            'oz to g',
                            'lbs to kg',
                            'F to C'
                          ].map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 14)))).toList(),
                          onChanged: (val) {
                            setState(() => _conversionType = val!);
                            _saveConversionToolState();
                            _performConversion();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _resultController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Result',
                      border: borderStyle,
                      enabledBorder: borderStyle,
                      fillColor: Theme.of(context).primaryColor.withOpacity(0.05),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Common Conversions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(height: 8),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    children: const [
                      TableRow(children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('1 tbsp = 15ml', style: TextStyle(fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('1/4 cup = 60ml', style: TextStyle(fontSize: 12))),
                      ]),
                      TableRow(children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('1 cup = 240ml', style: TextStyle(fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('1 oz = 28g', style: TextStyle(fontSize: 12))),
                      ]),
                      TableRow(children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('1 lb = 454g', style: TextStyle(fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('350F = 177C', style: TextStyle(fontSize: 12))),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text('Store Layout (Aisle Order)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            title: const Text('Manage Staples List'),
            subtitle: const Text('Items you always need to stock'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showManageStaples,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Sort Aisle Order (Drag to reorder):', style: TextStyle(fontSize: 14)),
          ),
          SizedBox(
            height: 300,
            child: ReorderableListView(
              shrinkWrap: true,
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                );
              },
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (int index = 0; index < _categoryOrder.length; index++)
                  ListTile(
                    key: Key(_categoryOrder[index]),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(_categoryOrder[index]),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: Semantics(
                        label: 'Drag to reorder ${_categoryOrder[index]} aisle',
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ),
                  ),
              ],
              onReorder: (oldIndex, newOrder) {
                setState(() {
                  if (newOrder > oldIndex) newOrder -= 1;
                  final item = _categoryOrder.removeAt(oldIndex);
                  _categoryOrder.insert(newOrder, item);
                });
                widget.onCategoryOrderChanged(_categoryOrder);
              },
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text('Data Portability', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Export your saved recipes as a backup file',
                    button: true,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload),
                      label: const Text('Export'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: widget.onExport,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    label: 'Import recipes from a backup file',
                    button: true,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Import'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _showImportDialog,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A screen that displays the user's scheduled meals in a calendar-like list.
///
/// Allows users to view recipe details, edit meals, scale portions,
/// and add ingredients to the shopping list.
class ScheduleScreen extends StatefulWidget {
  final List<Recipe> mealPlans;
  final Function(Recipe) onBookmarkToggled;
  final Function(Recipe) onEdit;
  final Function(Recipe) onAddToCart;
  final Function(int) onDelete;
  final double fontSize;
  final Function(String) onSpeak;
  final String? currentlySpeakingText;

  const ScheduleScreen(
      {super.key,
        required this.mealPlans,
        required this.onBookmarkToggled,
        required this.onEdit,
        required this.onAddToCart,
        required this.onDelete,
        required this.fontSize,
        required this.onSpeak,
        this.currentlySpeakingText});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int _servingSize = 4;

  /// Scales ingredient quantities based on the selected serving size.
  List<String> _scaleIngredients(List<String> ingredients, int size) {
    return ingredients.map((i) {
      return i.replaceAllMapped(RegExp(r'(\d+(\.\d+)?)'), (match) {
        double val = double.parse(match.group(1)!);
        double scaled = (val / 4) * size;
        return scaled % 1 == 0 ? scaled.toInt().toString() : scaled.toStringAsFixed(1);
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final sorted = List<Recipe>.from(widget.mealPlans)..sort((a, b) => a.date.compareTo(b.date));
    final currentPlans = sorted.where((p) => !DateTime(p.date.year, p.date.month, p.date.day).isBefore(today)).toList();

    if (currentPlans.isEmpty) {
      return const Center(
          child: Text('Plan your first meal with the + button', style: TextStyle(fontSize: 18, color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: currentPlans.length,
      itemBuilder: (context, index) {
        final plan = currentPlans[index];
        final originalIndex = widget.mealPlans.indexOf(plan);
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFFFCC99),
              child: Icon(_getMealIcon(plan.mealType), color: const Color(0xFF064E40)),
            ),
            title: Text(plan.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.fontSize)),
            subtitle: Text("${plan.mealType} • ${_formatDate(plan.date)}"),
            trailing: IconButton(
              icon: const Icon(Icons.add_shopping_cart, color: Color(0xFF064E40)),
              onPressed: () => widget.onAddToCart(plan),
              tooltip: 'Add to shopping list',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => widget.onEdit(plan),
                          tooltip: 'Edit meal',
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        ),
                        AnimatedBookmarkButton(
                          isBookmarked: plan.isBookmarked,
                          onTap: () => widget.onBookmarkToggled(plan),
                        ),
                        if (plan.link.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.link),
                            onPressed: () => launchUrl(Uri.parse(plan.link)),
                            tooltip: 'Open link',
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => widget.onDelete(originalIndex),
                          tooltip: 'Delete meal',
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      children: [
                        const Text("Servings: ", style: TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => _servingSize > 1 ? _servingSize-- : null), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
                        Text('$_servingSize'),
                        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _servingSize++), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("Ingredients", style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.fontSize)),
                    const SizedBox(height: 4),
                    ..._scaleIngredients(plan.ingredients, _servingSize).map((i) => Text("• $i", style: TextStyle(fontSize: widget.fontSize))),
                    const SizedBox(height: 12),
                    Text("Instructions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.fontSize)),
                    const SizedBox(height: 4),
                    ...plan.instructions.asMap().entries.map((e) => MergeSemantics(
                      child: Row(
                        children: [
                          Expanded(child: Text("${e.key + 1}. ${e.value}", style: TextStyle(fontSize: widget.fontSize, height: 1.5))),
                          IconButton(
                            icon: Icon(
                                widget.currentlySpeakingText == e.value
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                                color: const Color(0xFF064E40)),
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            onPressed: () => widget.onSpeak(e.value),
                            tooltip: widget.currentlySpeakingText == e.value ? 'Stop reading' : 'Read instruction aloud',
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getMealIcon(String type) {
    switch (type.toLowerCase()) {
      case 'breakfast': return Icons.wb_sunny;
      case 'lunch': return Icons.lunch_dining;
      case 'dinner': return Icons.restaurant;
      case 'snack': return Icons.cookie;
      case 'dessert': return Icons.cake;
      default: return Icons.flatware;
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return "Today";
    return "${d.month}/${d.day}";
  }
}

/// A screen for managing saved recipes in the user's cookbook.
///
/// Allows users to view bookmarked recipes, schedule them for future meals,
/// and scale ingredients for shopping.
class CookbookScreen extends StatefulWidget {
  final List<Recipe> cookbook;
  final Function(String) onRemove;
  final Function(Recipe) onSchedule;
  final Function(Recipe) onAddToCart;
  final double fontSize;
  final Function(String) onSpeak;
  final String? currentlySpeakingText;

  const CookbookScreen(
      {super.key,
        required this.cookbook,
        required this.onRemove,
        required this.onSchedule,
        required this.onAddToCart,
        required this.fontSize,
        required this.onSpeak,
        this.currentlySpeakingText});

  @override
  State<CookbookScreen> createState() => _CookbookScreenState();
}

class _CookbookScreenState extends State<CookbookScreen> {
  int _servingSize = 4;

  /// Scales ingredient quantities based on the selected serving size.
  List<String> _scaleIngredients(List<String> ingredients, int size) {
    return ingredients.map((i) {
      return i.replaceAllMapped(RegExp(r'(\d+(\.\d+)?)'), (match) {
        double val = double.parse(match.group(1)!);
        double scaled = (val / 4) * size;
        return scaled % 1 == 0 ? scaled.toInt().toString() : scaled.toStringAsFixed(1);
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cookbook.isEmpty) {
      return const Center(
          child: Text('Your saved recipes appear here', style: TextStyle(fontSize: 18, color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: widget.cookbook.length,
      itemBuilder: (context, index) {
        final recipe = widget.cookbook[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ExpansionTile(
            leading: const Icon(Icons.book, color: Colors.orange),
            title: Text(recipe.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.fontSize)),
            trailing: IconButton(
              icon: const Icon(Icons.add_shopping_cart, color: Color(0xFF064E40)),
              onPressed: () => widget.onAddToCart(recipe),
              tooltip: 'Add ingredients to shopping list',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ElevatedButton.icon(
                            onPressed: () => widget.onSchedule(recipe),
                            icon: const Icon(Icons.calendar_today),
                            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                            label: const Text("Plan Now")),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => widget.onRemove(recipe.title),
                          tooltip: 'Remove from cookbook',
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      children: [
                        const Text("Servings: ", style: TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => _servingSize > 1 ? _servingSize-- : null), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
                        Text('$_servingSize'),
                        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => _servingSize++), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("Ingredients", style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.fontSize)),
                    ..._scaleIngredients(recipe.ingredients, _servingSize).map((i) => Text("• $i", style: TextStyle(fontSize: widget.fontSize))),
                    const SizedBox(height: 12),
                    Text("Instructions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.fontSize)),
                    const SizedBox(height: 4),
                    ...recipe.instructions.asMap().entries.map((e) => MergeSemantics(
                      child: Row(
                        children: [
                          Expanded(child: Text("${e.key + 1}. ${e.value}", style: TextStyle(fontSize: widget.fontSize, height: 1.5))),
                          IconButton(
                            icon: Icon(
                                widget.currentlySpeakingText == e.value
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                                color: const Color(0xFF064E40)),
                            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                            onPressed: () => widget.onSpeak(e.value),
                            tooltip: widget.currentlySpeakingText == e.value ? 'Stop reading' : 'Read instruction aloud',
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A screen that manages the user's shopping list with automatic categorization.
///
/// Supports manual entry, standard staples, and frequent purchase suggestions.
/// Categorizes items into aisles like Produce, Dairy, and Meat for efficient shopping.
class GroceryListScreen extends StatefulWidget {
  final List<String> groceryList;
  final Function(String) onRemove;
  final Function(String, String) onUpdate;
  final Function(String) onAddManual;
  final VoidCallback onClearAll;
  final VoidCallback onAddStaples;
  final VoidCallback onLongPressAddStaples;
  final bool isCompactView;
  final bool showFrequentlyBought;
  final List<String> frequentSuggestions;
  final double fontSize;
  final List<String> categoryOrder;

  const GroceryListScreen(
      {super.key,
        required this.groceryList,
        required this.onRemove,
        required this.onUpdate,
        required this.onAddManual,
        required this.onClearAll,
        required this.onAddStaples,
        required this.onLongPressAddStaples,
        required this.isCompactView,
        required this.showFrequentlyBought,
        required this.frequentSuggestions,
        required this.fontSize,
        required this.categoryOrder});

  @override
  State<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends State<GroceryListScreen> {
  final TextEditingController _manualController = TextEditingController();
  final Set<String> _checkedItems = {};

  /// Determines the category of a grocery item based on its name.
  String _getCategory(String item) {
    final lowerItem = item.toLowerCase();

    const produce = ['onion', 'garlic', 'apple', 'banana', 'carrot', 'lettuce', 'tomato', 'potato', 'pepper', 'spinach', 'broccoli', 'lemon', 'lime', 'berry', 'cucumber', 'ginger', 'cilantro', 'parsley', 'herb', 'zucchini', 'cabbage'];
    const dairy = ['milk', 'cheese', 'butter', 'yogurt', 'cream', 'egg', 'sour cream', 'parmesan', 'mozzarella', 'cheddar'];
    const meat = ['chicken', 'beef', 'pork', 'steak', 'ground', 'turkey', 'bacon', 'sausage', 'salmon', 'shrimp', 'fish', 'lamb'];
    const pantry = ['flour', 'sugar', 'oil', 'salt', 'pepper', 'pasta', 'rice', 'bean', 'canned', 'broth', 'stock', 'vinegar', 'honey', 'spice', 'powder', 'sauce', 'bread', 'tortilla', 'cracker', 'chip'];

    if (produce.any((k) => lowerItem.contains(k))) return 'Produce';
    if (dairy.any((k) => lowerItem.contains(k))) return 'Dairy & Eggs';
    if (meat.any((k) => lowerItem.contains(k))) return 'Meat & Seafood';
    if (pantry.any((k) => lowerItem.contains(k))) return 'Pantry';

    return 'Other';
  }

  void _shareList() {
    if (widget.groceryList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your list is empty!')));
      return;
    }

    String listText = "🛒 Dinner Duck Grocery List:\n\n";

    if (widget.isCompactView) {
      listText += widget.groceryList.map((i) => "• $i").join("\n");
    } else {
      Map<String, List<String>> categorized = {
        'Produce': [],
        'Dairy & Eggs': [],
        'Meat & Seafood': [],
        'Pantry': [],
        'Other': [],
      };

      for (var item in widget.groceryList) {
        categorized[_getCategory(item)]!.add(item);
      }

      for (var category in widget.categoryOrder) {
        if (categorized[category] != null && categorized[category]!.isNotEmpty) {
          listText += "[$category]\n";
          listText += categorized[category]!.map((i) => "• $i").join("\n");
          listText += "\n\n";
        }
      }
    }

    Share.share(listText.trim(), subject: 'Grocery List from Dinner Duck');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCompactView) {
      return Column(
        children: [
          _buildHeader(),
          Expanded(
            child: widget.groceryList.isEmpty
                ? const Center(child: Text('Your list is empty', style: TextStyle(fontSize: 18, color: Colors.grey)))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.groceryList.length,
              itemBuilder: (context, index) {
                final item = widget.groceryList[index];
                return _buildItem(item);
              },
            ),
          ),
        ],
      );
    }

    Map<String, List<String>> categorized = {
      'Produce': [],
      'Dairy & Eggs': [],
      'Meat & Seafood': [],
      'Pantry': [],
      'Other': [],
    };

    for (var item in widget.groceryList) {
      categorized[_getCategory(item)]!.add(item);
    }

    final categories = widget.categoryOrder.where((c) => categorized[c] != null && categorized[c]!.isNotEmpty).toList();

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: widget.groceryList.isEmpty
              ? const Center(child: Text('Your list is empty', style: TextStyle(fontSize: 18, color: Colors.grey)))
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            itemBuilder: (context, catIdx) {
              final category = categories[catIdx];
              final items = categorized[category]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFCC99).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(category,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF064E40))),
                  ),
                  ...items.map((item) => _buildItem(item)),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showFrequentlyBought && widget.frequentSuggestions.isNotEmpty)
            Semantics(
              label: 'Frequently purchased suggestions',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: widget.frequentSuggestions.map((item) => Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: ActionChip(
                        backgroundColor: const Color(0xFFFFCC99),
                        label: Text(item, style: const TextStyle(color: Color(0xFF064E40), fontWeight: FontWeight.bold)),
                        onPressed: () => widget.onAddManual(item),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ),
          TextField(
            controller: _manualController,
            decoration: InputDecoration(
              hintText: 'Add item (e.g. Paper Towels)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF064E40)),
                onPressed: () {
                  if (_manualController.text.trim().isNotEmpty) {
                    widget.onAddManual(_manualController.text.trim());
                    _manualController.clear();
                  }
                },
                tooltip: 'Add manual item',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) {
                widget.onAddManual(val.trim());
                _manualController.clear();
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${widget.groceryList.length} Items",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Semantics(
                      label: 'Add standard pantry items to your list',
                      button: true,
                      child: Row(
                        children: [
                          GestureDetector(
                            onLongPress: widget.onLongPressAddStaples,
                            child: TextButton.icon(
                              onPressed: widget.onAddStaples,
                              icon: const Icon(Icons.auto_awesome, size: 18),
                              label: const Text('Staples', style: TextStyle(fontSize: 14)),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 48),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _shareList,
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('Share', style: TextStyle(fontSize: 14)),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Clear the entire shopping list',
                button: true,
                child: TextButton.icon(
                  onPressed: () {
                    if (widget.groceryList.isNotEmpty) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear List?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                              child: const Text('No'),
                            ),
                            TextButton(
                                onPressed: () {
                                  setState(() => _checkedItems.clear());
                                  widget.onClearAll();
                                  Navigator.pop(ctx);
                                },
                                style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                                child: const Text('Yes, Clear All', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_sweep, color: Colors.red),
                  label: const Text('Clear All', style: TextStyle(color: Colors.red)),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditDialog(String item) {
    final controller = TextEditingController(text: item);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Item'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              widget.onUpdate(item, val.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                widget.onUpdate(item, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(String item) {
    final bool isChecked = _checkedItems.contains(item);
    return Dismissible(
      key: Key(item),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        setState(() {
          _checkedItems.remove(item);
        });
        widget.onRemove(item);
      },
      child: Semantics(
        label: 'Grocery item: $item. ${isChecked ? "Checked" : "Unchecked"}. Tap checkbox to toggle. Long press to edit.',
        child: InkWell(
          onLongPress: () => _showEditDialog(item),
          child: CheckboxListTile(
            title: Text(
              item,
              style: TextStyle(
                fontSize: widget.fontSize,
                decoration: isChecked ? TextDecoration.lineThrough : null,
                color: isChecked ? Colors.grey : null,
              ),
            ),
            value: isChecked,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _checkedItems.add(item);
                } else {
                  _checkedItems.remove(item);
                }
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ),
    );
  }
}
