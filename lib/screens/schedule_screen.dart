import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recipe.dart';
import '../widgets/animated_bookmark_button.dart';

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

class _ScheduleScreenState extends State<ScheduleScreen> with AutomaticKeepAliveClientMixin {
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
