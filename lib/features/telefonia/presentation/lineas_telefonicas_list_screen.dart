import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/presentation/articulos/articulos_list_screen.dart' show formatoCosto;

import 'linea_telefonica_labels.dart';
import 'telefonia_controller.dart';
import 'telefonia_state.dart';
import 'widgets/gestionar_linea_telefonica_dialog.dart';
import '../telefonia_providers.dart';

/// Listado de líneas telefónicas (Etapa 9A) — la pantalla principal de
/// Telefonía. Sin pestañas todavía (mismo criterio que Inventario en
/// 7A/Vehículos en 8A: la subnavegación llega cuando exista más de una
/// sección real, ver la Etapa 9C).
class LineasTelefonicasListScreen extends ConsumerWidget {
  const LineasTelefonicasListScreen({super.key});

  Future<void> _nuevaLinea(BuildContext context, WidgetRef ref) async {
    await mostrarDialogoGestionarLineaTelefonica(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(telefoniaControllerProvider);
    final notifier = ref.read(telefoniaControllerProvider.notifier);

    if (state.errorCarga != null && state.lineas.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.telefoniaListadoCargaErrorTitulo,
        message: l10n.telefoniaListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('telefonia_boton_reintentar'),
          label: l10n.telefoniaListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.telefoniaListadoTitulo,
            primaryAction: RisegButton(
              key: const Key('telefonia_boton_nueva_linea'),
              label: l10n.telefoniaBotonNuevaLinea,
              onPressed: () => _nuevaLinea(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _LineasTable(state: state),
          ),
        ],
      ),
    );
  }
}

class _LineasTable extends ConsumerStatefulWidget {
  const _LineasTable({required this.state});

  final TelefoniaState state;

  @override
  ConsumerState<_LineasTable> createState() => _LineasTableState();
}

class _LineasTableState extends ConsumerState<_LineasTable> {
  Map<String, LineaTelefonicaPlanData> _planVigentePorLinea = const {};
  bool _cargandoPlanes = true;

  @override
  void initState() {
    super.initState();
    _cargarPlanes();
  }

  @override
  void didUpdateWidget(covariant _LineasTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.lineas != widget.state.lineas) _cargarPlanes();
  }

  Future<void> _cargarPlanes() async {
    final planes = await ref.read(lineaTelefonicaPlanRepositoryProvider).listarVigentes();
    if (!mounted) return;
    setState(() {
      _planVigentePorLinea = {for (final p in planes) p.lineaTelefonicaId: p};
      _cargandoPlanes = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RisegTableBase<LineaTelefonicaData>(
      loading: widget.state.cargando || _cargandoPlanes,
      rows: widget.state.lineas,
      onRowTap: (l) => context.go('/telefonia/${l.id}'),
      emptyState: RisegEmptyState(
        title: l10n.telefoniaListadoVacioTitulo,
        message: l10n.telefoniaListadoVacioMensaje,
      ),
      columns: [
        RisegColumn<LineaTelefonicaData>(
          label: l10n.telefoniaColumnaCodigo,
          width: 110,
          cellBuilder: (l) => Text(l.codigo),
        ),
        RisegColumn<LineaTelefonicaData>(
          label: l10n.telefoniaColumnaNumero,
          width: 130,
          cellBuilder: (l) => Text(l.numero ?? '—'),
        ),
        RisegColumn<LineaTelefonicaData>(
          label: l10n.telefoniaColumnaOperador,
          width: 130,
          cellBuilder: (l) => Text(operadorLineaTelefonicaLabel(l10n, l)),
        ),
        RisegColumn<LineaTelefonicaData>(
          label: l10n.telefoniaColumnaPlan,
          cellBuilder: (l) => Text(_planVigentePorLinea[l.id]?.nombre ?? '—'),
        ),
        RisegColumn<LineaTelefonicaData>(
          label: l10n.telefoniaColumnaCostoMensual,
          width: 120,
          alignment: TextAlign.right,
          cellBuilder: (l) {
            final costo = _planVigentePorLinea[l.id]?.costoMensual;
            return Text(costo == null ? '—' : formatoCosto(costo));
          },
        ),
        RisegColumn<LineaTelefonicaData>(
          label: l10n.telefoniaColumnaEstatus,
          width: 130,
          cellBuilder: (l) => RisegStatusBadge(
            label: estatusLineaTelefonicaLabel(l10n, l.estatus),
            tone: estatusLineaTelefonicaTono(l.estatus),
          ),
        ),
      ],
    );
  }
}
