import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/studio.dart';
import '../../core/services/api_service.dart';

/// 系列自动补全输入框
class SeriesAutocompleteField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final String? studioId;
  final String? labelText;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final InputDecoration? decoration;

  const SeriesAutocompleteField({
    super.key,
    required this.controller,
    this.studioId,
    this.labelText,
    this.hintText,
    this.onChanged,
    this.decoration,
  });

  @override
  ConsumerState<SeriesAutocompleteField> createState() =>
      _SeriesAutocompleteFieldState();
}

class _SeriesAutocompleteFieldState
    extends ConsumerState<SeriesAutocompleteField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<SeriesWithStudio>> _searchSeries(String query) async {
    if (query.isEmpty) return [];

    try {
      // TODO: 创建 SeriesRepository 后使用 repository
      final apiService = ref.read(apiServiceProvider);
      return await apiService.searchSeries(
        query,
        studioId: widget.studioId,
        limit: 10,
      );
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<SeriesWithStudio>(
      textEditingController: widget.controller,
      focusNode: FocusNode(),
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<SeriesWithStudio>.empty();
        }
        
        // 使用 Completer 来处理 debounce
        final completer = Completer<List<SeriesWithStudio>>();
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () async {
          final results = await _searchSeries(textEditingValue.text);
          if (!completer.isCompleted) {
            completer.complete(results);
          }
        });
        
        return await completer.future;
      },
      displayStringForOption: (SeriesWithStudio option) => option.name,
      onSelected: (SeriesWithStudio selection) {
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
                labelText: widget.labelText ?? '系列',
                hintText: widget.hintText ?? '输入系列名称',
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
        AutocompleteOnSelected<SeriesWithStudio> onSelected,
        Iterable<SeriesWithStudio> options,
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
                  final series = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(series.name),
                    subtitle: Text(
                      series.studioName != null
                          ? '${series.studioName} · ${series.mediaCount} 部作品'
                          : '${series.mediaCount} 部作品',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () => onSelected(series),
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
