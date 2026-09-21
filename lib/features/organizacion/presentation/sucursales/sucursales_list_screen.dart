import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';

import '../../organizacion_providers.dart';
import 'sucursales_list_controller.dart';

/// Listado de Sucursales (Etapa 16, tercera pasada visual) — entidades
/// físicas independientes, presentadas como una cuadrícula adaptativa
/// de tarjetas (nunca una tabla): 3 por fila en escritorio ancho, 2 en
/// medio, 1 en compacto. Buscador (código/nombre/tipo) y alta vía
/// diálogo (solo nombre + tipo; el resto se captura en el expediente
/// recién creado).
class SucursalesListScreen extends ConsumerStatefulWidget {
  const SucursalesListScreen({super.key});

  @override
  ConsumerState<SucursalesListScreen> createState() => _SucursalesListScreenState();
}

class _SucursalesListScreenState extends ConsumerState<SucursalesListScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _mostrarDialogoAlta(List<CatalogoItem> tipos) async {
    final l10n = AppLocalizations.of(context)!;
    var nombreActual = '';
    String? tipoSeleccionado;

    final creada = await RisegDialog.showForm<SucursalData?>(
      context: context,
      title: l10n.sucursalAltaTitulo,
      confirmLabel: l10n.sucursalAltaBotonCrear,
      cancelLabel: l10n.sucursalAltaBotonCancelar,
      contentBuilder: (_) => _AltaSucursalForm(
        tipos: tipos,
        onNombreChanged: (valor) => nombreActual = valor,
        onTipoChanged: (valor) => tipoSeleccionado = valor,
      ),
      onConfirm: () async {
        final nombre = nombreActual.trim();
        final tipo = tipoSeleccionado;
        if (nombre.isEmpty || tipo == null) return null;

        final resultado = await ref.read(crearSucursalAutorizadoProvider)(nombre: nombre, tipoSucursalId: tipo);
        return resultado.when(ok: (s) => s, failure: (_) => null);
      },
    );

    if (!mounted) return;

