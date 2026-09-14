import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// The app's search input: rounded pill without a leading/prefix icon, with a
/// single compact interactive Search button on the right (smaller + right
/// margin). Used inside the full-screen search overlay.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSearchPressed,
    this.onClear,
    this.hintText = 'Search for music on YouTube',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onSearchPressed;

  /// Called when the trailing Clear (X) button is tapped. Clears the field
  /// text and resets the current search state without triggering a search.
  final VoidCallback? onClear;

  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the field value changes (including programmatic
    // clears) so the trailing icon always tracks the current text.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasText = controller.text.isNotEmpty;
        return SizedBox(
          height: 52,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hintText,
              suffixIcon: hasText && onClear != null
                  ? _SearchClearButton(onPressed: onClear!)
                  : _SearchActionButton(onPressed: onSearchPressed),
            ),
          ),
        );
      },
    );
  }
}

/// Non-editable search-bar lookalike used as the entry point on the Search
/// screen: tapping it (or its Search button) opens the full-screen overlay.
class SearchLauncherBar extends StatelessWidget {
  const SearchLauncherBar({
    super.key,
    required this.controller,
    required this.onTap,
    required this.onSearchPressed,
    this.hintText = 'Search for music on YouTube',
    this.isLoading = false,
  });

  final TextEditingController controller;
  final VoidCallback onTap;
  final VoidCallback onSearchPressed;
  final String hintText;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).inputDecorationTheme;
    final text = controller.text.trim();
    return Material(
      color: theme.fillColor ?? AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.only(left: AppRadius.lg, right: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text.isEmpty ? hintText : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: text.isEmpty
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  _SearchActionButton(onPressed: onSearchPressed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact, right-margined Search action button shared by both flavors.
class _SearchActionButton extends StatelessWidget {
  const _SearchActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        key: const Key('search_action'),
        tooltip: 'Search',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.all(8),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.search_rounded),
      ),
    );
  }
}

/// The compact Clear (X) button shown while the search field has a value.
class _SearchClearButton extends StatelessWidget {
  const _SearchClearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IconButton(
        key: const Key('search_clear'),
        tooltip: 'Clear search',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceMuted,
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.all(8),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.clear),
      ),
    );
  }
}