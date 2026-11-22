import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';

const tableColumns = [
  AppColumn.text('Name', sortable: true),
  AppColumn.numeric('Rank', sortable: true, descendingFirst: false),
  AppColumn.numeric('Total points', sortable: true),
  AppColumn.numeric('Correct tips', sortable: true),
  AppColumn.numeric('Margins', sortable: true),
  AppColumn.numeric('Missed tips', sortable: true),
  AppColumn.numeric('Change', sortable: true),
];

List<AppRow> tableRows({int count = 40, VoidCallback? onTap}) => [
  for (var i = 0; i < count; i++) AppRow(key: ValueKey('row-$i'),
    colour: i == 1 ? Colors.lightGreen.shade100 : null, onTap: onTap,
    cells: [
      AppCell.text(i == 1 ? 'Alexandra Montgomery' : 'Tipper ${i + 1}',
        leading: const CircleAvatar(child: Icon(Icons.person, size: 16)),
        leadingSize: const Size(24, 24)),
      AppCell.text('${i + 1}'),
      AppCell.text('${90 - i}'),
      AppCell.text('${42 - i}'),
      AppCell.text('${i % 9}'),
      AppCell.text('${i % 3}'),
      const AppCell.widget(Icon(Icons.arrow_upward, color: Colors.green, size: 20),
        intrinsicSize: Size(20, 20), semanticLabel: 'Up one place'),
    ]),
];
