import 'package:flutter_riverpod/flutter_riverpod.dart';

enum IntentsHubTab { list, compose }

class IntentsHubTabNotifier extends Notifier<IntentsHubTab> {
  @override
  IntentsHubTab build() => IntentsHubTab.list;

  void showList() => state = IntentsHubTab.list;

  void showCompose() => state = IntentsHubTab.compose;
}

final intentsHubTabProvider =
    NotifierProvider<IntentsHubTabNotifier, IntentsHubTab>(
  IntentsHubTabNotifier.new,
);
