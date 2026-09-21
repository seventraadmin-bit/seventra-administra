import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/dashboard/presentation/dashboard_controller.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import 'antiguedad_texto.dart';
import 'empleados_list_screen.dart' show empleadoNombreCompleto;
import 'personal_activo_controller.dart';
import 'package:riseg_one/features/personal/domain/plantilla_personal.dart' show AsignacionEstructural;

import 'personal_activo_state.dart' show DestinoFiltro, FiltroPlantilla, TipoDestinoFiltro;
import 'widgets/crear_empleado_dialog.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// "Plantilla activa" (Etapa 15, rediseño de Personal/Bajas — segunda
/// pasada visual) — vista predeterminada de Empleados. Un empleado dado
/// de baja NUNCA aparece aquí (pasa de inmediato a Bajas).
class PersonalActivoListScreen extends ConsumerStatefulWidget {
  const PersonalActivoListScreen({this.filtroInicialSinAsignar = false, super.key});

  /// Deep-link real desde el Dashboard (Etapa 20, "Sin asignar") —
  /// aplica el filtro ya existente `FiltroPlantilla.sinAsignar`
  /// una sola vez al entrar, nunca en cada rebuild.
  final bool filtroInicialSinAsignar;

  @override
  ConsumerState<PersonalActivoListScreen> createState() => _PersonalActivoListScreenState();
}

