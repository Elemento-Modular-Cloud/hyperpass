import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../widgets/rounded_search_field.dart';

class SearchNameNotifier extends Notifier<String> {
  @override
  String build() {
    return '';
  }

  void set(String value) {
    state = value;
  }
}

final searchNameProvider = NotifierProvider<SearchNameNotifier, String>(
  SearchNameNotifier.new,
);

final llmSearchProvider = NotifierProvider<SearchNameNotifier, String>(
  SearchNameNotifier.new,
);

final serviceSearchProvider = NotifierProvider<SearchNameNotifier, String>(
  SearchNameNotifier.new,
);

class SearchBox extends ConsumerWidget {
  const SearchBox({
    super.key,
    this.hint,
    this.provider,
    this.width = 280,
  });

  final String? hint;
  final NotifierProvider<SearchNameNotifier, String>? provider;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final searchProvider = provider ?? searchNameProvider;
    return RoundedSearchField(
      width: width,
      hint: hint ?? l10n.searchBoxHint,
      onChanged: (name) => ref.read(searchProvider.notifier).set(name),
    );
  }
}
