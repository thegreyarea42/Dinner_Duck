import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dinner_duck/models/recipe.dart';

class PersistenceService {
  static const String _mealPlansKey = 'mealPlans';
  static const String _cookbookKey = 'cookbook';
  static const String _groceryListKey = 'groceryList';
  static const String _staplesKey = 'staples';
  static const String _categoryOrderKey = 'categoryOrder';
  static const String _purchaseHistoryKey = 'purchaseHistory';
  static const String _fontSizeKey = 'fontSize';
  static const String _isDarkModeKey = 'isDarkMode';
  static const String _keepScreenOnKey = 'keepScreenOn';
  static const String _isCompactViewKey = 'isCompactView';
  static const String _showFrequentlyBoughtKey = 'showFrequentlyBought';
  static const String _speechRateKey = 'speechRate';

  Future<Map<String, dynamic>> loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final plannerJson = prefs.getString(_mealPlansKey);
    final cookbookJson = prefs.getString(_cookbookKey);
    final groceryJson = prefs.getString(_groceryListKey);
    final staplesJson = prefs.getString(_staplesKey);
    final orderJson = prefs.getString(_categoryOrderKey);
    final historyJson = prefs.getString(_purchaseHistoryKey);

    List<Recipe> mealPlans = [];
    if (plannerJson != null) {
      mealPlans = List<Recipe>.from(jsonDecode(plannerJson).map((x) => Recipe.fromJson(x)));
    }

    List<Recipe> cookbook = [];
    if (cookbookJson != null) {
      cookbook = List<Recipe>.from(jsonDecode(cookbookJson).map((x) => Recipe.fromJson(x)));
    }

    List<String> groceryList = [];
    if (groceryJson != null) {
      groceryList = List<String>.from(jsonDecode(groceryJson));
    }

    List<String> staples = [];
    if (staplesJson != null) {
      staples = List<String>.from(jsonDecode(staplesJson));
    }

    List<String> categoryOrder = ['Produce', 'Dairy & Eggs', 'Meat & Seafood', 'Pantry', 'Other'];
    if (orderJson != null) {
      categoryOrder = List<String>.from(jsonDecode(orderJson));
    }

    Map<String, int> purchaseHistory = {};
    if (historyJson != null) {
      purchaseHistory = Map<String, int>.from(jsonDecode(historyJson));
    }

    return {
      'mealPlans': mealPlans,
      'cookbook': cookbook,
      'groceryList': groceryList,
      'staples': staples,
      'categoryOrder': categoryOrder,
      'purchaseHistory': purchaseHistory,
      'fontSize': prefs.getDouble(_fontSizeKey) ?? 18.0,
      'isDarkMode': prefs.getBool(_isDarkModeKey) ?? false,
      'keepScreenOn': prefs.getBool(_keepScreenOnKey) ?? false,
      'isCompactView': prefs.getBool(_isCompactViewKey) ?? false,
      'showFrequentlyBought': prefs.getBool(_showFrequentlyBoughtKey) ?? true,
      'speechRate': prefs.getDouble(_speechRateKey) ?? 0.5,
    };
  }

  Future<void> saveData({
    required List<Recipe> mealPlans,
    required List<Recipe> cookbook,
    required List<String> groceryList,
    required List<String> staples,
    required List<String> categoryOrder,
    required Map<String, int> purchaseHistory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mealPlansKey, jsonEncode(mealPlans.map((x) => x.toJson()).toList()));
    await prefs.setString(_cookbookKey, jsonEncode(cookbook.map((x) => x.toJson()).toList()));
    await prefs.setString(_groceryListKey, jsonEncode(groceryList));
    await prefs.setString(_staplesKey, jsonEncode(staples));
    await prefs.setString(_categoryOrderKey, jsonEncode(categoryOrder));
    await prefs.setString(_purchaseHistoryKey, jsonEncode(purchaseHistory));
  }

  Future<void> saveSettings({
    required double fontSize,
    required bool isDarkMode,
    required bool keepScreenOn,
    required bool isCompactView,
    required bool showFrequentlyBought,
    required double speechRate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, fontSize);
    await prefs.setBool(_isDarkModeKey, isDarkMode);
    await prefs.setBool(_keepScreenOnKey, keepScreenOn);
    await prefs.setBool(_isCompactViewKey, isCompactView);
    await prefs.setBool(_showFrequentlyBoughtKey, showFrequentlyBought);
    await prefs.setDouble(_speechRateKey, speechRate);
  }

  String exportCookbook(List<Recipe> cookbook) {
    return jsonEncode(cookbook.map((e) => e.toJson()).toList());
  }

  List<Recipe> importCookbook(String jsonStr) {
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((x) => Recipe.fromJson(x)).toList();
  }
}
