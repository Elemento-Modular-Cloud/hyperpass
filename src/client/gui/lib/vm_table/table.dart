import 'dart:math';

import 'package:collection/collection.dart';
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
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(left: 10),
      child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class Table<T> extends StatefulWidget {
  final List<TableHeader<T>> headers;
  final List<T> data;
  final List<Widget> finalRow;
  final bool Function(T entry)? isSelected;

  const Table({
    super.key,
    required this.headers,
    required this.data,
    required this.finalRow,
    this.isSelected,
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

  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  BorderSide _borderSide(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.25);
    return BorderSide(color: muted, width: 0.5);
  }

  Widget addScrollbars(TableView table) {
    return Scrollbar(
      controller: vertical,
      child: Scrollbar(controller: horizontal, child: table),
    );
  }

  Widget buildHeader(int index, TableHeader<T> header, BorderSide borderSide) {
    final resizeHandle = MouseRegion(
      onEnter: (_) => setState(() => isResizingColumn++),
      onExit: (_) => setState(() => isResizingColumn--),
      child: GestureDetector(
        child: Container(
          width: 10,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(right: borderSide),
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
            child: sortAscending
                ? const Icon(Icons.arrow_drop_up_rounded)
                : const Icon(Icons.arrow_drop_down_rounded),
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
          margin: const EdgeInsets.all(10),
          child: header.cellBuilder(entry),
        ),
    ];
  }

  Color? _rowColor(int row, List<T> data) {
    if (row <= 0 || row > data.length) return null;
    final entry = data[row - 1];
    final selected = widget.isSelected?.call(entry) ?? false;
    if (!selected) return null;
    return Brand.accent.withOpacity(0.14);
  }

  List<double> _columnWidths(double viewportWidth) {
    final headers = widget.headers;
    final weightSum = headers.fold<double>(0, (sum, h) => sum + h.width);
    if (weightSum <= 0 || viewportWidth <= 0) {
      return headers.map((h) => h.width).toList();
    }

    final scale = viewportWidth / weightSum;
    return [
      for (final h in headers) max(h.minWidth, h.width * scale),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final borderSide = _borderSide(context);
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
      for (final (i, header) in widget.headers.indexed)
        buildHeader(i, header, borderSide),
    ];
    final cells = [headerCells, ...dataList.map(buildRow), widget.finalRow];

    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _columnWidths(constraints.maxWidth);
        // If mins pushed total over viewport, re-normalize down to fit.
        final total = widths.fold<double>(0, (a, b) => a + b);
        final fitted = total <= constraints.maxWidth || total == 0
            ? widths
            : [
                for (final w in widths)
                  w * (constraints.maxWidth / total),
              ];

        final table = TableView.builder(
          horizontalDetails:
              ScrollableDetails.horizontal(controller: horizontal),
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
          pinnedRowCount: 1,
          rowCount: cells.length,
          columnCount: widget.headers.length,
          rowBuilder: (_) =>
              const TableSpan(extent: FixedTableSpanExtent(50)),
          columnBuilder: (i) => TableSpan(
            extent: FixedTableSpanExtent(fitted[i]),
          ),
          cellBuilder: (_, v) {
            final rowColor = _rowColor(v.row, dataList);
            return TableViewCell(
              child: Container(
                decoration: BoxDecoration(
                  color: rowColor,
                  border: Border(
                    bottom: v.row < cells.length - 1
                        ? borderSide
                        : BorderSide.none,
                    left: rowColor != null && v.column == 0
                        ? const BorderSide(color: Brand.accent, width: 3)
                        : BorderSide.none,
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: onSurface),
                  child: cells
                          .elementAtOrNull(v.row)
                          ?.elementAtOrNull(v.column) ??
                      const SizedBox.shrink(),
                ),
              ),
            );
          },
        );

        return MouseRegion(
          cursor: isResizingColumn == 0
              ? MouseCursor.defer
              : SystemMouseCursors.resizeColumn,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(borderSide),
            ),
            child: addScrollbars(table),
          ),
        );
      },
    );
  }
}
