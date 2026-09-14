import 'package:flutter/material.dart';
import '../services/search_suggestion_service.dart';
import '../services/youtube_url.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/search_field.dart';

/// Full-screen, modal search UI shown above the whole app. The background
/// (including the navigation bar) is dimmed and blocked; back / tapping the
/// barrier closes the overlay without searching.
///
/// Returns the chosen query via [Navigator.pop]; a dismissed overlay pops with
/// null.
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({
    super.key,
    required this.initialQuery,
    required this.fetchSuggestions,
    required this.recents,
  });

  final String initialQuery;
  final Future<List<String>> Function(String query) fetchSuggestions;
  final RecentSearchStore recents;

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final SearchSuggestionService _suggestions;

  List<String> _recentQueries = const [];
  bool _busy = false;
  bool _showRecents = false;
  List<String> _suggestionResults = const [];
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialQuery.length,
    );
    _focusNode = FocusNode();
    _suggestions = SearchSuggestionService(
      fetchSuggestions: widget.fetchSuggestions,
    );
    _loadRecents();

    // Carry-over query: request suggestions immediately so the overlay opens
    // fully populated. Initial field values are pre-build, no setState needed.
    final initial = widget.initialQuery.trim();
    if (initial.isNotEmpty && !isYouTubeUrl(initial)) {
      _busy = true;
      _showRecents = false;
      _suggestions.requestSuggestions(initial, _onSuggestionsReady);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _suggestions.dispose();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    await widget.recents.ensureLoaded();
    if (_disposed || !mounted) {
      return;
    }
    setState(() => _recentQueries = widget.recents.items);
    if (_controller.text.trim().isEmpty && _recentQueries.isNotEmpty) {
      setState(() => _showRecents = true);
    }
  }

  void _onTextChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _suggestions.cancel();
      setState(() {
        _busy = false;
        _showRecents = _recentQueries.isNotEmpty;
        _suggestionResults = const [];
      });
      return;
    }
    if (isYouTubeUrl(trimmed)) {
      _suggestions.cancel();
      setState(() {
        _busy = false;
        _showRecents = false;
        _suggestionResults = const [];
      });
      return;
    }
    setState(() {
      _busy = true;
      _showRecents = false;
      _suggestionResults = const [];
    });
    _suggestions.requestSuggestions(value, _onSuggestionsReady);
  }

  /// Clears the field and resets the overlay's search state back to the
  /// empty-field view (recents / hints). Never triggers a search.
  void _onClear() {
    _controller.clear();
    _onTextChanged('');
  }

  void _onSuggestionsReady(List<String> suggestions) {
    if (_disposed || !mounted) {
      return;
    }
    if (isYouTubeUrl(_controller.text.trim())) {
      setState(() {
        _busy = false;
        _suggestionResults = const [];
      });
      return;
    }
    setState(() {
      _busy = false;
      _suggestionResults = suggestions;
    });
  }

  void _close() {
    Navigator.of(context).pop();
  }

  void _submit([String? query]) {
    final q = (query ?? _controller.text).trim();
    if (q.isEmpty) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(q);
    }
  }

  Future<void> _removeRecent(String query) async {
    await widget.recents.remove(query);
    if (_disposed || !mounted) {
      return;
    }
    setState(() => _recentQueries = widget.recents.items);
  }

  Future<void> _clearRecents() async {
    await widget.recents.clear();
    if (_disposed || !mounted) {
      return;
    }
    setState(() => _recentQueries = widget.recents.items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The overlay page fully covers the app, so tapping any empty part
            // of the background dismisses it (back / barrier also close it).
            // All interactive content below absorbs its own taps, so nothing
            // behind this route can ever receive input while search is active.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Close search',
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textPrimary,
                        ),
                        onPressed: _close,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: SearchField(
                          key: const Key('search_overlay_field'),
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          onChanged: _onTextChanged,
                          onSubmitted: (_) => _submit(),
                          onSearchPressed: () => _submit(),
                          onClear: _onClear,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(child: _buildContent(_controller.text.trim())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String text) {
    if (isYouTubeUrl(text)) {
      return const _OverlayMessage(
        icon: Icons.link_rounded,
        title: 'YouTube video link detected',
        subtitle: 'Press Search to open this video',
      );
    }
    if (_busy) {
      return const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Text('Searching…', style: AppTypography.caption),
          ],
        ),
      );
    }
    if (text.isEmpty) {
      if (_showRecents && _recentQueries.isNotEmpty) {
        return _recentsPanel();
      }
      return const _OverlayMessage(
        icon: Icons.search_rounded,
        title: 'Search for music on YouTube',
      );
    }
    if (_suggestionResults.isNotEmpty) {
      return _suggestionsPanel();
    }
    return _OverlayMessage(
      icon: Icons.search_off_rounded,
      title: 'Press Search to find “$text”',
    );
  }

  Widget _recentsPanel() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            children: [
              const Text('Recent searches', style: AppTypography.caption),
              const Spacer(),
              IconButton(
                tooltip: 'Clear recent searches',
                iconSize: 18,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textMuted,
                ),
                onPressed: _clearRecents,
              ),
            ],
          ),
        ),
        for (final query in _recentQueries)
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.schedule_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            title: Text(
              query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body,
            ),
            trailing: IconButton(
              tooltip: 'Remove',
              iconSize: 18,
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.textMuted,
              ),
              onPressed: () => _removeRecent(query),
            ),
            onTap: () => _submit(query),
          ),
      ],
    );
  }

  Widget _suggestionsPanel() {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _suggestionResults.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestionResults[index];
        return ListTile(
          dense: true,
          leading: const Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.textSecondary,
          ),
          title: Text(
            suggestion,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body,
          ),
          onTap: () => _submit(suggestion),
        );
      },
    );
  }
}

class _OverlayMessage extends StatelessWidget {
  const _OverlayMessage({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ],
      ),
    );
  }
}