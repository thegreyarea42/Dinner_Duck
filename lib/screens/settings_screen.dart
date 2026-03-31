import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _staples = List<String>.from(widget.staples);
    _categoryOrder = List<String>.from(widget.categoryOrder);
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
                      fillColor: Theme.of(context).primaryColor.withValues(alpha: 0.05),
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
                  color: Colors.white.withValues(alpha: 0.8),
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
