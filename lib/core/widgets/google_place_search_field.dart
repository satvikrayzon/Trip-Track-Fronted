import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/picked_location.dart';
import '../services/google_places_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'map_location_picker_screen.dart';

/// Google Places search with an inline suggestion dropdown (no map).
class GooglePlaceSearchField extends StatefulWidget {
  const GooglePlaceSearchField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.initial,
    this.errorText,
    this.readOnly = false,
    required this.onLocationSelected,
  });

  final String label;
  final String hint;
  final IconData icon;
  final PickedLocation? initial;
  final String? errorText;
  final bool readOnly;
  final ValueChanged<PickedLocation?> onLocationSelected;

  @override
  State<GooglePlaceSearchField> createState() => _GooglePlaceSearchFieldState();
}

class _GooglePlaceSearchFieldState extends State<GooglePlaceSearchField> {
  final _places = GooglePlacesService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  final _suggestions = ValueNotifier<List<PlacePrediction>>([]);
  final _loadingSuggestions = ValueNotifier<bool>(false);
  final _resolvingSelection = ValueNotifier<bool>(false);
  final _selected = ValueNotifier<PickedLocation?>(null);
  final _focused = ValueNotifier<bool>(false);

  Timer? _debounce;

  Listenable get _uiListenable => Listenable.merge([
        _suggestions,
        _loadingSuggestions,
        _resolvingSelection,
        _selected,
        _focused,
      ]);

  @override
  void initState() {
    super.initState();
    _selected.value = widget.initial;
    if (widget.initial != null) {
      _controller.text = _fieldTextFor(widget.initial!);
    }
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant GooglePlaceSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial &&
        widget.initial != _selected.value) {
      _selected.value = widget.initial;
      _controller.text = widget.initial != null
          ? _fieldTextFor(widget.initial!)
          : '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    _suggestions.dispose();
    _loadingSuggestions.dispose();
    _resolvingSelection.dispose();
    _selected.dispose();
    _focused.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    _focused.value = _focusNode.hasFocus;
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _suggestions.value = [];
      });
    }
  }

  String _fieldTextFor(PickedLocation location) {
    if (location.formattedAddress != null &&
        location.formattedAddress!.trim().isNotEmpty) {
      return location.formattedAddress!;
    }
    return location.name;
  }

  String? _fullAddressFor(PickedLocation location) {
    final full = location.formattedAddress?.trim();
    if (full == null || full.isEmpty) return null;
    final short = _fieldTextFor(location);
    if (full.toLowerCase() == short.toLowerCase()) return null;
    return full;
  }

  Future<void> _openMapPicker(BuildContext context) async {
    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => MapLocationPickerScreen(
          label: widget.label,
          initialLocation: _selected.value?.latLng,
        ),
      ),
    );

    if (result != null && mounted) {
      _selected.value = result;
      _controller.text = _fieldTextFor(result);
      widget.onLocationSelected(result);
    }
  }

  void _onTextChanged(String value) {
    if (widget.readOnly) return;
    final selected = _selected.value;
    if (selected != null &&
        value.trim() != _fieldTextFor(selected) &&
        value.trim() != selected.name.trim()) {
      _selected.value = null;
      widget.onLocationSelected(null);
    }

    _debounce?.cancel();
    if (value.trim().length < 2) {
      _suggestions.value = [];
      _loadingSuggestions.value = false;
      return;
    }

    _loadingSuggestions.value = true;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _places.autocomplete(value);
      if (!mounted) return;
      _suggestions.value = results;
      _loadingSuggestions.value = false;
    });
  }

  Future<void> _selectSuggestion(PlacePrediction prediction) async {
    _resolvingSelection.value = true;
    _suggestions.value = [];
    _controller.text = prediction.description;
    _focusNode.unfocus();

    final picked = await _places.placeDetails(
      prediction.placeId,
      selectedName: prediction.mainText,
    );
    if (!mounted) return;

    _resolvingSelection.value = false;

    if (picked == null) {
      _selected.value = null;
      widget.onLocationSelected(null);
      return;
    }

    _selected.value = picked;
    _controller.text = _fieldTextFor(picked);
    widget.onLocationSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _uiListenable,
      builder: (context, _) {
        final showDropdown = _focused.value &&
            (_loadingSuggestions.value || _suggestions.value.isNotEmpty);
        final selected = _selected.value;
        final resolving = _resolvingSelection.value;
        final loading = _loadingSuggestions.value;
        final suggestions = _suggestions.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: AppTextStyles.inputLabel.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              readOnly: widget.readOnly,
              enabled: !widget.readOnly,
              onChanged: _onTextChanged,
              style: AppTextStyles.inputText.copyWith(
                color: widget.readOnly
                    ? AppColors.textDisabled
                    : AppColors.textPrimary,
              ),
              validator: (_) {
                if (widget.errorText != null) return widget.errorText;
                if (selected == null) {
                  return 'Please select a location from the list';
                }
                return null;
              },
              decoration: InputDecoration(
                hintText: widget.hint,
                filled: true,
                fillColor: AppColors.surfaceVariant,
                prefixIcon: Icon(widget.icon),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (resolving)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (selected != null)
                      const Icon(Icons.check_circle, color: AppColors.success)
                    else
                      const Icon(Icons.search),
                    IconButton(
                      icon: const Icon(Icons.map, color: AppColors.primary),
                      tooltip: 'Select on Map',
                      onPressed: () => _openMapPicker(context),
                    ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.greyLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.buttonRadius),
                  borderSide: BorderSide(
                    color: widget.errorText != null
                        ? AppColors.error
                        : AppColors.greyLight,
                  ),
                ),
                errorText: widget.errorText,
              ),
            ),
            if (selected != null && !showDropdown) ...[
              if (_fullAddressFor(selected) case final fullAddress?) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        fullAddress,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
            if (showDropdown)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  elevation: 4,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                    side: const BorderSide(color: AppColors.greyLight),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: loading && suggestions.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: suggestions.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = suggestions[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.place_outlined,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                title: Text(
                                  item.mainText,
                                  style: AppTextStyles.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: item.description != item.mainText
                                    ? Text(
                                        item.description
                                            .replaceFirst(item.mainText, '')
                                            .replaceFirst(RegExp(r'^,\s*'), ''),
                                        style: AppTextStyles.labelSmall
                                            .copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                onTap: () => _selectSuggestion(item),
                              );
                            },
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
