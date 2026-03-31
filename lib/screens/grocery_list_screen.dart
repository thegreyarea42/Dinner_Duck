import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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
  final double fontSize;
  final bool isCompactView;
  final bool showFrequentlyBought;
  final List<String> frequentSuggestions;
  final List<String> categoryOrder;

  const GroceryListScreen({
    super.key,
    required this.groceryList,
    required this.onRemove,
    required this.onUpdate,
    required this.onClearAll,
    required this.onAddStaples,
    required this.onLongPressAddStaples,
    required this.fontSize,
    required this.isCompactView,
    required this.showFrequentlyBought,
    required this.frequentSuggestions,
    required this.onAddManual,
    required this.categoryOrder,
  });

  @override
  State<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends State<GroceryListScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Set<String> _checkedItems = {};
  final TextEditingController _manualController = TextEditingController();
  bool _isStoreLayout = true;

  Future<void> _shareList() async {
    if (widget.groceryList.isEmpty) return;
    String listText = "🛒 Shopping List:\n\n${widget.groceryList.join('\n')}";
    await Share.share(listText, subject: 'My Shopping List');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final displayItems = List<String>.from(widget.groceryList);
    if (!_isStoreLayout) {
      displayItems.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return Column(
        children: [
          _buildHeader(),
          Expanded(
            child: displayItems.isEmpty
                ? const Center(child: Text('Your list is empty', style: TextStyle(fontSize: 18, color: Colors.grey)))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: displayItems.length,
              itemBuilder: (context, index) {
                final item = displayItems[index];
                return _buildItem(item);
              },
            ),
          ),
        ],
      );
    }

    Map<String, List<String>> categorized = {};
    for (var cat in widget.categoryOrder) {
      categorized[cat] = [];
    }

    final producePattern = RegExp(r'\b(apple|banana|berry|berries|lettuce|onion|tomato|carrot|garlic|ginger|spinach|kale|broccoli|potato|pepper|herb|cilantro|mint|pear|peach|grape|avocado|lime|lemon|orange|cucumber|cabbage|squash|zucchini|mushroom|celery|corn|pea|bean|radish|beet|asparagus|eggplant|cauliflower|leek|artichoke|sprout|basil|parsley|thyme|rosemary|sage|dill|chive|scallion|leek|shallot|endive|jicama|yam|sweet potato|turnip|parsnip|rutabaga|tuber|rhubarb|okra|tomatillo|grapefruit|melon|pineapple|mango|kiwi|pomegranate|fig|date|apricot|plum|cherry|olive|lettuce|arugula|watercress|radicchio|bok choy|chard|collard|mustard|dandelion|purslane|sorrel)\b', caseSensitive: false);
    final dairyPattern = RegExp(r'\b(milk|cheese|egg|butter|yogurt|cream|sour cream|mayo|half and half|alternative|parmesan|mozzarella|cheddar|feta|goat|brie|gouda|swiss|provolone|ricotta|mascarpone|kefir|margarine|shortening)\b', caseSensitive: false);
    final meatPattern = RegExp(r'\b(chicken|beef|pork|steak|bacon|sausage|fish|shrimp|salmon|turid|ham|turkey|lamb|duck|venison|bison|goat|rabbit|quail|pheasant|veal|chorizo|salami|pepperoni|prosciutto|pancetta|jerky|tuna|cod|tilapia|haddock|halibut|snapper|bass|trout|crab|lobster|oyster|mussel|clam|scallop|squid|octopus|prawn)\b', caseSensitive: false);
    final pantryPattern = RegExp(r'\b(flour|sugar|oil|vinegar|spice|salt|pepper|rice|pasta|sauce|broth|stock|cereal|oat|cracker|chip|nut|seed|dried|canned|honey|syrup|jam|jelly|peanut butter|nut butter|almond butter|cashew butter|maple|condiment|ketchup|mustard|mayo|relish|salsa|pickles|soy sauce|teriyaki|hoisin|oyster sauce|fish sauce|worcestershire|hot sauce|tahini|pesto|marinade|dressing|extract|baking|yeast|cocoa|chocolate|coffee|tea|juice|soda|water|wine|beer|liquor)\b', caseSensitive: false);

    for (var item in widget.groceryList) {
      String cat = 'Other';
      String val = item.toLowerCase();
      if (producePattern.hasMatch(val)) {
        cat = 'Produce';
      } else if (dairyPattern.hasMatch(val)) {
        cat = 'Dairy & Eggs';
      } else if (meatPattern.hasMatch(val)) {
        cat = 'Meat & Seafood';
      } else if (pantryPattern.hasMatch(val)) {
        cat = 'Pantry';
      }

      if (!categorized.containsKey(cat)) categorized[cat] = [];
      categorized[cat]!.add(item);
    }

    final categories = widget.categoryOrder.where((c) => categorized[c]!.isNotEmpty).toList();
    if (categorized['Other']!.isNotEmpty && !categories.contains('Other')) {
      categories.add('Other');
    }

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
                      color: const Color(0xFFFFCC99).withValues(alpha: 0.4),
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
                    Row(
                      children: [
                        DropdownButton<bool>(
                          value: _isStoreLayout,
                          icon: const Icon(Icons.sort, size: 18, color: Colors.blue),
                          underline: Container(),
                          onChanged: (val) => setState(() => _isStoreLayout = val!),
                          items: const [
                            DropdownMenuItem(value: true, child: Text('Store Layout', style: TextStyle(fontSize: 14))),
                            DropdownMenuItem(value: false, child: Text('Alphabetical', style: TextStyle(fontSize: 14))),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          label: 'Add standard pantry items to your list',
                          button: true,
                          child: GestureDetector(
                            onLongPress: widget.onLongPressAddStaples,
                            child: IconButton(
                              onPressed: widget.onAddStaples,
                              icon: const Icon(Icons.auto_awesome, size: 18, color: Colors.blue),
                              tooltip: 'Add Staples',
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _shareList,
                          icon: const Icon(Icons.share, size: 18, color: Colors.blue),
                          tooltip: 'Share List',
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        ),
                      ],
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
