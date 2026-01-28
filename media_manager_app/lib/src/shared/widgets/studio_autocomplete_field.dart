import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/studio.dart';
import '../../core/services/api_service.dart';

/// 制作商自动补全输入框
class StudioAutocompleteField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final InputDecoration? decoration;

  const StudioAutocompleteField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.onChanged,
    this.decoration,
  });

  @override
  ConsumerState<StudioAutocompleteField> createState() =>
      _StudioAutocompleteFieldState();
}

class _StudioAutocompleteFieldState
    extends ConsumerState<StudioAutocompleteField> {
  List<Studio> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<Studio>> _searchStudios(String query) async {
    if (query.isEmpty) return [];

    try {
      // TODO: 创建 StudioRepository 后使用 repository
      final apiService = ref.read(apiServiceProvider);
      return await apiService.searchStudios(query, limit: 10);
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Studio>(
      textEditingController: widget.controller,
      focusNode: FocusNode(),
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<Studio>.empty();
        }
        
        // 使用 Completer 来处理 debounce
        final completer = Completer<List<Studio>>();
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () async {
          final results = await _searchStudios(textEditingValue.text);
          if (!completer.isCompleted) {
            completer.complete(results);
          }
        });
        
        return await completer.future;
      },
      displayStringForOption: (Studio option) => option.name,
      onSelected: (Studio selection) {
        widget.controller.text = selection.name;
        widget.onChanged?.call(selection.name);
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController fieldController,
        FocusNode fieldFocusNode,
        VoidCallback onFieldSubmitted,
      ) {
        // 同步外部 controller 的值
        if (fieldController.text != widget.controller.text) {
          fieldController.text = widget.controller.text;
        }
        
        return TextFormField(
          controller: fieldController,
          focusNode: fieldFocusNode,
          decoration: widget.decoration ??
              InputDecoration(
                labelText: widget.labelText ?? '制作商',
                hintText: widget.hintText ?? '输入制作商名称',
                border: const OutlineInputBorder(),
              ),
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
          onChanged: (value) {
            widget.controller.text = value;
            widget.onChanged?.call(value);
          },
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<Studio> onSelected,
        Iterable<Studio> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final studio = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(studio.name),
                    subtitle: studio.mediaCount > 0
                        ? Text('${studio.mediaCount} 部作品',
                            style: Theme.of(context).textTheme.bodySmall)
                        : null,
                    onTap: () => onSelected(studio),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
