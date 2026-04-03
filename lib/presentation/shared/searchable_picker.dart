import 'package:flutter/material.dart';

class SearchablePicker<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) itemLabel;
  final String Function(T)? itemSubtitle;
  final Widget Function(T)? leadingIcon;
  final VoidCallback onAddNew;
  final String addNewLabel;

  const SearchablePicker({
    super.key,
    required this.title,
    required this.items,
    required this.itemLabel,
    this.itemSubtitle,
    this.leadingIcon,
    required this.onAddNew,
    required this.addNewLabel,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required String Function(T) itemLabel,
    String Function(T)? itemSubtitle,
    Widget Function(T)? leadingIcon,
    required VoidCallback onAddNew,
    required String addNewLabel,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SearchablePicker<T>(
        title: title,
        items: items,
        itemLabel: itemLabel,
        itemSubtitle: itemSubtitle,
        leadingIcon: leadingIcon,
        onAddNew: onAddNew,
        addNewLabel: addNewLabel,
      ),
    );
  }

  @override
  State<SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<SearchablePicker<T>> {
  String _searchQuery = '';
  late TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.items.where((item) {
      final label = widget.itemLabel(item).toLowerCase();
      final sub = widget.itemSubtitle?.call(item).toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return label.contains(query) || sub.contains(query);
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Pull handle indicator
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: filteredItems.length + 1, // +1 for Add New
                  itemBuilder: (context, index) {
                    if (index == filteredItems.length) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                        title: Text(
                          widget.addNewLabel,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () {
                          // Note: closing the Modal first so it doesn't stay open under the new dialog
                          Navigator.pop(context);
                          widget.onAddNew();
                        },
                      );
                    }

                    final item = filteredItems[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                      leading: widget.leadingIcon?.call(item),
                      title: Text(widget.itemLabel(item), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: widget.itemSubtitle != null ? Text(widget.itemSubtitle!(item)) : null,
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