    if (creada != null) {
      ref.read(sucursalesListControllerProvider.notifier).recargar();
      RisegFeedback.showSuccess(context, l10n.sucursalCrearExito);
      context.push('/organizacion/sucursales/${creada.id}');
    } else {
      RisegFeedback.showError(context, l10n.sucursalCrearError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(sucursalesListControllerProvider);
    final notifier = ref.read(sucursalesListControllerProvider.notifier);

    if (state.errorCarga != null && state.sucursales.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.sucursalesListadoCargaErrorTitulo,
        message: l10n.sucursalesListadoCargaErrorMensaje,
        primaryAction: RisegButton(
          key: const Key('sucursales_boton_reintentar'),
          label: l10n.sucursalesListadoBotonReintentar,
          onPressed: notifier.reintentarCarga,
        ),
      );
    }

    final filas = state.sucursalesFiltradas;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.sucursalesListadoTitulo,
            description: l10n.sucursalesListadoSubtitulo,
            primaryAction: RisegButton(
              key: const Key('sucursales_boton_nueva'),
              label: l10n.sucursalesListadoBotonNueva,
              icon: Icons.add,
              onPressed: () => _mostrarDialogoAlta(state.tipos),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 320,
            child: RisegSearchField(
              hint: l10n.sucursalesListadoBuscarHint,
              controller: _busquedaController,
              onChanged: notifier.actualizarBusqueda,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando)
            const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl), child: Center(child: CircularProgressIndicator()))
          else if (filas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(
                child: RisegEmptyState(
                  icon: Icons.storefront_outlined,
                  title: l10n.sucursalesListadoVacioTitulo,
                  message: l10n.sucursalesListadoVacioMensaje,
                  primaryAction: state.busqueda.trim().isEmpty
                      ? RisegButton(
                          label: l10n.sucursalesListadoBotonNueva,
                          icon: Icons.add,
                          onPressed: () => _mostrarDialogoAlta(state.tipos),
                        )
                      : null,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columnas = constraints.maxWidth >= 1200 ? 3 : (constraints.maxWidth >= 700 ? 2 : 1);
                const espacio = AppSpacing.lg;
                final anchoTarjeta = (constraints.maxWidth - espacio * (columnas - 1)) / columnas;

                return Wrap(
                  spacing: espacio,
                  runSpacing: espacio,
                  children: [
                    for (final s in filas)
                      SizedBox(
                        width: anchoTarjeta,
                        child: _SucursalCard(
                          sucursal: s,
                          tipoNombre: state.nombreTipo(s.tipoSucursalId),
                          ubicacion: state.ubicacionDe(s.id),
                          personal: state.personalPorSucursal[s.id] ?? 0,
                          servicios: state.serviciosPorSucursal[s.id] ?? 0,
                          onTap: () => context.push('/organizacion/sucursales/${s.id}'),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SucursalCard extends StatelessWidget {
  const _SucursalCard({
    required this.sucursal,
    required this.tipoNombre,
    required this.ubicacion,
    required this.personal,
    required this.servicios,
    required this.onTap,
  });

  final SucursalData sucursal;
  final String? tipoNombre;
  final String? ubicacion;
  final int personal;
  final int servicios;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final operando = sucursal.estadoOperativo == EstadoOperativoSucursal.operando.name;

    return RisegCard(
      variant: RisegCardVariant.interactive,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, color: colors.accentText, size: AppSizes.iconMd),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sucursal.nombre.toUpperCase(),
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              RisegStatusBadge(
                label: operando ? l10n.sucursalEstadoOperativoOperando : l10n.sucursalEstadoOperativoCerradaTemporalmente,
                tone: operando ? RisegStatusTone.success : RisegStatusTone.warning,
              ),
            ],
          ),
          if (tipoNombre != null) ...[
            const SizedBox(height: 2),
            Text(tipoNombre!, style: AppTypography.body.copyWith(color: colors.textMuted)),
          ],
          const SizedBox(height: 2),
          Text(sucursal.codigo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.place_outlined, size: AppSizes.iconSm, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  ubicacion ?? l10n.sucursalUbicacionNoRegistrada,
                  style: AppTypography.caption.copyWith(
                    color: colors.textMuted,
                    fontStyle: ubicacion == null ? FontStyle.italic : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _MiniEstadistica(valor: personal, etiqueta: l10n.sucursalMetricaPersonal),
              const SizedBox(width: AppSpacing.lg),
              _MiniEstadistica(valor: servicios, etiqueta: l10n.sucursalMetricaServicios),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(l10n.sucursalVerSucursal, style: AppTypography.caption.copyWith(color: colors.accentText)),
              Icon(Icons.chevron_right, size: AppSizes.iconSm, color: colors.accentText),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniEstadistica extends StatelessWidget {
  const _MiniEstadistica({required this.valor, required this.etiqueta});

  final int valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$valor', style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
        const SizedBox(width: AppSpacing.xxs),
        Text(etiqueta, style: AppTypography.caption.copyWith(color: colors.textMuted)),
      ],
    );
  }
}

/// Contenido del diálogo de alta — un `StatefulWidget` propio (no una
/// pareja `TextEditingController` + `StatefulBuilder` en el método que
/// abre el diálogo) para que el `TextEditingController` se cree y se
/// destruya con el ciclo de vida real del widget. Deshacerlo a mano justo
/// después de `await RisegDialog.showForm(...)` competía con la animación
/// de salida del diálogo (el campo podía seguir montado un frame más),
/// lanzando "TextEditingController usado después de dispose()" — un bug
/// real encontrado al escribir las pruebas de este flujo.
class _AltaSucursalForm extends StatefulWidget {
  const _AltaSucursalForm({required this.tipos, required this.onNombreChanged, required this.onTipoChanged});

  final List<CatalogoItem> tipos;
  final ValueChanged<String> onNombreChanged;
  final ValueChanged<String?> onTipoChanged;

  @override
  State<_AltaSucursalForm> createState() => _AltaSucursalFormState();
}

class _AltaSucursalFormState extends State<_AltaSucursalForm> {
  final _nombreController = TextEditingController();
  String? _tipoSeleccionado;

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.sucursalAltaCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: widget.onNombreChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.sucursalAltaCampoTipo,
          value: _tipoSeleccionado,
          items: [for (final tipo in widget.tipos) RisegSelectItem(value: tipo.id, label: tipo.nombre)],
          onChanged: (valor) {
            setState(() => _tipoSeleccionado = valor);
            widget.onTipoChanged(valor);
          },
        ),
      ],
    );
  }
}
