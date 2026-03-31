import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recipe.dart';
import '../widgets/animated_bookmark_button.dart';

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

class _CookbookScreenState extends State<CookbookScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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
    super.build(context);
    if (widget.cookbook.isEmpty) {
      return const Center(child: Text('Your cookbook is empty', style: TextStyle(fontSize: 18, color: Colors.grey)));
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
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFCC99),
              child: Icon(Icons.menu_book, color: Color(0xFF064E40)),
            ),
            title: Text(recipe.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: widget.fontSize)),
            subtitle: Text(recipe.mealType),
            trailing: IconButton(
              icon: const Icon(Icons.add_shopping_cart, color: Color(0xFF064E40)),
              onPressed: () => widget.onAddToCart(recipe),
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
                          icon: const Icon(Icons.calendar_month, color: Colors.blue),
                          onPressed: () => widget.onSchedule(recipe),
                          tooltip: 'Schedule meal',
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        ),
                        AnimatedBookmarkButton(
                          isBookmarked: true,
                          onTap: () => widget.onRemove(recipe.title),
                        ),
                        if (recipe.link.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.link),
                            onPressed: () => launchUrl(Uri.parse(recipe.link)),
                            tooltip: 'Open link',
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
