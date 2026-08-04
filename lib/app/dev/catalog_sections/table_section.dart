import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import 'catalog_section_scaffold.dart';

class _ClienteDemo {
  const _ClienteDemo(this.id, this.nombre, this.rfc, this.tone, this.estado);
  final String id;
  final String nombre;
  final String rfc;
  final RisegStatusTone tone;
  final String estado;
}

const _clientesDemo = [
  _ClienteDemo('1', 'Sportium', 'SPO010101AA1', RisegStatusTone.success, 'Activo'),
  _ClienteDemo('2', 'Grupo Alfa', 'GAL020202BB2', RisegStatusTone.success, 'Activo'),
  _ClienteDemo('3', 'Constructora Delta', 'CDE030303CC3', RisegStatusTone.warning, 'Suspendido'),
  _ClienteDemo('4', 'Plaza Norte', 'PNO040404DD4', RisegStatusTone.error, 'Contrato vencido'),
];

class TableCatalogSection extends StatefulWidget {
  const TableCatalogSection({super.key});

  @override
  State<TableCatalogSection> createState() => _TableCatalogSectionState();
}

class _TableCatalogSectionState extends State<TableCatalogSection> {
  _ClienteDemo? _selected;
  bool _loading = false;
  bool _empty = false;

  late final _columns = [
    RisegColumn<_ClienteDemo>(label: 'CLIENTE', cellBuilder: (row) => Text(row.nombre)),
    RisegColumn<_ClienteDemo>(label: 'RFC', cellBuilder: (row) => Text(row.rfc, style: AppTypography.data)),
    RisegColumn<_ClienteDemo>(
      label: 'ESTADO',
      width: 160,
      cellBuilder: (row) => RisegStatusBadge(label: row.estado, tone: row.tone),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CatalogSection(
      children: [
        CatalogSubsection(
          title: 'RisegTableBase — tabla de clientes',
          description: 'Tab entre filas, Enter/Espacio selecciona, hover y selección visual, acciones por fila',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  RisegButton(
                    label: _loading ? 'Detener carga' : 'Simular carga',
                    size: RisegButtonSize.compact,
                    variant: RisegButtonVariant.secondary,
                    onPressed: () => setState(() => _loading = !_loading),
                  ),
                  RisegButton(
                    label: _empty ? 'Mostrar filas' : 'Vaciar tabla',
                    size: RisegButtonSize.compact,
                    variant: RisegButtonVariant.secondary,
                    onPressed: () => setState(() => _empty = !_empty),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTableBase<_ClienteDemo>(
                columns: _columns,
                rows: _empty ? const [] : _clientesDemo,
                loading: _loading,
                selectedRow: _selected,
                onRowTap: (row) => setState(() => _selected = row),
                rowActionsBuilder: (row) => IconButton(
                  tooltip: 'Editar ${row.nombre}',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () {},
                ),
                emptyState: const RisegEmptyState(
                  title: 'Sin clientes que mostrar',
                  message: 'Ajusta los filtros o da de alta un nuevo cliente.',
                  icon: Icons.groups_outlined,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
