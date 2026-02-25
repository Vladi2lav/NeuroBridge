import 'package:flutter/material.dart';

class MultiSelectDropdown extends StatefulWidget {
  final List<String> items;
  final List<String> selectedItems;
  final Function(List<String>) onChanged;

  const MultiSelectDropdown({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.onChanged,
  });

  @override
  State<MultiSelectDropdown> createState() => _MultiSelectDropdownState();
}

class _MultiSelectDropdownState extends State<MultiSelectDropdown> with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Use Curves.easeOutCubic for a snappy unfolding effect
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _onItemTapped(String item) {
    List<String> newSelection = List.from(widget.selectedItems);
    
    if (item == 'Нет нарушений') {
      newSelection.clear();
      newSelection.add('Нет нарушений');
    } else {
      newSelection.remove('Нет нарушений');
      if (newSelection.contains(item)) {
        newSelection.remove(item);
      } else {
        newSelection.add(item);
      }
      
      if (newSelection.isEmpty) {
        newSelection.add('Нет нарушений');
      }
    }
    
    widget.onChanged(newSelection);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggleDropdown,
          borderRadius: BorderRadius.circular(12),
          child: Container(
             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
             decoration: BoxDecoration(
               border: Border.all(color: Theme.of(context).colorScheme.outline),
               borderRadius: BorderRadius.circular(12),
               color: Theme.of(context).colorScheme.surface,
             ),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Expanded(
                   child: Text(
                     widget.selectedItems.isEmpty ? 'Выберите профиль' : widget.selectedItems.join(', '),
                     overflow: TextOverflow.ellipsis,
                     style: const TextStyle(fontSize: 16),
                   ),
                 ),
                 AnimatedRotation(
                   turns: _isOpen ? 0.5 : 0.0,
                   duration: const Duration(milliseconds: 300),
                   child: const Icon(Icons.keyboard_arrow_down),
                 ),
               ],
             ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1.0, // Animates scaling starting from the top and growing downwards
          child: Container(
             margin: const EdgeInsets.only(top: 8),
             decoration: BoxDecoration(
               border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
               borderRadius: BorderRadius.circular(12),
               color: Theme.of(context).colorScheme.surface,
               boxShadow: [
                 BoxShadow(
                   color: Colors.black.withOpacity(0.05),
                   blurRadius: 10,
                   offset: const Offset(0, 4),
                 )
               ]
             ),
             // Constrain height if items are too many
             constraints: const BoxConstraints(maxHeight: 250),
             child: ClipRRect(
               borderRadius: BorderRadius.circular(12),
               child: ListView(
                 shrinkWrap: true,
                 padding: EdgeInsets.zero,
                 children: widget.items.map((item) {
                   final isSelected = widget.selectedItems.contains(item);
                   return CheckboxListTile(
                     title: Text(item, style: const TextStyle(fontSize: 15)),
                     value: isSelected,
                     onChanged: (bool? value) {
                       _onItemTapped(item);
                     },
                     controlAffinity: ListTileControlAffinity.leading,
                     activeColor: Theme.of(context).colorScheme.primary,
                     contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                     dense: true,
                   );
                 }).toList(),
               ),
             ),
          ),
        ),
      ],
    );
  }
}