class _PersonalActivoListScreenState extends ConsumerState<PersonalActivoListScreen> {
  final _buscarCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.filtroInicialSinAsignar) {
      Future.microtask(
        () => ref.read(personalActivoControllerProvider.notifier).aplicarFiltros(estadoAsignacion: FiltroPlantilla.sinAsignacion),
      );
    }
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final empleadoId = await mostrarDialogoCrearEmpleado(context, ref);
    if (empleadoId == null) return;
    ref.read(personalActivoControllerProvider.notifier).recargar();
    ref.invalidate(dashboardControllerProvider);
    if (mounted) context.push('/personal/empleados/$empleadoId');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final state = ref.watch(personalActivoControllerProvider);
    final notifier = ref.read(personalActivoControllerProvider.notifier);

    if (state.errorCarga != null && state.empleados.isEmpty) {
      return RisegEmptyState(
        icon: Icons.error_outline,
        title: l10n.empleadosListadoCargaErrorTitulo,
        message: l10n.empleadosListadoCargaErrorMensaje,
        primaryAction: RisegButton(label: l10n.empleadosListadoBotonReintentar, onPressed: notifier.reintentarCarga),
      );
    }

    // Etapa 16, evolución visual: hallazgo real — con el Shell completo
    // (barra superior azul + sidebar reales, no una vista aislada) en
    // ventanas angostas Y bajas a la vez, los KPIs/filtros en `Wrap`
    // podían necesitar más líneas de las que cabían junto con la tabla
    // dentro de un `Column` no desplazable ("RenderFlex overflowed").
    // Se vuelve `SingleChildScrollView` a nivel de página — mismo patrón
    // ya usado en Bajas — y la tabla deja de forzarse a `Expanded`:
    // `RisegTableBase` detecta la altura no acotada y usa su propio
    // camino de scroll de página (ver el doc comment de ese componente).
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.personalActivoTitulo,
            primaryAction: RisegButton(
              key: const Key('empleados_boton_registrar'),
              label: l10n.empleadosListadoBotonRegistrar,
              onPressed: ref.watch(permissionServiceProvider).hasCode('personal.crear') ? _registrar : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(width: 190, child: RisegStatCard(dense: true, label: l10n.personalActivoKpiActivo, value: '${state.personalActivo}')),
              SizedBox(width: 190, child: RisegStatCard(dense: true, label: l10n.personalActivoKpiAsignado, value: '${state.personalAsignado}')),
              SizedBox(
                width: 190,
                child: RisegStatCard(
                  dense: true,
                  label: l10n.personalActivoKpiSinAsignar,
                  value: '${state.personalSinAsignar}',
                  deltaTone: state.personalSinAsignar > 0 ? RisegStatusTone.warning : RisegStatusTone.success,
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegStatCard(dense: true, label: l10n.personalActivoKpiPorcentajeAsignado, value: '${state.porcentajeAsignado.round()}%'),
              ),
              // Servicio Y Sucursal a la vez: ni asignado ni sin asignar.
              // Sólo aparece cuando el dato roto existe — nunca se esconde
              // dentro de otro conteo para que el porcentaje se vea mejor.
              if (state.personalInconsistente > 0)
                SizedBox(
                  width: 190,
                  child: RisegStatCard(
                    dense: true,
                    label: l10n.personalActivoKpiInconsistente,
                    value: '${state.personalInconsistente}',
                    deltaTone: RisegStatusTone.warning,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: RisegSearchField(
                  hint: l10n.personalActivoBuscar,
                  controller: _buscarCtrl,
                  onChanged: (valor) => notifier.aplicarFiltros(texto: valor, limpiarTexto: valor.isEmpty),
                ),
              ),
              SizedBox(
                width: 190,
                child: RisegSelect<String?>(
                  label: l10n.empleadosFiltroPuesto,
                  value: state.puestoId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.empleadosFiltroPuestoTodos),
                    for (final p in state.puestos) RisegSelectItem(value: p.id, label: p.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(puestoId: valor, limpiarPuestoId: valor == null),
                ),
              ),
              SizedBox(
                width: 230,
                // Un solo selector para los DOS destinos reales: filtrar
                // sólo por Servicio dejaba invisible a todo el personal
                // administrativo. Los valores son (tipo, id) reales.
                child: RisegSelect<DestinoFiltro?>(
                  label: l10n.personalActivoFiltroAsignacion,
                  value: state.destino,
                  items: [
                    RisegSelectItem(value: null, label: l10n.personalActivoFiltroAsignacionTodas),
                    for (final s in state.servicios)
                      RisegSelectItem(
                        value: (tipo: TipoDestinoFiltro.servicio, id: s.servicio.id),
                        label: s.servicio.nombre,
                      ),
                    for (final s in state.sucursales)
                      RisegSelectItem(
                        value: (tipo: TipoDestinoFiltro.sucursal, id: s.id),
                        label: s.nombre,
                      ),
                    RisegSelectItem(
                      value: (tipo: TipoDestinoFiltro.sinAsignacion, id: null),
                      label: l10n.personalActivoFiltroPlantillaSinAsignacion,
                    ),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(destino: valor, limpiarDestino: valor == null),
                ),
              ),
              SizedBox(
                width: 170,
                child: RisegSelect<String?>(
                  label: l10n.personalActivoFiltroTurno,
                  value: state.turnoId,
                  items: [
                    RisegSelectItem(value: null, label: l10n.empleadosFiltroPuestoTodos),
                    for (final t in state.turnos) RisegSelectItem(value: t.id, label: t.nombre),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(turnoId: valor, limpiarTurnoId: valor == null),
                ),
              ),
              SizedBox(
                width: 180,
                child: RisegSelect<FiltroPlantilla>(
                  label: l10n.personalActivoFiltroPlantilla,
                  value: state.estadoAsignacion,
                  items: [
                    RisegSelectItem(
                      value: FiltroPlantilla.todos,
                      label: l10n.personalActivoFiltroPlantillaTodos,
                    ),
                    RisegSelectItem(
                      value: FiltroPlantilla.operativo,
                      label: l10n.personalActivoFiltroPlantillaOperativo,
                    ),
                    RisegSelectItem(
                      value: FiltroPlantilla.administrativo,
                      label: l10n.personalActivoFiltroPlantillaAdministrativo,
                    ),
                    RisegSelectItem(
                      value: FiltroPlantilla.sinAsignacion,
                      label: l10n.personalActivoFiltroPlantillaSinAsignacion,
                    ),
                  ],
                  onChanged: (valor) => notifier.aplicarFiltros(estadoAsignacion: valor),
                ),
              ),
              RisegButton(
                label: l10n.personalActivoLimpiarFiltros,
                variant: RisegButtonVariant.ghost,
                onPressed: state.hayFiltrosActivos
                    ? () {
                        _buscarCtrl.clear();
                        notifier.limpiarTodosLosFiltros();
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTableBase<EmpleadoData>(
            loading: state.cargando,
            rows: state.visibles,
            onRowTap: (empleado) => context.push('/personal/empleados/${empleado.id}'),
            emptyState: RisegEmptyState(title: l10n.empleadosListadoVacioTitulo, message: l10n.empleadosListadoVacioMensaje),
            hoverColor: colors.accentSoftBg,
            rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
            rowActionsBuilder: (_) => Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
            actionsWidth: 40,
            columns: [
              RisegColumn<EmpleadoData>(
                label: l10n.empleadosColumnaNombre,
                cellBuilder: (e) => RisegEntityIdentity(
                  primario: empleadoNombreCompleto(e),
                  secundario: l10n.personalActivoNumeroEmpleado(e.numeroEmpleado),
                  imagenPath: state.fotografiaPathPorEmpleadoId[e.id],
                ),
              ),
              RisegColumn<EmpleadoData>(
                label: l10n.empleadosColumnaPuesto,
                width: 170,
                cellBuilder: (e) {
                  for (final p in state.puestos) {
                    if (p.id == e.puestoId) return RisegStatusBadge(label: p.nombre, tone: RisegStatusTone.neutral);
                  }
                  return const Text('—');
                },
              ),
              RisegColumn<EmpleadoData>(
                label: l10n.personalActivoColumnaAsignacion,
                // Los dos destinos de la empresa en una sola columna: un
                // operativo se adscribe a un Servicio y un administrativo
                // a una Sucursal. "Sin asignar" SÓLO cuando la
                // clasificación de dominio dice que no hay ningún destino.
                cellBuilder: (e) {
                  final clasificacion = state.clasificacionPorEmpleado[e.id];

                  Widget destino(String nombre, String? subtitulo) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                          if (subtitulo != null) ...[
                            const SizedBox(height: 2),
                            Text(subtitulo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                          ],
                        ],
                      );

                  switch (clasificacion?.asignacion) {
                    case AsignacionEstructural.servicio:
                      final servicioId = clasificacion!.servicioId!;
                      // Ubicación como 2ª línea muted SOLO cuando ya existe
                      // estructurada — nunca un placeholder en esta fila densa.
                      return destino(
                        state.servicioNombrePorId[servicioId] ?? '—',
                        state.ubicacionPorServicioId[servicioId],
                      );
                    case AsignacionEstructural.sucursal:
                      final sucursalId = clasificacion!.sucursalId!;
                      // Mismo tratamiento que el Servicio; si la Sucursal no
                      // tiene dirección capturada, el subtítulo dice de qué
                      // plantilla es el destino, que siempre es cierto.
                      return destino(
                        state.sucursalNombrePorId[sucursalId] ?? '—',
                        state.ubicacionPorSucursalId[sucursalId] ?? l10n.personalActivoAsignacionAdministrativo,
                      );
                    case AsignacionEstructural.inconsistente:
                      return RisegStatusBadge(
                        label: l10n.personalActivoAsignacionInconsistente,
                        tone: RisegStatusTone.warning,
                      );
                    case AsignacionEstructural.sinAsignacion:
                    case null:
                      return RisegStatusBadge(
                        label: l10n.personalActivoSinAsignar,
                        tone: RisegStatusTone.warning,
                      );
                  }
                },
              ),
              RisegColumn<EmpleadoData>(
                label: l10n.personalActivoColumnaTurno,
                width: 130,
                cellBuilder: (e) {
                  final asignacion = state.asignacionPorEmpleado[e.id];
                  final turnoId = asignacion?.turnoId;
                  if (turnoId == null) return const Text('—');
                  final nombre = state.turnoNombrePorId[turnoId];
                  if (nombre == null) return const Text('—');
                  return RisegStatusBadge(label: nombre, tone: RisegStatusTone.neutral);
                },
              ),
              RisegColumn<EmpleadoData>(
                label: l10n.empleadosColumnaFechaIngreso,
                width: 110,
                cellBuilder: (e) => Text(_formatoFecha.format(e.fechaIngreso)),
              ),
              RisegColumn<EmpleadoData>(
                label: l10n.personalActivoColumnaAntiguedad,
                width: 130,
                cellBuilder: (e) => Text(antiguedadTexto(l10n, e)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
