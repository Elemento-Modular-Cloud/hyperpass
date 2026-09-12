import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../brand.dart';

class TableHeader<T> {
  final String name;
  final Widget Function(String) childBuilder;
  final String Function(T)? sortKey;
  double width;
  final double minWidth;
  double _oldWidth;
  final Widget Function(T) cellBuilder;

  TableHeader({
    this.name = '',
    this.childBuilder = defaultHeaderBuilder,
    this.sortKey,
    required this.width,
    required this.minWidth,
    required this.cellBuilder,
  }) : _oldWidth = width;

  static Widget defaultHeaderBuilder(String name) {
    return Builder(
      builder: (context) {
        final onSurface = Theme.of(context).colorScheme.onSurface;
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
                color: onSurface.withValues(alpha: 0.48),
              ),
            ),
          ),
        );
      },
    );
  }
}

class Table<T> extends StatefulWidget {
  final List<TableHeader<T>> headers;
  final List<T> data;
  final List<Widget> finalRow;
  final bool Function(T entry)? isSelected;
  final double rowExtent;
  final EdgeInsets cellMargin;

  const Table({
    super.key,
    required this.headers,
    required this.data,
    required this.finalRow,
    this.isSelected,
    this.rowExtent = 50,
    this.cellMargin = const EdgeInsets.all(10),
  });

  @override
  State<Table<T>> createState() => _TableState<T>();
}

class _TableState<T> extends State<Table<T>> {
  final horizontal = ScrollController();
  final vertical = ScrollController();
  var isResizingColumn = 0;
  bool sortAscending = false;
  int? sortIndex;
  int? hoveredRow;

  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  Color _separator(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
  }

  Widget addScrollbars(TableView table) {
    return Scrollbar(
      controller: vertical,
      child: Scrollbar(controller: horizontal, child: table),
    );
  }

  Widget buildHeader(int index, TableHeader<T> header) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final resizeHandle = MouseRegion(
      onEnter: (_) => setState(() => isResizingColumn++),
      onExit: (_) => setState(() => isResizingColumn--),
      child: GestureDetector(
        child: Container(
          width: 10,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: _separator(context), width: 1),
            ),
          ),
        ),
        onHorizontalDragStart: (_) => setState(() => isResizingColumn++),
        onHorizontalDragUpdate: (d) => setState(() {
          header.width = max(
            header.minWidth,
            header._oldWidth + d.localPosition.dx,
          );
        }),
        onHorizontalDragEnd: (_) => setState(() {
          header._oldWidth = header.width;
          isResizingColumn--;
        }),
      ),
    );

    final title = Stack(
      children: [
        Positioned.fill(child: header.childBuilder(header.name)),
        if (index == sortIndex)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                sortAscending
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 10,
                color: onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );

    setSorting() {
      setState(() {
        if (sortIndex == index && !sortAscending) {
          sortAscending = false;
          sortIndex = null;
        } else {
          sortAscending = sortIndex == index ? !sortAscending : true;
          sortIndex = index;
        }
      });
    }

    return Stack(
      children: [
        header.sortKey != null
            ? InkWell(onTap: setSorting, child: title)
            : title,
        Align(alignment: Alignment.centerRight, child: resizeHandle),
      ],
    );
  }

  List<Widget> buildRow(T entry) {
    return [
      for (final header in widget.headers)
        Container(
          alignment: Alignment.centerLeft,
          margin: widget.cellMargin,
          child: header.cellBuilder(entry),
        ),
    ];
  }

  Color? _rowColor(int row, List<T> data) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (row == 0) {
      return onSurface.withValues(alpha: isDark ? 0.06 : 0.04);
    }
    if (row > 0 && row <= data.length) {
      final entry = data[row - 1];
      if (widget.isSelected?.call(entry) ?? false) {
        return Brand.accent.withValues(alpha: 0.14);
      }
      if (hoveredRow == row) {
        return onSurface.withValues(alpha: isDark ? 0.07 : 0.05);
      }
      if ((row - 1).isOdd) {
        return onSurface.withValues(alpha: isDark ? 0.045 : 0.032);
      }
    }
    return null;
  }

  BoxBorder? _rowBorder(int row, int rowCount) {
    final hairline = BorderSide(color: _separator(context));
    if (row == 0) {
      return Border(bottom: hairline);
    }
    if (row == rowCount - 1 && row > 0) {
      return Border(top: hairline);
    }
    return null;
  }

  List<double> _columnWidths(double viewportWidth) {
    final headers = widget.headers;
    final natural = [
      for (final h in headers) max(h.minWidth, h.width),
    ];
    final total = natural.fold<double>(0, (sum, w) => sum + w);
    if (viewportWidth <= 0 || total >= viewportWidth) {
      return natural;
    }

    final scale = viewportWidth / total;
    return [for (final w in natural) w * scale];
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Iterable<T> data = widget.data;
    final sortKey = widget.headers
        .elementAtOrNull(sortIndex ?? widget.headers.length)
        ?.sortKey;
    if (sortKey != null) {
      final sortedData = data.sortedBy(sortKey);
      data = sortAscending ? sortedData : sortedData.reversed;
    }
    final dataList = data.toList();

    final headerCells = [
      for (final (i, header) in widget.headers.indexed) buildHeader(i, header),
    ];
    final cells = [headerCells, ...dataList.map(buildRow), widget.finalRow];

    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _columnWidths(constraints.maxWidth);

        final table = TableView.builder(
          horizontalDetails:
              ScrollableDetails.horizontal(controller: horizontal),
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
          pinnedRowCount: 1,
          rowCount: cells.length,
          columnCount: widget.headers.length,
          rowBuilder: (_) =>
              TableSpan(extent: FixedTableSpanExtent(widget.rowExtent)),
          columnBuilder: (i) => TableSpan(
            extent: FixedTableSpanExtent(widths[i]),
          ),
          cellBuilder: (_, v) {
            final rowColor = _rowColor(v.row, dataList);
            return TableViewCell(
              child: MouseRegion(
                onEnter: v.row == 0
                    ? null
                    : (_) => setState(() => hoveredRow = v.row),
                onExit: v.row == 0
                    ? null
                    : (_) => setState(() {
                          if (hoveredRow == v.row) hoveredRow = null;
                        }),
                child: Container(
                  decoration: BoxDecoration(
                    color: rowColor,
                    border: _rowBorder(v.row, cells.length),
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: onSurface,
                      fontSize: v.row == 0 ? 11 : 13,
                    ),
                    child: cells
                            .elementAtOrNull(v.row)
                            ?.elementAtOrNull(v.column) ??
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        );

        final radius = BorderRadius.circular(Brand.radius);
        return MouseRegion(
          cursor: isResizingColumn == 0
              ? MouseCursor.defer
              : SystemMouseCursors.resizeColumn,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _separator(context)),
              borderRadius: radius,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: addScrollbars(table),
            ),
          ),
        );
      },
    );
  }
}
