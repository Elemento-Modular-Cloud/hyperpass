import 'package:flutter/material.dart';

/// [TextEditingController] that applies lightweight YAML syntax highlighting.
class YamlHighlightController extends TextEditingController {
  YamlHighlightController({super.text});

  static final _linePattern = RegExp(
    r'^(?<indent>\s*)'
    r'(?:'
    r'(?<comment>#.*)'
    r'|(?<list>-\s+)'
    r')?'
    r'(?:'
    r'(?<key>[A-Za-z0-9_.-]+)\s*:'
    r'(?<sep>\s*)'
    r'(?<value>.*)?'
    r'|(?<plain>.*)'
    r')?$',
    multiLine: true,
  );

  static final _boolPattern =
      RegExp(r'^(true|false|yes|no|on|off)$', caseSensitive: false);
  static final _numberPattern = RegExp(r'^-?\d+(\.\d+)?$');
  static final _quotedPattern = RegExp(r'''^(['"]).*\1$''');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final styles = Theme.of(context).brightness == Brightness.dark
        ? YamlHighlightStyles.dark
        : YamlHighlightStyles.light;
    final spans = <InlineSpan>[];
    final source = text;
    var offset = 0;

    for (final match in _linePattern.allMatches(source)) {
      if (match.start > offset) {
        spans.add(TextSpan(
          text: source.substring(offset, match.start),
          style: base,
        ));
      }
      spans.addAll(_spansForLine(match, base, styles));
      offset = match.end;
    }

    if (offset < source.length) {
      spans.add(TextSpan(text: source.substring(offset), style: base));
    }

    return TextSpan(style: base, children: spans);
  }

  List<InlineSpan> _spansForLine(
    RegExpMatch match,
    TextStyle base,
    YamlHighlightStyles styles,
  ) {
    final spans = <InlineSpan>[];

    void add(String? value, TextStyle? style) {
      if (value == null || value.isEmpty) return;
      spans.add(TextSpan(text: value, style: style ?? base));
    }

    add(match.namedGroup('indent'), base);

    final comment = match.namedGroup('comment');
    if (comment != null) {
      add(comment, base.merge(styles.comment));
      return spans;
    }

    add(match.namedGroup('list'), base.merge(styles.punctuation));

    final key = match.namedGroup('key');
    if (key != null) {
      add(key, base.merge(styles.key));
      add(':', base.merge(styles.punctuation));
      add(match.namedGroup('sep'), base);
      _appendValueSpans(match.namedGroup('value') ?? '', base, styles, spans);
      return spans;
    }

    _appendValueSpans(match.namedGroup('plain') ?? '', base, styles, spans);
    return spans;
  }

  void _appendValueSpans(
    String value,
    TextStyle base,
    YamlHighlightStyles styles,
    List<InlineSpan> spans,
  ) {
    if (value.isEmpty) return;

    var code = value;
    String? trailingComment;
    final trimmedForQuote = value.trimLeft();
    final isQuoted = trimmedForQuote.startsWith("'") ||
        trimmedForQuote.startsWith('"');
    if (!isQuoted) {
      final hashIndex = value.indexOf(' #');
      if (hashIndex >= 0) {
        code = value.substring(0, hashIndex);
        trailingComment = value.substring(hashIndex + 1); // keep '#'
      } else if (value.startsWith('#')) {
        spans.add(TextSpan(text: value, style: base.merge(styles.comment)));
        return;
      }
    }

    final trimmed = code.trimRight();
    final trailingSpace = code.substring(trimmed.length);
    if (trimmed.isNotEmpty) {
      spans.add(TextSpan(text: trimmed, style: _valueStyle(trimmed, base, styles)));
    }
    if (trailingSpace.isNotEmpty) {
      spans.add(TextSpan(text: trailingSpace, style: base));
    }
    if (trailingComment != null) {
      // Restore the space before '#' that we used as a delimiter.
      spans.add(TextSpan(text: ' ', style: base));
      spans.add(TextSpan(
        text: trailingComment,
        style: base.merge(styles.comment),
      ));
    }
  }

  TextStyle _valueStyle(
    String value,
    TextStyle base,
    YamlHighlightStyles styles,
  ) {
    if (value.isEmpty) return base;
    if (_quotedPattern.hasMatch(value) ||
        value.startsWith("'") ||
        value.startsWith('"')) {
      return base.merge(styles.string);
    }
    if (_boolPattern.hasMatch(value) || value == '~' || value == 'null') {
      return base.merge(styles.keyword);
    }
    if (_numberPattern.hasMatch(value)) {
      return base.merge(styles.number);
    }
    return base.merge(styles.value);
  }
}

@immutable
class YamlHighlightStyles {
  const YamlHighlightStyles({
    required this.comment,
    required this.key,
    required this.value,
    required this.string,
    required this.number,
    required this.keyword,
    required this.punctuation,
  });

  final TextStyle comment;
  final TextStyle key;
  final TextStyle value;
  final TextStyle string;
  final TextStyle number;
  final TextStyle keyword;
  final TextStyle punctuation;

  static const dark = YamlHighlightStyles(
    comment: TextStyle(color: Color(0xFF6A9955)),
    key: TextStyle(color: Color(0xFF9CDCFE)),
    value: TextStyle(color: Color(0xFFD4D4D4)),
    string: TextStyle(color: Color(0xFFCE9178)),
    number: TextStyle(color: Color(0xFFB5CEA8)),
    keyword: TextStyle(color: Color(0xFF569CD6)),
    punctuation: TextStyle(color: Color(0xFFD4D4D4)),
  );

  static const light = YamlHighlightStyles(
    comment: TextStyle(color: Color(0xFF008000)),
    key: TextStyle(color: Color(0xFF0451A5)),
    value: TextStyle(color: Color(0xFF000000)),
    string: TextStyle(color: Color(0xFFA31515)),
    number: TextStyle(color: Color(0xFF098658)),
    keyword: TextStyle(color: Color(0xFF0000FF)),
    punctuation: TextStyle(color: Color(0xFF000000)),
  );
}
