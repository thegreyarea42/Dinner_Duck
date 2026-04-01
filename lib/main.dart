/// Dinner Duck - A Flutter application for meal planning, recipe management, and grocery listing.
///
/// This file contains the main entry point and all the core UI components and logic
/// for the Dinner Duck app, including meal scheduling, a personal cookbook,
/// and an automated grocery list generator.
library;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:dinner_duck/models/recipe.dart';
import 'package:dinner_duck/screens/settings_screen.dart';
import 'package:dinner_duck/screens/schedule_screen.dart';
import 'package:dinner_duck/screens/cookbook_screen.dart';
import 'package:dinner_duck/screens/grocery_list_screen.dart';
import 'package:dinner_duck/services/persistence_service.dart';
import 'package:dinner_duck/services/recipe_service.dart';
import 'package:dinner_duck/screens/quack_center_screen.dart';
import 'package:dinner_duck/services/quack_service.dart';

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
  List<String> _checkedItems = [];
  int _selectedIndex = 0;

  // Settings
  late double _fontSize;
  late bool _isDarkMode;
  bool _keepScreenOn = false;
  bool _isCompactView = false;
  bool _showFrequentlyBought = true;
  double _speechRate = 0.5;
  String _quackCode = '0000';
  String? _currentlySpeakingText;
  late PageController _pageController;
  Timer? _heartbeatTimer;
  int _lastModifiedTimestamp = 0;
  int _lastSyncedTimestamp = 0;

  final FlutterTts _flutterTts = FlutterTts();
  final PersistenceService _persistenceService = PersistenceService();
  final QuackService _quackService = QuackService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fontSize = widget.initialFontSize;
    _isDarkMode = widget.initialIsDarkMode;
    _selectedIndex = 0; // Ensure starts at 0
    // Start at a high multiple of 3 for infinite swiping
    _pageController = PageController(initialPage: 3000);
    _loadData();
    
    // Listen for Quack Service status changes
    _quackService.statusStream.listen((status) {
      if (mounted) setState(() {});
    });

    _quackService.timerStream.listen((remainingSeconds) {
       if (mounted) setState(() {});
    });

    _startHeartbeat();

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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_quackService.isLiveExcellent && _lastModifiedTimestamp > _lastSyncedTimestamp) {
        debugPrint('Heartbeat: Pushing bread...');
        _pushBread();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    WakelockPlus.disable();
    _flutterTts.stop();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      WakelockPlus.disable();
      _quackService.stopQuacking();
    } else if (state == AppLifecycleState.resumed) {
      _updateWakelock();
      _quackService.startQuacking(
        quackCode: _quackCode,
        onDataReceived: _syncData,
        onSyncExcellent: () {},
        onDeviceFound: (host, port, name) {},
      );
    }
  }

  /// Loads all application data (meal plans, cookbook, etc.) from local storage.
  Future<void> _loadData() async {
    final data = await _persistenceService.loadAllData();
    
    setState(() {
      _mealPlans = data['mealPlans'];
      _cookbook = data['cookbook'];
      _groceryList = (data['groceryList'] as List<String>)
          .map((e) => RecipeService.cleanIngredientName(e))
          .where((e) => e.isNotEmpty)
          .toList();
      _staples = data['staples'];
      _categoryOrder = data['categoryOrder'];
      _purchaseHistory = data['purchaseHistory'];
      _checkedItems = data['checkedItems'] ?? [];
      
      _keepScreenOn = data['keepScreenOn'];
      _quackCode = data['quackCode'] ?? '0000';
    });
    _updateWakelock();
  }

  /// Persists all current application data to local storage.
  Future<void> _saveData() async {
    _lastModifiedTimestamp = DateTime.now().millisecondsSinceEpoch;
    await _saveDataInternal();
  }

  void _pushBread() {
    if (!_quackService.isLiveExcellent) return;
    _lastSyncedTimestamp = _lastModifiedTimestamp;
    _quackService.pushBread({
      'mealPlans': _mealPlans,
      'cookbook': _cookbook,
      'groceryList': _groceryList,
      'staples': _staples,
      'categoryOrder': _categoryOrder,
      'purchaseHistory': _purchaseHistory,
      'checkedItems': _checkedItems,
    });
  }

  /// Saves user settings and notifies the parent widget of changes.
  Future<void> _saveSettings() async {
    await _persistenceService.saveSettings(
      fontSize: _fontSize,
      isDarkMode: _isDarkMode,
      keepScreenOn: _keepScreenOn,
      isCompactView: _isCompactView,
      showFrequentlyBought: _showFrequentlyBought,
      speechRate: _speechRate,
    );
    widget.onSettingsChanged(_isDarkMode, _fontSize);
    _updateWakelock();
  }

  /// Toggles the device's wakelock based on current screen and settings.
  void _updateWakelock() {
    bool shouldBeOn = _keepScreenOn && (_selectedIndex == 0 || _selectedIndex == 1);
    WakelockPlus.toggle(enable: shouldBeOn);
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
    if (index < 0 || index >= _mealPlans.length) return;
    final deletedRecipe = _mealPlans[index];
    setState(() {
      _mealPlans.removeAt(index);
      _saveData();
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${deletedRecipe.title}" removed from planner.'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            setState(() {
              _mealPlans.insert(index, deletedRecipe);
              _saveData();
            });
          },
        ),
      ),
    );
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
    final recipeIdx = _cookbook.indexWhere((r) => r.title == title);
    if (recipeIdx == -1) return;
    final removedRecipe = _cookbook[recipeIdx];
    
    setState(() {
      _cookbook.removeAt(recipeIdx);
      for (var p in _mealPlans) {
        if (p.title == title) p.isBookmarked = false;
      }
      _saveData();
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${removedRecipe.title}" removed from cookbook.'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            setState(() {
              _cookbook.insert(recipeIdx, removedRecipe);
              for (var p in _mealPlans) {
                if (p.title == title) p.isBookmarked = true;
              }
              _saveData();
            });
          },
        ),
      ),
    );
  }

  void _toggleBookmark(Recipe recipe) {
    bool wasBookmarked = recipe.isBookmarked;
    int? removedCookbookIdx;
    Recipe? removedRecipe;

    if (wasBookmarked) {
      removedCookbookIdx = _cookbook.indexWhere((r) => r.title == recipe.title);
      if (removedCookbookIdx != -1) {
        removedRecipe = _cookbook[removedCookbookIdx];
      }
    }

    setState(() {
      recipe.isBookmarked = !recipe.isBookmarked;
      if (recipe.isBookmarked) {
        if (!_cookbook.any((r) => r.title == recipe.title)) {
          _cookbook.add(recipe);
        }
      } else {
        if (removedCookbookIdx != null && removedCookbookIdx != -1) {
          _cookbook.removeAt(removedCookbookIdx);
        } else {
          _cookbook.removeWhere((r) => r.title == recipe.title);
        }
      }
      _saveData();
    });

    if (wasBookmarked) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${recipe.title}" from cookbook.'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              setState(() {
                recipe.isBookmarked = true;
                if (removedRecipe != null && removedCookbookIdx != null && removedCookbookIdx != -1) {
                  _cookbook.insert(removedCookbookIdx, removedRecipe);
                } else if (!_cookbook.any((r) => r.title == recipe.title)) {
                  _cookbook.add(recipe);
                }
                _saveData();
              });
            },
          ),
        ),
      );
    }
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
        String cleaned = RecipeService.cleanIngredientName(item);
        if (cleaned.isNotEmpty) {
          currentItems.add(cleaned);
        }
      }
      _groceryList = currentItems.toList();
      _saveData();
    });
  }

  void _removeFromGroceryList(String item) {
    final int oldIndex = _groceryList.indexOf(item);
    if (oldIndex == -1) return;
    
    setState(() {
      _groceryList.remove(item);
      _purchaseHistory[item] = (_purchaseHistory[item] ?? 0) + 1;
      _saveData();
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "$item" from list.'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            setState(() {
              _groceryList.insert(oldIndex, item);
              if (_purchaseHistory[item] != null && _purchaseHistory[item]! > 0) {
                _purchaseHistory[item] = _purchaseHistory[item]! - 1;
              }
              _saveData();
            });
          },
        ),
      ),
    );
  }

  void _updateGroceryItem(String oldItem, String newItem) {
    setState(() {
      int index = _groceryList.indexOf(oldItem);
      if (index != -1) {
        String cleaned = RecipeService.cleanIngredientName(newItem);
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

  void _syncData(Map<String, dynamic> data) {
    setState(() {
      // 1. Merge Cookbook (unique by title)
      final remoteCookbook = List<Recipe>.from((data['cookbook'] as List).map((x) => Recipe.fromJson(x)));
      final Map<String, Recipe> cookbookMap = { for (var r in _cookbook) r.title: r };
      for (var r in remoteCookbook) {
        if (!cookbookMap.containsKey(r.title)) cookbookMap[r.title] = r;
      }
      _cookbook = cookbookMap.values.toList();

      // 2. Merge Planner (unique by composite: title_date_mealType)
      final remoteMealPlans = List<Recipe>.from((data['mealPlans'] as List).map((x) => Recipe.fromJson(x)));
      final Map<String, Recipe> mealPlanMap = {
        for (var r in _mealPlans) '${r.title}_${r.date.toIso8601String()}_${r.mealType}': r
      };
      for (var r in remoteMealPlans) {
        final key = '${r.title}_${r.date.toIso8601String()}_${r.mealType}';
        if (!mealPlanMap.containsKey(key)) mealPlanMap[key] = r;
      }
      _mealPlans = mealPlanMap.values.toList();
      _mealPlans.sort((a, b) => a.date.compareTo(b.date)); // Keep schedule sorted chronologically

      // 3. Merge Grocery Lists & Checked Items
      final remoteGrocery = List<String>.from(data['groceryList'] ?? []);
      _groceryList = (_groceryList.toSet()..addAll(remoteGrocery)).toList();

      final remoteChecked = List<String>.from(data['checkedItems'] ?? []);
      _checkedItems = (_checkedItems.toSet()..addAll(remoteChecked)).toList();

      // 4. Merge Staples & Category Order
      final remoteStaples = List<String>.from(data['staples'] ?? []);
      _staples = (_staples.toSet()..addAll(remoteStaples)).toList();

      final remoteCategoryOrder = List<String>.from(data['categoryOrder'] ?? []);
      _categoryOrder = (_categoryOrder.toSet()..addAll(remoteCategoryOrder)).toList();

      // 5. Merge Purchase History (keep the highest purchase count)
      final remotePurchaseHistory = Map<String, int>.from(data['purchaseHistory'] ?? {});
      for (var entry in remotePurchaseHistory.entries) {
        int current = _purchaseHistory[entry.key] ?? 0;
        _purchaseHistory[entry.key] = current > entry.value ? current : entry.value;
      }
      
      // Save without pushing back to avoid bread loops
      _saveDataInternal();
      _lastSyncedTimestamp = _lastModifiedTimestamp; // Avoid immediate re-push
    });
  }

  Future<void> _saveDataInternal() async {
    await _persistenceService.saveData(
      mealPlans: _mealPlans,
      cookbook: _cookbook,
      groceryList: _groceryList,
      staples: _staples,
      categoryOrder: _categoryOrder,
      purchaseHistory: _purchaseHistory,
      checkedItems: _checkedItems,
    );
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
            String json = _persistenceService.exportCookbook(_cookbook);
            Share.share(json, subject: 'My Dinner Duck Cookbook');
          },
          onImport: (jsonStr) {
            try {
              final imported = _persistenceService.importCookbook(jsonStr);
              
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
              setModalState(() => isLoading = true);
              try {
                final result = await RecipeService.scrapeRecipe(linkController.text);
                setModalState(() {
                  titleController.text = result['title'];
                  ingredientsController.text = result['ingredients'].join('\n');
                  instructionsController.text = result['instructions'].join('\n');
                  linkController.text = result['link'];
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Details captured!')));
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
            String json = _persistenceService.exportCookbook(_cookbook);
            Share.share(json, subject: 'My Dinner Duck Cookbook');
          },
          onImport: (jsonStr) {
            try {
              final imported = _persistenceService.importCookbook(jsonStr);
              
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
        actions: [
          if (_quackService.isLiveExcellent)
            _PulsingDuckIcon(timerStream: _quackService.timerStream),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuackCenterScreen(
                    quackCode: _quackCode,
                    onQuackCodeChanged: (newCode) {
                      setState(() => _quackCode = newCode);
                      _persistenceService.saveSettings(
                        fontSize: _fontSize,
                        isDarkMode: _isDarkMode,
                        keepScreenOn: _keepScreenOn,
                        isCompactView: _isCompactView,
                        showFrequentlyBought: _showFrequentlyBought,
                        speechRate: _speechRate,
                        quackCode: newCode,
                      );
                    },
                    onDataReceived: _syncData,
                  ),
                ),
              );
            },
            tooltip: 'Sync (Quack)',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettings(),
            tooltip: 'Settings',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index % 3;
            _updateWakelock();
          });
        },
        itemBuilder: (context, index) {
          final realIndex = index % 3;
          switch (realIndex) {
            case 0:
              return ScheduleScreen(
                mealPlans: _mealPlans,
                onBookmarkToggled: _toggleBookmark,
                onEdit: (r) => _showRecipeDialog(existingRecipe: r, index: _mealPlans.indexOf(r)),
                onAddToCart: _showAddToCartDialog,
                onDelete: (index) => _deleteFromPlanner(index),
                fontSize: _fontSize,
                onSpeak: _speak,
                currentlySpeakingText: _currentlySpeakingText,
              );
            case 1:
              return CookbookScreen(
                cookbook: _cookbook,
                onRemove: _removeFromCookbook,
                onSchedule: (r) => _showRecipeDialog(existingRecipe: r, isSchedulingFromCookbook: true),
                onAddToCart: _showAddToCartDialog,
                fontSize: _fontSize,
                onSpeak: _speak,
                currentlySpeakingText: _currentlySpeakingText,
              );
            case 2:
              return GroceryListScreen(
                groceryList: _groceryList,
                checkedItems: _checkedItems,
                onRemove: _removeFromGroceryList,
                onUpdate: _updateGroceryItem,
                onAddManual: (item) => _addToGroceryList([item]),
                onClearAll: _clearGroceryList,
                onAddStaples: _addStaplesToGroceries,
                onLongPressAddStaples: _showSettingsAndManageStaples,
                onCheckToggled: (item, isChecked) {
                  setState(() {
                    if (isChecked) {
                      _checkedItems.add(item);
                    } else {
                      _checkedItems.remove(item);
                    }
                    _saveData();
                  });
                },
                isCompactView: _isCompactView,
                showFrequentlyBought: _showFrequentlyBought,
                frequentSuggestions: _topFrequentSuggestions,
                fontSize: _fontSize,
                categoryOrder: _categoryOrder,
              );
            default:
              return Container();
          }
        },
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
          // Current absolute index in the infinite list
          final currentAbsoluteIndex = _pageController.page?.round() ?? 3000;
          // Calculate the nearest target index based on the modulo
          final currentModuloIndex = currentAbsoluteIndex % 3;
          int targetAbsoluteIndex;
          
          if (i > currentModuloIndex) {
            targetAbsoluteIndex = currentAbsoluteIndex + (i - currentModuloIndex);
          } else if (i < currentModuloIndex) {
            targetAbsoluteIndex = currentAbsoluteIndex - (currentModuloIndex - i);
          } else {
            targetAbsoluteIndex = currentAbsoluteIndex;
          }

          _pageController.animateToPage(
            targetAbsoluteIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
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

class _PulsingDuckIcon extends StatefulWidget {
  final Stream<int> timerStream;
  const _PulsingDuckIcon({required this.timerStream});

  @override
  State<_PulsingDuckIcon> createState() => _PulsingDuckIconState();
}

class _PulsingDuckIconState extends State<_PulsingDuckIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: widget.timerStream,
      builder: (context, snapshot) {
        final totalSeconds = snapshot.data ?? 0;
        final minutes = totalSeconds ~/ 60;
        final seconds = totalSeconds % 60;
        final timerText = "$minutes:${seconds.toString().padLeft(2, '0')}";

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.2).animate(_controller),
              child: const Icon(Icons.flutter_dash, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 4),
            Text(
              timerText,
              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 8),
          ],
        );
      },
    );
  }
}
