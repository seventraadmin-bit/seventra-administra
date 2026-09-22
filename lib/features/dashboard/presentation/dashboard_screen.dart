import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/permissions/permission_service.dart';
import 'package:riseg_one/features/personal/domain/plantilla_personal.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;
import 'package:riseg_one/features/inventario/presentation/movimiento_tipo_label.dart';
import 'package:riseg_one/features/nomina/data/tables/nomina_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/obtener_resumen_tiempos_extra_usecase.dart';
import 'package:riseg_one/features/usuarios/usuarios_providers.dart';

import '../domain/periodo_dashboard.dart';
import '../domain/usecases/obtener_actividad_reciente_usecase.dart';
import '../domain/usecases/obtener_alertas_dashboard_usecase.dart' show umbralUtilizacionAltaTarjeta;
import '../domain/usecases/obtener_cobertura_operativa_usecase.dart';
import '../domain/usecases/obtener_resumen_cobranza_usecase.dart';
import 'dashboard_controller.dart';
import 'dashboard_state.dart';
import 'widgets/grafica_financiera.dart';
import 'widgets/periodo_selector.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Centro de control gerencial (Etapa 13, rediseño Etapa 15) — responde
/// en ~5 segundos: cuántos Servicios activos, cobertura real,
/// vacantes/antigüedad, próxima Nómina, resultado del periodo,
/// cobranza por estatus, y qué requiere atención hoy. Cada zona se
/// deriva de módulos/relaciones reales (nunca una cifra inventada) y se
/// omite por completo si no hay dato autorizado que mostrar.
///
/// [PeriodoDashboard] (cabecera) afecta ingresos/egresos/resultado/
/// gráfica/actividad — NUNCA cobertura/vacantes actuales, que siempre
/// reflejan el estado operativo de hoy (ver `DashboardController`).
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _coberturaKey = GlobalKey();

  void _irACobertura() {
    final ctx = _coberturaKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(dashboardControllerProvider);
    final controller = ref.read(dashboardControllerProvider.notifier);
    final permissionService = ref.watch(permissionServiceProvider);

    final huboAlgunaCarga = state.resumenGeneral != null ||
        state.resumenPersonal != null ||
        state.resumenNomina != null ||
        state.resumenInventario != null ||
        state.resumenVehiculos != null ||
        state.resumenTelefonia != null ||
        state.resumenCobertura != null ||
        state.resumenCobranza != null;

    // Jerarquía ejecutiva (Etapa 20): 1) Estado general (KPIs) — 2)
    // Requiere atención, inmediatamente después de los KPIs — 3)
    // Operación (Cobertura + Personal + Tiempos Extra, snapshot actual)
    // — 4) Finanzas y cobranza (periodo seleccionado) — 5) Actividad
    // reciente. Antes: Cobertura → Financiera/Cobranza → Atención →
    // Personal/Actividad → Tiempos Extra (aislado, ancho completo).
    final secciones = <Widget>[
      _KpiRow(l10n: l10n, state: state, onIrACobertura: _irACobertura),
      _SeccionAtencion(l10n: l10n, state: state),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyedSubtree(key: _coberturaKey, child: _CoberturaOperativaSection(l10n: l10n, resumen: state.resumenCobertura)),
          const SizedBox(height: AppSpacing.xl),
          _DosColumnas(
            izquierda: _construirPersonal(context, l10n, state.personalOperativo, onVacantes: _irACobertura),
            derecha: _construirTiemposExtra(context, l10n, state.resumenTiemposExtra),
          ),
        ],
      ),
      _DosColumnas(
        izquierda: _construirFinanciera(context, l10n, state),
        derecha: _construirCobranza(context, l10n, state.resumenCobranza),
      ),
      if (_construirActividad(context, l10n, state) case final actividad?) actividad,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        key: const Key('dashboard_screen'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegSectionHeader(
            title: l10n.dashboardTitulo,
            description: l10n.dashboardDescripcion,
            primaryAction: _AccesosRapidos(l10n: l10n, permissionService: permissionService),
          ),
          const SizedBox(height: AppSpacing.md),
          if (state.periodo != null) PeriodoSelector(periodo: state.periodo!, onChanged: controller.cambiarPeriodo),
          const SizedBox(height: AppSpacing.lg),
          if (state.cargando && !huboAlgunaCarga)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorCarga != null)
            RisegEmptyState(icon: Icons.error_outline, title: l10n.reportesErrorCargaTitulo, message: state.errorCarga!)
          else
            for (var i = 0; i < secciones.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xl),
              secciones[i],
            ],
        ],
      ),
    );
  }
}

/// Dos columnas ≥ [AppBreakpoints.medium], apiladas debajo — ambos
/// lados son opcionales (`null` = esa mitad no tiene contenido
/// autorizado, nunca un hueco).
class _DosColumnas extends StatelessWidget {
  const _DosColumnas({required this.izquierda, required this.derecha});

  final Widget? izquierda;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    if (izquierda == null && derecha == null) return const SizedBox.shrink();
    if (izquierda == null) return derecha!;
    if (derecha == null) return izquierda!;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.medium) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: izquierda!),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: derecha!),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [izquierda!, const SizedBox(height: AppSpacing.lg), derecha!],
        );
      },
    );
  }
}

/// Los 4 KPI primarios (Parte C) — nunca Existencia total/Asignaciones
/// vigentes/Líneas activas como KPI principal (Parte A).
class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.l10n, required this.state, required this.onIrACobertura});

  final AppLocalizations l10n;
  final DashboardState state;
  final VoidCallback onIrACobertura;

  @override
  Widget build(BuildContext context) {
    final cobertura = state.resumenCobertura;
    final proximaNomina = state.proximaNomina;
    final tarjetas = <Widget>[];

    if (cobertura != null) {
      tarjetas.add(_KpiCardPrincipal(
        label: l10n.dashboardKpiServiciosActivos,
        value: '${cobertura.serviciosActivos}',
        icon: Icons.handshake_outlined,
        onTap: () => context.go('/comercial/servicios'),
      ));

      final porcentaje = cobertura.porcentajeGlobal;
      final toneCobertura = porcentaje >= 100
          ? RisegStatusTone.success
          : porcentaje >= 80
              ? RisegStatusTone.warning
              : RisegStatusTone.error;
      tarjetas.add(_KpiCardPrincipal(
        label: l10n.dashboardKpiCobertura,
        value: '${porcentaje.round()}%',
        delta: cobertura.totalRequerido == 0
            ? l10n.dashboardKpiSinRequerimientos
            : l10n.dashboardKpiCoberturaDetalle(cobertura.totalCubierto, cobertura.totalRequerido),
        tone: toneCobertura,
        icon: Icons.shield_outlined,
        onTap: onIrACobertura,
      ));

      final vacantes = cobertura.totalVacantes;
      final toneVacantes = vacantes == 0 ? RisegStatusTone.success : toneCobertura;
      final antiguedadDias = cobertura.vacanteMasAntigua?.inDays;
      tarjetas.add(_KpiCardPrincipal(
        label: l10n.dashboardKpiVacantes,
        value: '$vacantes',
        delta: vacantes == 0
            ? l10n.dashboardKpiCoberturaCompleta
            : (antiguedadDias != null ? l10n.dashboardKpiVacanteMasAntigua(antiguedadDias) : null),
        tone: toneVacantes,
        icon: Icons.person_search_outlined,
        onTap: onIrACobertura,
      ));
    }

    if (state.resumenNomina != null || proximaNomina != null) {
      final hoy = DateTime.now();
      RisegStatusTone toneNomina = RisegStatusTone.neutral;
      String? delta;
      if (proximaNomina != null) {
        final diasParaPago = DateTime(proximaNomina.fechaPagoOrdinaria.year, proximaNomina.fechaPagoOrdinaria.month, proximaNomina.fechaPagoOrdinaria.day)
            .difference(DateTime(hoy.year, hoy.month, hoy.day))
            .inDays;
        toneNomina = diasParaPago < 0
            ? RisegStatusTone.error
            : diasParaPago <= 3
                ? RisegStatusTone.warning
                : RisegStatusTone.info;
        delta = l10n.dashboardKpiProximaNominaFecha(_formatoFecha.format(proximaNomina.fechaPagoOrdinaria));
      }
      // Etapa 16, evolución visual: un texto largo ("Sin nómina
      // pendiente") en el slot `value` (heading1 44px, sin overflow/
      // maxLines) rompía la proporción de la tarjeta frente a sus
      // hermanas numéricas en el mismo `Wrap`. El slot `delta` ya tiene
      // `ellipsis`/tipografía menor — el texto descriptivo va ahí, y
      // `value` conserva un placeholder corto y neutro.
      final hayProximaNomina = proximaNomina != null && state.proximaNominaTotal != null;
      tarjetas.add(_KpiCardPrincipal(
        label: l10n.dashboardKpiProximaNomina,
        value: hayProximaNomina ? formatoCentavosPago(state.proximaNominaTotal!) : '—',
        delta: hayProximaNomina ? delta : l10n.dashboardKpiSinNominaPendiente,
        tone: toneNomina,
        icon: Icons.payments_outlined,
        // `push` (nunca `go`): preserva el Dashboard en la pila para
        // volver con el botón de regreso real (Parte 9).
        onTap: proximaNomina != null ? () => context.push('/personal/nomina/${proximaNomina.id}') : null,
      ));
    }

    // 5º KPI ejecutivo (Etapa 20): Saldo disponible de caja —
    // `ObtenerPosicionDeCajaUseCase`, snapshot actual, nunca afectado
    // por el periodo (mismo criterio que Cobertura). Auditado contra
    // Resultado operativo/Total por cobrar/Vencido: esos ya se
    // muestran en la sección Finanzas y Cobranza más abajo — repetirlos
    // aquí violaría "no repetir cifras que ya están inmediatamente
    // visibles". El saldo de caja es el único de los 4 candidatos que
    // no se muestra en ningún otro lugar del Dashboard.
    final posicionCaja = state.posicionCaja;
    if (posicionCaja != null) {
      final configurada = posicionCaja.configurada;
      final saldoNegativo = configurada && posicionCaja.saldoDisponible < 0;
      tarjetas.add(_KpiCardPrincipal(
        label: l10n.dashboardKpiSaldoCaja,
        value: configurada ? formatoCentavosPago(posicionCaja.saldoDisponible) : '—',
        delta: configurada ? null : l10n.dashboardKpiSaldoCajaNoConfigurada,
        tone: !configurada
            ? RisegStatusTone.neutral
            : (saldoNegativo ? RisegStatusTone.error : RisegStatusTone.success),
        icon: Icons.account_balance_wallet_outlined,
        // Suma de N cuentas — nunca un id único que inventar; navega a
        // la lista real (Parte 9: nunca navegar por coincidencia).
        onTap: () => context.push('/finanzas/cuentas-financieras'),
      ));
    }

    // 6º KPI ejecutivo (Etapa "Dashboard: posición financiera") —
    // Crédito disponible de TDC, agregado vía
    // `ObtenerCreditoDisponibleTarjetasUseCase` (misma fórmula
    // `creditoDisponibleTarjeta` que ya usa el listado de Deudas y
    // crédito). Deliberadamente NUNCA sumado con `posicionCaja`: caja y
    // crédito son conceptos financieros distintos.
    final creditoDisponible = state.creditoDisponibleTarjetas;
    if (creditoDisponible != null) {
      final hayTarjetas = creditoDisponible.hayTarjetas;
      tarjetas.add(_KpiCardPrincipal(
        label: l10n.dashboardKpiCreditoDisponible,
        value: hayTarjetas ? formatoCentavosPago(creditoDisponible.totalDisponible) : '—',
        delta: hayTarjetas ? null : l10n.dashboardKpiCreditoDisponibleSinTarjetas,
        tone: hayTarjetas ? RisegStatusTone.info : RisegStatusTone.neutral,
        icon: Icons.credit_card_outlined,
        onTap: () => context.push('/finanzas/deudas-y-credito'),
      ));
    }

    if (tarjetas.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final tarjeta in tarjetas) SizedBox(width: 270, child: tarjeta),
      ],
    );
  }
}

/// KPI principal del Dashboard (Etapa 15 v1.1, Parte 1: "los KPIs
/// necesitan mucho más protagonismo") — número grande (44px), icono
/// grande, borde de color por tono cuando aplica. Deliberadamente NO es
/// [RisegStatCard]: esa prominencia es específica de los 4 indicadores
/// de cabecera del Dashboard, no un cambio al componente compartido que
/// usan 40+ pantallas del resto del sistema.
class _KpiCardPrincipal extends StatelessWidget {
  const _KpiCardPrincipal({required this.label, required this.value, this.delta, this.tone, this.icon, this.onTap});

  final String label;
  final String value;
  final String? delta;
  final RisegStatusTone? tone;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final colorTono = switch (tone) {
      RisegStatusTone.success => colors.success,
      RisegStatusTone.warning => colors.warning,
      RisegStatusTone.error => colors.error,
      RisegStatusTone.info => colors.info,
      RisegStatusTone.neutral || null => null,
    };

    return RisegCard(
      variant: onTap == null ? RisegCardVariant.standard : RisegCardVariant.interactive,
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: colorTono,
      borderWidth: colorTono != null ? 1.5 : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.label.copyWith(color: colors.textMuted))),
              if (icon != null) Icon(icon, size: AppSizes.iconLg, color: colorTono ?? colors.textMuted),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTypography.heading1.copyWith(fontSize: 44, color: colors.textPrimary)),
          if (delta != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              delta!,
              style: AppTypography.body.copyWith(color: colorTono ?? colors.textMuted, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Cobertura operativa por Servicio (Parte D/E) — presentación
/// adaptativa (Etapa 20, Parte 4): un Servicio completo ocupa una
/// tarjeta compacta (nombre + % + check), nunca la misma barra de
/// progreso grande que uno con faltantes — la excepción debe llamar la
/// atención, el estado normal debe ser compacto. Los Servicios con
/// faltantes se muestran primero (más vacantes → vacante más antigua),
/// con el detalle completo (barra + desglose por línea cuando aplica,
/// Parte E: "no dejar que 3 empleados de un perfil cubran
/// artificialmente 3 posiciones de otro perfil").
class _CoberturaOperativaSection extends StatelessWidget {
  const _CoberturaOperativaSection({required this.l10n, required this.resumen});

  final AppLocalizations l10n;
  final ResumenCoberturaOperativa? resumen;

  @override
  Widget build(BuildContext context) {
    if (resumen == null) return const SizedBox.shrink();
    final colors = context.colors;

    final incompletos = resumen!.servicios.where((s) => !s.completo).toList()
      ..sort((a, b) {
        final porVacantes = b.vacantes.compareTo(a.vacantes);
        if (porVacantes != 0) return porVacantes;
        final antiguedadA = a.vacanteMasAntigua;
        final antiguedadB = b.vacanteMasAntigua;
        if (antiguedadA == null && antiguedadB == null) return 0;
        if (antiguedadA == null) return 1;
        if (antiguedadB == null) return -1;
        return antiguedadB.compareTo(antiguedadA);
      });
    final completos = resumen!.servicios.where((s) => s.completo).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardCoberturaTitulo, style: AppTypography.heading2),
        if (resumen!.servicios.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.dashboardCoberturaServiciosCompletos(resumen!.serviciosCompletos, resumen!.serviciosActivos),
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (resumen!.servicios.isEmpty)
          RisegEmptyState(
            icon: Icons.shield_outlined,
            title: l10n.dashboardCoberturaVaciaTitulo,
            message: l10n.dashboardCoberturaVaciaMensaje,
          )
        else
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final servicio in incompletos) SizedBox(width: 340, child: _TarjetaCoberturaServicio(l10n: l10n, servicio: servicio)),
              for (final servicio in completos) SizedBox(width: 200, child: _TarjetaCoberturaCompleta(l10n: l10n, servicio: servicio)),
            ],
          ),
      ],
    );
  }
}

/// Servicio 100% cubierto (Etapa 20) — mínimo espacio posible: nombre,
/// porcentaje, cubiertos/requeridos y un check, sin barra de progreso
/// (redundante en 100%) ni desglose por línea (nunca aporta nada
/// cuando ya está completo). Nunca 9 tarjetas grandes idénticas.
class _TarjetaCoberturaCompleta extends StatelessWidget {
  const _TarjetaCoberturaCompleta({required this.l10n, required this.servicio});

  final AppLocalizations l10n;
  final CoberturaServicio servicio;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RisegCard(
      variant: RisegCardVariant.interactive,
      onTap: () => context.push('/comercial/servicios/${servicio.servicioId}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: AppSizes.iconMd, color: colors.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  servicio.servicioNombre,
                  style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${servicio.porcentaje.round()}% · ${servicio.cubierto}/${servicio.requerido}',
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta "centro de control" por Servicio (Etapa 15 v1.1, Parte 2) —
/// reemplaza la fila de tabla anterior. Siempre muestra el desglose por
/// línea/perfil cuando hay más de una (Parte E: nunca dejar que un
/// perfil sobrante cubra artificialmente a otro).
class _TarjetaCoberturaServicio extends StatelessWidget {
  const _TarjetaCoberturaServicio({required this.l10n, required this.servicio});

  final AppLocalizations l10n;
  final CoberturaServicio servicio;

  RisegStatusTone get _tono {
    if (servicio.completo) return RisegStatusTone.success;
    return servicio.porcentaje >= 80 ? RisegStatusTone.warning : RisegStatusTone.error;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tono = _tono;
    final colorTono = switch (tono) {
      RisegStatusTone.success => colors.success,
      RisegStatusTone.warning => colors.warning,
      RisegStatusTone.error => colors.error,
      RisegStatusTone.info => colors.info,
      RisegStatusTone.neutral => colors.neutralText,
    };
    final dias = servicio.vacanteMasAntigua?.inDays;

    return RisegCard(
      variant: RisegCardVariant.interactive,
      // `push` (nunca `go`): preserva el Dashboard en la pila (Parte 9).
      onTap: () => context.push('/comercial/servicios/${servicio.servicioId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(servicio.servicioNombre, style: AppTypography.heading3.copyWith(color: colors.textPrimary))),
              if (dias != null) RisegStatusBadge(label: l10n.dashboardCoberturaDiasAbreviado(dias), tone: tono),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${servicio.porcentaje.round()}% · ${servicio.cubierto}/${servicio.requerido} cubiertos',
            style: AppTypography.bodyStrong.copyWith(color: colorTono),
          ),
          const SizedBox(height: AppSpacing.xs),
          RisegProgressBar(porcentaje: servicio.porcentaje, tone: tono),
          if (servicio.lineas.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: AppSpacing.xs),
            for (final linea in servicio.lineas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(linea.puestoNombre, style: AppTypography.caption.copyWith(color: colors.textMuted))),
                    Text(
                      '${linea.cubierto}/${linea.requerido}',
                      style: AppTypography.bodyStrong.copyWith(color: linea.completo ? colors.success : colors.error),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AccesosRapidos extends StatelessWidget {
  const _AccesosRapidos({required this.l10n, required this.permissionService});

  final AppLocalizations l10n;
  final PermissionService permissionService;

  @override
  Widget build(BuildContext context) {
    final botones = <Widget>[
      if (permissionService.hasCode('personal.crear'))
        RisegButton(
          label: l10n.dashboardAccesoAltaPersonal,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          icon: Icons.person_add_outlined,
          onPressed: () => context.go('/personal/empleados'),
        ),
      if (permissionService.hasCode('compras.crear'))
        RisegButton(
          label: l10n.dashboardAccesoRegistrarCompra,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          icon: Icons.shopping_cart_outlined,
          onPressed: () => context.go('/compras/nueva'),
        ),
      if (permissionService.hasCode('nomina.crear'))
        RisegButton(
          label: l10n.dashboardAccesoGenerarNomina,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          icon: Icons.payments_outlined,
          onPressed: () => context.go('/personal/nomina'),
        ),
      if (permissionService.hasCode('inventario.ver'))
        RisegButton(
          label: l10n.dashboardAccesoInventario,
          variant: RisegButtonVariant.ghost,
          size: RisegButtonSize.compact,
          icon: Icons.inventory_2_outlined,
          onPressed: () => context.go('/inventario/articulos'),
        ),
    ];

    if (botones.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: botones);
  }
}

/// Bandeja de excepciones "Requiere atención" (Parte K) — distinta del
/// Centro de notificaciones: aquí solo panorama operativo accionable,
/// reutilizando exactamente los datos ya cargados (nunca una segunda
/// consulta paralela).
/// Un renglón de "Requiere atención" — Etapa 15 v1.1, Parte 3: lista
/// compacta priorizada (antes: tarjetas grandes que ocupaban demasiado
/// espacio). `tono` determina el color del punto/valor; los renglones
/// más urgentes (vacantes/CxC vencida) van primero por construcción del
/// orden de inserción abajo.
class _ItemAtencion {
  const _ItemAtencion({required this.texto, required this.valor, required this.tono, this.onTap});

  final String texto;
  final String valor;
  final RisegStatusTone tono;
  final VoidCallback? onTap;
}

class _SeccionAtencion extends StatelessWidget {
  const _SeccionAtencion({required this.l10n, required this.state});

  final AppLocalizations l10n;
  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = <_ItemAtencion>[];

    // Vacantes abiertas por línea/perfil (Parte K, ejemplo principal) —
    // la antigüedad usada es la del Servicio completo (única
    // granularidad rastreada hoy; ver limitación documentada en
    // `ObtenerCoberturaOperativaUseCase`).
    for (final servicio in state.resumenCobertura?.servicios ?? const []) {
      if (servicio.completo) continue;
      final dias = servicio.vacanteMasAntigua?.inDays;
      for (final linea in servicio.lineas) {
        if (linea.completo) continue;
        items.add(_ItemAtencion(
          texto: '${servicio.servicioNombre} — ${linea.puestoNombre} sin cubrir',
          valor: dias != null ? l10n.dashboardCoberturaDiasAbreviado(dias) : '',
          tono: RisegStatusTone.error,
          // Etapa 20 (Parte 9): navega al expediente real del
          // Servicio por ID — antes solo hacía scroll a Cobertura.
          onTap: () => context.push('/comercial/servicios/${servicio.servicioId}'),
        ));
      }
    }

    final documentosPorEmitir = state.alertas?.documentosPorEmitirPendientes;
    if (documentosPorEmitir != null && documentosPorEmitir.isNotEmpty) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaDocumentosPorEmitir,
        valor: l10n.dashboardAlertaDocumentosPorEmitirDetalle(documentosPorEmitir.length),
        tono: RisegStatusTone.warning,
        // Con contexto: la Agenda abre en el modo Pendientes y muestra
        // exactamente los documentos que esta alerta acaba de contar. Sin
        // el parámetro, abría en el mes actual y podía mostrar cero.
        onTap: () => context.push('/comercial/agenda?filtro=pendientes'),
      ));
    }

    final cxc = state.alertas?.cxcVencida;
    if (cxc != null && cxc.cantidadCuentas > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaCxcVencida,
        valor: formatoCentavosPago(cxc.montoTotal),
        tono: RisegStatusTone.error,
        onTap: () => context.go('/finanzas/cuentas-por-cobrar'),
      ));
    }

    // Etapa 19B — tarjeta con utilización alta o pago próximo (ya
    // excluye saldoActual == 0 desde el use case: nada accionable ahí).
    // Etapa "Dashboard: posición financiera" — un ciclo vencido (posible
    // solo tras conciliar `tarjetaVencimientoCubiertoHasta`) tiene
    // prioridad sobre utilización alta, que a su vez tiene prioridad
    // sobre pago próximo — un solo ítem por tarjeta, nunca 2 filas.
    for (final tarjeta in state.alertas?.tarjetasEnAlerta ?? const []) {
      final utilizacionAlta = tarjeta.utilizacion != null && tarjeta.utilizacion! >= umbralUtilizacionAltaTarjeta;
      final String texto;
      final String valor;
      final RisegStatusTone tono;
      if (tarjeta.vencida) {
        texto = l10n.dashboardAlertaTarjetaPagoVencido(tarjeta.nombre);
        valor = tarjeta.proximaFechaPago != null ? _formatoFecha.format(tarjeta.proximaFechaPago!) : '';
        tono = RisegStatusTone.error;
      } else if (utilizacionAlta) {
        texto = l10n.dashboardAlertaTarjetaUtilizacionAlta(tarjeta.nombre);
        valor = l10n.dashboardAlertaTarjetaUtilizacionValor(tarjeta.utilizacion!.round());
        tono = RisegStatusTone.error;
      } else {
        texto = l10n.dashboardAlertaTarjetaPagoProximo(tarjeta.nombre);
        valor = l10n.dashboardAlertaTarjetaDiasValor(tarjeta.diasParaPago ?? 0);
        tono = RisegStatusTone.warning;
      }
      items.add(_ItemAtencion(
        texto: texto,
        valor: valor,
        tono: tono,
        onTap: () => context.push('/finanzas/deudas-y-credito/${tarjeta.deudaId}'),
      ));
    }

    final proximaNomina = state.proximaNomina;
    if (proximaNomina != null) {
      final hoy = DateTime.now();
      final diasParaPago = DateTime(
        proximaNomina.fechaPagoOrdinaria.year,
        proximaNomina.fechaPagoOrdinaria.month,
        proximaNomina.fechaPagoOrdinaria.day,
      ).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
      if (diasParaPago <= 3) {
        items.add(_ItemAtencion(
          texto: '${l10n.dashboardKpiProximaNomina} — ${proximaNomina.folio}',
          valor: _formatoFecha.format(proximaNomina.fechaPagoOrdinaria),
          tono: diasParaPago < 0 ? RisegStatusTone.error : RisegStatusTone.warning,
          onTap: () => context.push('/personal/nomina/${proximaNomina.id}'),
        ));
      }
    }

    final inventario = state.resumenInventario;
    if (inventario != null && inventario.danadosPerdidos > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaInventarioDanado,
        valor: '${inventario.danadosPerdidos}',
        tono: RisegStatusTone.error,
        onTap: () => context.go('/inventario/articulos'),
      ));
    }
    if (inventario != null && inventario.descuentosPendientes > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaDescuentosPendientes,
        valor: '${inventario.descuentosPendientes}',
        tono: RisegStatusTone.warning,
        onTap: () => context.go('/inventario/articulos'),
      ));
    }

    final empleadosBajaConPendiente = state.alertas?.empleadosBajaConPendiente;
    if (empleadosBajaConPendiente != null && empleadosBajaConPendiente.isNotEmpty) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaEmpleadosBajaPendiente,
        valor: '${empleadosBajaConPendiente.length}',
        tono: RisegStatusTone.error,
        onTap: () => context.go('/personal/empleados'),
      ));
    }

    final vehiculos = state.resumenVehiculos;
    if (vehiculos != null && vehiculos.mantenimientosVencidos > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaMantenimientoVencido,
        valor: '${vehiculos.mantenimientosVencidos}',
        tono: RisegStatusTone.error,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }
    if (vehiculos != null && vehiculos.mantenimientosProximos > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaMantenimientoProximo,
        valor: '${vehiculos.mantenimientosProximos}',
        tono: RisegStatusTone.warning,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }
    if (vehiculos != null && vehiculos.documentosVencidos > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaDocumentoVencido,
        valor: '${vehiculos.documentosVencidos}',
        tono: RisegStatusTone.error,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }
    if (vehiculos != null && vehiculos.documentosPorVencer > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaDocumentoProximo,
        valor: '${vehiculos.documentosPorVencer}',
        tono: RisegStatusTone.warning,
        onTap: () => context.go('/vehiculos/alertas'),
      ));
    }

    final telefonia = state.resumenTelefonia;
    final lineasSuspendidas = telefonia?.lineasPorEstatus['suspendida'] ?? 0;
    if (telefonia != null && lineasSuspendidas > 0) {
      items.add(_ItemAtencion(
        texto: l10n.dashboardAlertaLineasSuspendidas,
        valor: '$lineasSuspendidas',
        tono: RisegStatusTone.warning,
        onTap: () => context.go('/telefonia/lineas'),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardSeccionAtencion, style: AppTypography.heading2),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          RisegCard(
            variant: RisegCardVariant.subtle,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: AppSizes.iconMd, color: colors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.dashboardSinPendientesTitulo, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                      Text(l10n.dashboardSinPendientesMensaje, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          RisegCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: colors.borderSubtle),
                  _FilaAtencion(item: items[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FilaAtencion extends StatelessWidget {
  const _FilaAtencion({required this.item});

  final _ItemAtencion item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final colorTono = switch (item.tono) {
      RisegStatusTone.success => colors.success,
      RisegStatusTone.warning => colors.warning,
      RisegStatusTone.error => colors.error,
      RisegStatusTone.info => colors.info,
      RisegStatusTone.neutral => colors.neutralText,
    };

    final fila = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: colorTono, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(item.texto, style: AppTypography.body.copyWith(color: colors.textPrimary), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: AppSpacing.sm),
          Text(item.valor, style: AppTypography.bodyStrong.copyWith(color: colorTono)),
        ],
      ),
    );

    if (item.onTap == null) return fila;
    return InkWell(onTap: item.onTap, child: fila);
  }
}

/// `null` cuando no hay ningún dato financiero autorizado que mostrar —
/// el llamador la omite por completo (nunca una sección vacía).
Widget? _construirFinanciera(BuildContext context, AppLocalizations l10n, DashboardState state) {
  final general = state.resumenGeneral;
  if (general == null) return null;

  final resultado = general.resultadoOperativo;
  final ingresos = general.totalIngresos;
  // El Dashboard muestra la MISMA cifra de gasto que Reportes y que
  // Finanzas: gasto operativo, no el total crudo de Egresos.
  final egresos = general.gastoOperativo;
  final compras = general.totalComprasPeriodo;
  final nominaPagada = general.totalNominaPagadaPeriodo;
  if (resultado == null && ingresos == null && egresos == null && compras == null && nominaPagada == null) {
    return null;
  }

  final colors = context.colors;
  final positivo = (resultado ?? 0) >= 0;
  final tono = positivo ? colors.success : colors.error;
  final tonoBg = positivo ? colors.successBg : colors.errorBg;
  final formatoPorcentaje = NumberFormat('0.0', 'es_MX');

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardResultadoTitulo, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      RisegCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (resultado != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(color: tonoBg, shape: BoxShape.circle),
                    child: Icon(Icons.account_balance_outlined, size: AppSizes.iconMd, color: tono),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.reportesGeneralResultadoOperativo, style: AppTypography.label.copyWith(color: colors.textMuted)),
                        Text(formatoCentavosPago(resultado), style: AppTypography.heading1.copyWith(color: tono)),
                        if (ingresos != null && ingresos > 0)
                          Text(
                            l10n.dashboardMargenOperativo(formatoPorcentaje.format(resultado / ingresos * 100)),
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            if (ingresos != null || egresos != null) ...[
              if (resultado != null) ...[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: colors.borderSubtle),
                const SizedBox(height: AppSpacing.md),
              ],
              Row(
                children: [
                  if (ingresos != null)
                    Expanded(
                      child: _MetricaFinancieraSecundaria(icon: Icons.trending_up, label: l10n.reportesGeneralIngresos, valor: formatoCentavosPago(ingresos)),
                    ),
                  if (ingresos != null && egresos != null) const SizedBox(width: AppSpacing.lg),
                  if (egresos != null)
                    Expanded(
                      child: _MetricaFinancieraSecundaria(icon: Icons.trending_down, label: l10n.reportesGeneralGastoOperativo, valor: formatoCentavosPago(egresos)),
                    ),
                ],
              ),
            ],
            if (state.serieFinanciera != null && state.serieFinanciera!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.dashboardGraficaTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              GraficaFinanciera(puntos: state.serieFinanciera!),
            ],
            if (compras != null || nominaPagada != null) ...[
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.xs,
                children: [
                  if (compras != null) _MetricaFinancieraTerciaria(label: l10n.reportesGeneralCompras, valor: formatoCentavosPago(compras)),
                  if (nominaPagada != null) _MetricaFinancieraTerciaria(label: l10n.reportesGeneralNominaPagada, valor: formatoCentavosPago(nominaPagada)),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _MetricaFinancieraSecundaria extends StatelessWidget {
  const _MetricaFinancieraSecundaria({required this.icon, required this.label, required this.valor});

  final IconData icon;
  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconSm, color: colors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTypography.label.copyWith(color: colors.textMuted)),
              Text(valor, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Métricas de Tiempos Extra (cobertura operativa por ausencia, pedido
/// explícito de Marlon: "cuántos tiempos extra, en qué servicio, gasto,
/// etc.") — mismo estilo que `_construirFinanciera`. Etapa 20: ahora
/// vive integrado en "Operación" (`_DosColumnas` junto a Personal, en
/// vez de aislado a ancho completo al final) — `null` cuando no hay
/// nada que mostrar, mismo criterio que Financiera/Cobranza, para que
/// `_DosColumnas` le ceda el ancho completo a Personal cuando
/// corresponda.
Widget? _construirTiemposExtra(BuildContext context, AppLocalizations l10n, ResumenTiemposExtraDetalle? resumen) {
  if (resumen == null || resumen.totalRegistros == 0) return null;

  final colors = context.colors;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardTiemposExtraTitulo, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      RisegCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _MetricaFinancieraSecundaria(
                    icon: Icons.schedule_outlined,
                    label: l10n.dashboardTiemposExtraTotalRegistros,
                    valor: '${resumen.totalRegistros}',
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: _MetricaFinancieraSecundaria(
                    icon: Icons.account_balance_wallet_outlined,
                    label: l10n.dashboardTiemposExtraGastoTotal,
                    valor: formatoCentavosPago(resumen.gastoTotal),
                  ),
                ),
              ],
            ),
            if (resumen.porServicio.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.dashboardTiemposExtraPorServicio, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final fila in resumen.porServicio.take(5))
                    _MetricaFinancieraTerciaria(
                      label: l10n.dashboardTiemposExtraServicioCantidad(fila.servicioNombre, fila.cantidad),
                      valor: formatoCentavosPago(fila.gastoTotal),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _MetricaFinancieraTerciaria extends StatelessWidget {
  const _MetricaFinancieraTerciaria({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label · $valor', style: AppTypography.body.copyWith(color: colors.textPrimary)),
        Text(AppLocalizations.of(context)!.reportesGeneralIndicadorInformativo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
      ],
    );
  }
}

/// `null` cuando Cobranza no está autorizada (Parte I/J) — clasifica
/// exclusivamente vía `ResumenCobranza`, nunca un estado paralelo. Etapa
/// 15 v1.1, Parte 6: donut en vez de barra lineal + tabla compacta
/// Estado/Días.
Widget? _construirCobranza(BuildContext context, AppLocalizations l10n, ResumenCobranza? resumen) {
  if (resumen == null) return null;
  final colors = context.colors;

  final categorias = [
    (l10n.dashboardCobranzaPagado, resumen.pagado, colors.success, colors.successBg),
    (l10n.dashboardCobranzaEnProceso, resumen.enProceso, colors.info, colors.infoBg),
    (l10n.dashboardCobranzaProximoAVencer, resumen.proximoAVencer, colors.warning, colors.warningBg),
    (l10n.dashboardCobranzaVencido, resumen.vencido, colors.error, colors.errorBg),
  ];

  final totalDocumentos = categorias.fold<int>(0, (acc, c) => acc + c.$2.cantidad);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardCobranzaTitulo, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      RisegCard(
        child: InkWell(
          onTap: () => context.go('/finanzas/cuentas-por-cobrar'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.dashboardCobranzaTotalPorCobrar, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: AppSpacing.xxs),
              Text(formatoCentavosPago(resumen.totalPorCobrar), style: AppTypography.heading1.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CustomPaint(
                      painter: _DonutCobranzaPainter(
                        valores: [for (final c in categorias) c.$2.cantidad],
                        colores: [for (final c in categorias) c.$3],
                        colorFondo: colors.surfaceSunken,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$totalDocumentos', style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final c in categorias)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Container(width: 10, height: 10, decoration: BoxDecoration(color: c.$3, shape: BoxShape.circle)),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    c.$1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.body.copyWith(color: colors.textPrimary),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                // Etapa 16, evolución visual: hallazgo real —
                                // en ventanas angostas (~500px) el importe
                                // desbordaba ("RenderFlex overflowed by 22
                                // pixels"). `Flexible`+`ellipsis` corrige de
                                // raíz sin tocar el dato ni su formato.
                                Flexible(
                                  child: c == categorias[3] && c.$2.cantidad == 0
                                      ? Text(
                                          l10n.dashboardCobranzaSinVencidos,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.caption.copyWith(color: colors.success),
                                        )
                                      : Text(
                                          l10n.dashboardCobranzaCantidadImporte(c.$2.cantidad, formatoCentavosPago(c.$2.importe)),
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.data.copyWith(color: colors.textPrimary),
                                        ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(child: Text(l10n.dashboardCobranzaTablaEstado, style: AppTypography.label.copyWith(color: colors.textMuted))),
                  Text(l10n.dashboardCobranzaTablaDias, style: AppTypography.label.copyWith(color: colors.textMuted)),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  Expanded(child: Text(l10n.dashboardCobranzaProximoAVencer, style: AppTypography.body.copyWith(color: colors.textPrimary))),
                  Text(
                    resumen.diasProximoMasCercano != null ? '${resumen.diasProximoMasCercano}' : l10n.dashboardCobranzaTablaSinDatos,
                    style: AppTypography.bodyStrong.copyWith(color: colors.warning),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text(l10n.dashboardCobranzaVencido, style: AppTypography.body.copyWith(color: colors.textPrimary))),
                  Text(
                    '${resumen.diasVencidoMasUrgente}',
                    style: AppTypography.bodyStrong.copyWith(color: resumen.diasVencidoMasUrgente > 0 ? colors.error : colors.success),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _DonutCobranzaPainter extends CustomPainter {
  _DonutCobranzaPainter({required this.valores, required this.colores, required this.colorFondo});

  final List<int> valores;
  final List<Color> colores;
  final Color colorFondo;

  @override
  void paint(Canvas canvas, Size size) {
    final total = valores.fold<int>(0, (a, b) => a + b);
    final centro = size.center(Offset.zero);
    final radio = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: centro, radius: radio - 6);
    const grosor = 12.0;

    if (total == 0) {
      canvas.drawArc(rect, 0, 6.28319, false, Paint()
        ..color = colorFondo
        ..style = PaintingStyle.stroke
        ..strokeWidth = grosor);
      return;
    }

    var inicio = -1.5707963267948966; // -90°, empieza arriba
    for (var i = 0; i < valores.length; i++) {
      if (valores[i] == 0) continue;
      final barrido = (valores[i] / total) * 6.28318530718;
      canvas.drawArc(
        rect,
        inicio,
        barrido,
        false,
        Paint()
          ..color = colores[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = grosor
          ..strokeCap = StrokeCap.butt,
      );
      inicio += barrido;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutCobranzaPainter oldDelegate) {
    return oldDelegate.valores != valores || oldDelegate.colores != colores;
  }
}

/// `null` cuando Personal no está autorizado (Parte M) — nunca mezcla
/// "sin asignar" con "vacante": son hechos independientes.
///
/// Etapa "Plantilla operativa vs. administrativa": la sección prioriza
/// la OPERACIÓN. Las 5 mini-tarjetas grandes responden las preguntas
/// gerenciales reales (¿cuántos operativos tengo?, ¿está cubierta mi
/// operación?, ¿a quién le falta Servicio?, ¿qué tan rápido cubro?,
/// ¿cuánta rotación tengo?), y la plantilla administrativa aparece
/// abajo en una línea compacta — existe y se ve, pero no compite por
/// atención con la operación ni contamina sus porcentajes.
///
/// El % de asignación operativa se calcula contra la PROPIA plantilla
/// operativa, nunca contra el total de la empresa: ese denominador
/// equivocado era el bug del 94%.
Widget? _construirPersonal(BuildContext context, AppLocalizations l10n, PersonalOperativoDashboard? personal, {required VoidCallback onVacantes}) {
  if (personal == null) return null;
  final colors = context.colors;
  final formatoPromedio = NumberFormat('0.0', 'es_MX');
  final formatoRotacion = NumberFormat('0.0', 'es_MX');
  final promedio = personal.promedioDiasCobertura;
  final operativa = personal.operativa;
  final administrativa = personal.administrativa;
  final rotacion = personal.rotacionOperativa;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardPersonalTituloOperativo, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          _MiniStatCard(
            icon: Icons.groups_outlined,
            iconColor: colors.info,
            valor: '${operativa.activos}',
            label: l10n.dashboardPersonalActivos,
            onTap: () => context.push('/personal/empleados?filtro=operativo'),
          ),
          _MiniStatCard(
            icon: Icons.person_pin_circle_outlined,
            iconColor: colors.success,
            valor: '${operativa.porcentajeAsignados.round()}%',
            label: l10n.dashboardPersonalAsignados,
            onTap: () => context.push('/personal/empleados?filtro=operativo'),
          ),
          _MiniStatCard(
            icon: Icons.person_off_outlined,
            iconColor: operativa.sinAsignar > 0 ? colors.warning : colors.textMuted,
            valor: '${operativa.sinAsignar}',
            label: l10n.dashboardPersonalSinAsignar,
            // Etapa 20 (Parte 5): deep-link real con el filtro ya
            // aplicado, en vez de aterrizar en la lista sin filtrar.
            onTap: () => context.push('/personal/empleados?filtro=sinAsignacion'),
          ),
          _MiniStatCard(
            icon: Icons.schedule_outlined,
            iconColor: colors.error,
            valor: promedio != null ? l10n.dashboardPersonalPromedioCoberturaDias(formatoPromedio.format(promedio.inHours / 24)) : l10n.dashboardPersonalPromedioCoberturaSinDatos,
            label: l10n.dashboardPersonalPromedioCobertura,
            onTap: onVacantes,
          ),
          _MiniStatCard(
            icon: Icons.sync_alt_outlined,
            iconColor: colors.warning,
            valor: rotacion == null
                ? l10n.dashboardPersonalRotacionSinDatos
                : l10n.dashboardPersonalRotacionValor(formatoRotacion.format(rotacion)),
            label: l10n.dashboardPersonalRotacion,
            onTap: () => context.push('/personal/empleados?filtro=operativo'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      // Aclaración discreta de semántica (punto 13 del pedido): las
      // cifras de plantilla son de HOY; rotación y cobertura miran el
      // periodo elegido. Sin esto, un filtro de "esta semana" haría
      // leer los activos como si fueran del periodo.
      Text(
        l10n.dashboardPersonalNotaSemantica,
        style: AppTypography.caption.copyWith(color: colors.textMuted),
      ),
      const SizedBox(height: AppSpacing.md),
      _PlantillaAdministrativaCompacta(
        administrativa: administrativa,
        inconsistentes: personal.inconsistentes,
      ),
    ],
  );
}

/// Plantilla administrativa en una sola línea (Etapa "Plantilla
/// operativa vs. administrativa") — deliberadamente sin el peso visual
/// de la operación: responde "¿cuánta estructura interna tengo?" sin
/// robarle espacio a "¿está cubierta mi operación?".
///
/// Las inconsistencias Servicio+Sucursal se muestran aquí cuando
/// existen, nunca se ocultan para que los porcentajes se vean mejor.
class _PlantillaAdministrativaCompacta extends StatelessWidget {
  const _PlantillaAdministrativaCompacta({required this.administrativa, required this.inconsistentes});

  final ConteoPlantilla administrativa;
  final int inconsistentes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    // `Column` de piezas que a su vez envuelven, en vez de un `Wrap`
    // horizontal de bloques rígidos: a 500px el título y el resumen no
    // caben en la misma línea, y un `Row` de ancho intrínseco dentro de
    // un `Wrap` se desborda en vez de partirse (RenderFlex de 30px,
    // detectado por la prueba responsive).
    return RisegCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 18, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.dashboardPersonalTituloAdministrativo,
                  style: AppTypography.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.dashboardPersonalAdministrativoResumen(
              administrativa.activos,
              administrativa.asignados,
              administrativa.sinAsignar,
            ),
            style: AppTypography.body.copyWith(color: colors.textMuted),
          ),
          if (inconsistentes > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            RisegStatusBadge(
              label: l10n.dashboardPersonalInconsistentes(inconsistentes),
              tone: RisegStatusTone.error,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({required this.icon, required this.iconColor, required this.valor, required this.label, this.onTap});

  final IconData icon;
  final Color iconColor;
  final String valor;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 150,
      child: RisegCard(
        variant: onTap == null ? RisegCardVariant.standard : RisegCardVariant.interactive,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizes.iconLg, color: iconColor),
            const SizedBox(height: AppSpacing.xs),
            Text(valor, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
            Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Un renglón de la Actividad reciente unificada — presentación pura,
/// nunca persistida. `fecha` es siempre la única precisión real
/// disponible en el dominio de origen (nunca se inventa una hora).
class _ActividadItem {
  const _ActividadItem({
    required this.icon,
    required this.titulo,
    required this.detalle,
    required this.fecha,
    this.tono = RisegStatusTone.info,
    this.valor,
    this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String detalle;
  final DateTime fecha;

  /// Color del punto de la línea de tiempo (Etapa 15 v1.1, Parte 7) —
  /// heurística por tipo de evento: éxito/cobro = success, alta/cobertura
  /// = success, baja/vacante/daño = error o warning, resto = info.
  final RisegStatusTone tono;
  final String? valor;
  final VoidCallback? onTap;
}

/// "Hace X minutos/horas" / "Ayer" / fecha absoluta — Etapa 15 v1.1,
/// Parte 7: la Actividad reciente ahora es un Timeline y necesita
/// tiempo relativo para los eventos de hoy/ayer (más allá de eso, la
/// fecha absoluta sigue siendo más útil que "hace 5 días").
String _formatoRelativoActividad(AppLocalizations l10n, DateTime fecha, DateTime ahora) {
  final diferencia = ahora.difference(fecha);
  if (diferencia.inMinutes < 1) return l10n.dashboardActividadHaceMinutos(0);
  if (diferencia.inMinutes < 60) return l10n.dashboardActividadHaceMinutos(diferencia.inMinutes);
  final mismoDia = fecha.year == ahora.year && fecha.month == ahora.month && fecha.day == ahora.day;
  if (mismoDia) return l10n.dashboardActividadHaceHoras(diferencia.inHours);
  final ayer = ahora.subtract(const Duration(days: 1));
  final esAyer = fecha.year == ayer.year && fecha.month == ayer.month && fecha.day == ayer.day;
  if (esAyer) return l10n.dashboardActividadAyer;
  return _formatoFecha.format(fecha);
}

const _limiteActividad = 10;

/// "Ver detalle" de un renglón agrupado de Actividad reciente (Etapa
/// 20, Parte 7) — nunca pierde los folios/cantidades originales, solo
/// los oculta hasta que el usuario los pide; no hay un destino único
/// al que navegar (son N registros distintos), así que esto reemplaza
/// una navegación incorrecta, nunca la sustituye.
Future<void> _mostrarDetalleActividadAgrupada(
  BuildContext context,
  AppLocalizations l10n, {
  required String titulo,
  required List<(String, String)> filas,
}) {
  final colors = context.colors;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.md),
              for (final fila in filas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fila.$1,
                          style: AppTypography.body.copyWith(color: colors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(fila.$2, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: RisegButton(
                  label: l10n.dashboardActividadDetalleBotonCerrar,
                  variant: RisegButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// `null` cuando ninguna fuente de actividad está autorizada.
Widget? _construirActividad(BuildContext context, AppLocalizations l10n, DashboardState state) {
  final huboAlgunaFuente =
      state.actividad != null || state.resumenPersonal != null || state.resumenNomina != null || state.resumenVehiculos != null;
  if (!huboAlgunaFuente) return null;

  final items = <_ActividadItem>[];

  for (final c in state.actividad?.comprasRecientes ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.shopping_cart_outlined,
      titulo: l10n.dashboardActividadItemCompra,
      detalle: '${c.folioCompra} · ${c.proveedor ?? '—'}',
      fecha: c.fecha,
      tono: RisegStatusTone.info,
      onTap: () => context.push('/compras/${c.id}'),
    ));
  }
  // Pagos — Etapa 20, Parte 7: agrupa EXCLUSIVAMENTE cuando 2+ pagos
  // comparten el mismo Cliente Y el mismo día calendario (nunca
  // clientes o días distintos entre sí) — "5 pagos registrados ·
  // SPORTIUM · $97,962.00 · Ayer" en vez de 5 filas casi idénticas.
  // Los folios/montos originales se conservan íntegros para "Ver
  // detalle" — la agrupación es únicamente de presentación.
  final pagosPorGrupo = <String, List<PagoReciente>>{};
  for (final p in state.actividad?.pagosRecientes ?? const []) {
    final dia = DateTime(p.pago.fechaPago.year, p.pago.fechaPago.month, p.pago.fechaPago.day);
    (pagosPorGrupo['${p.pago.clienteId}|$dia'] ??= []).add(p);
  }
  for (final grupo in pagosPorGrupo.values) {
    if (grupo.length == 1) {
      final p = grupo.single;
      items.add(_ActividadItem(
        icon: Icons.payments_outlined,
        titulo: l10n.dashboardActividadItemPago,
        detalle: '${p.pago.folioPago} · ${p.clienteNombre}',
        fecha: p.pago.fechaPago,
        valor: formatoCentavosPago(p.pago.montoTotal),
        tono: RisegStatusTone.success,
      ));
      continue;
    }
    final fechaMasReciente = grupo.map((p) => p.pago.fechaPago).reduce((a, b) => a.isAfter(b) ? a : b);
    final total = grupo.fold<int>(0, (s, p) => s + p.pago.montoTotal);
    items.add(_ActividadItem(
      icon: Icons.payments_outlined,
      titulo: l10n.dashboardActividadPagosAgrupados(grupo.length),
      detalle: '${grupo.first.clienteNombre} · ${l10n.dashboardActividadVerDetalle}',
      fecha: fechaMasReciente,
      valor: formatoCentavosPago(total),
      tono: RisegStatusTone.success,
      onTap: () => _mostrarDetalleActividadAgrupada(
        context,
        l10n,
        titulo: l10n.dashboardActividadPagosAgrupados(grupo.length),
        filas: [for (final p in grupo) (p.pago.folioPago, formatoCentavosPago(p.pago.montoTotal))],
      ),
    ));
  }

  // Movimientos de Inventario — mismo criterio, pero SOLO para
  // `salidaAsignacion` (el único ejemplo real dado: "4 artículos
  // asignados · 24/08/2026"); nunca se agrupan otros tipos de
  // movimiento sin respaldo explícito.
  final movimientosPorDia = <String, List<MovimientoReciente>>{};
  for (final m in state.actividad?.movimientosRecientes ?? const []) {
    if (m.movimiento.tipoMovimiento != 'salidaAsignacion') {
      items.add(_ActividadItem(
        icon: Icons.swap_horiz_outlined,
        titulo: movimientoTipoLabel(l10n, m.movimiento.tipoMovimiento),
        detalle: m.articuloNombre,
        fecha: m.movimiento.fecha,
        valor: '${m.movimiento.cantidad}',
        tono: RisegStatusTone.neutral,
      ));
      continue;
    }
    final dia = DateTime(m.movimiento.fecha.year, m.movimiento.fecha.month, m.movimiento.fecha.day);
    (movimientosPorDia['$dia'] ??= []).add(m);
  }
  for (final grupo in movimientosPorDia.values) {
    if (grupo.length == 1) {
      final m = grupo.single;
      items.add(_ActividadItem(
        icon: Icons.swap_horiz_outlined,
        titulo: movimientoTipoLabel(l10n, m.movimiento.tipoMovimiento),
        detalle: m.articuloNombre,
        fecha: m.movimiento.fecha,
        valor: '${m.movimiento.cantidad}',
        tono: RisegStatusTone.neutral,
      ));
      continue;
    }
    final fechaMasReciente = grupo.map((m) => m.movimiento.fecha).reduce((a, b) => a.isAfter(b) ? a : b);
    items.add(_ActividadItem(
      icon: Icons.swap_horiz_outlined,
      titulo: l10n.dashboardActividadArticulosAsignados(grupo.length),
      detalle: l10n.dashboardActividadVerDetalle,
      fecha: fechaMasReciente,
      tono: RisegStatusTone.neutral,
      onTap: () => _mostrarDetalleActividadAgrupada(
        context,
        l10n,
        titulo: l10n.dashboardActividadArticulosAsignados(grupo.length),
        filas: [for (final m in grupo) (m.articuloNombre, '${m.movimiento.cantidad}')],
      ),
    ));
  }
  for (final e in state.resumenPersonal?.altasEnPeriodo ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.person_add_outlined,
      titulo: l10n.dashboardActividadItemAltaPersonal,
      detalle: e.nombreCompleto,
      fecha: e.fechaIngreso,
      tono: RisegStatusTone.success,
      onTap: () => context.push('/personal/empleados/${e.id}'),
    ));
  }
  for (final b in state.resumenPersonal?.bajasEnPeriodo ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.person_off_outlined,
      titulo: l10n.dashboardActividadItemBajaPersonal,
      detalle: b.nombreCompleto,
      fecha: b.fechaBaja,
      tono: RisegStatusTone.warning,
      onTap: () => context.push('/personal/empleados/${b.empleadoId}'),
    ));
  }
  for (final n in state.resumenNomina?.nominas ?? const []) {
    final pagada = n.nomina.estatus == EstatusNomina.pagada.name;
    items.add(_ActividadItem(
      icon: Icons.badge_outlined,
      titulo: pagada ? l10n.dashboardActividadItemNominaPagada : l10n.dashboardActividadItemNomina,
      detalle: n.nomina.folio,
      fecha: n.nomina.fechaFinPeriodo,
      valor: formatoCentavosPago(n.totalGenerado),
      tono: pagada ? RisegStatusTone.success : RisegStatusTone.info,
      onTap: () => context.push('/personal/nomina/${n.nomina.id}'),
    ));
  }
  for (final m in state.resumenVehiculos?.detalleMantenimientos ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.build_outlined,
      titulo: l10n.dashboardActividadItemMantenimiento,
      detalle: m.vehiculoLabel,
      fecha: m.registro.fecha,
      tono: RisegStatusTone.warning,
    ));
  }
  for (final r in state.actividad?.recargasRecientes ?? const []) {
    items.add(_ActividadItem(
      icon: Icons.sim_card_outlined,
      titulo: l10n.dashboardActividadItemRecarga,
      detalle: r.lineaCodigo,
      fecha: r.recarga.fecha,
      valor: formatoCentavosPago(r.recarga.importe),
      tono: RisegStatusTone.info,
    ));
  }
  for (final v in state.actividad?.vacantesRecientes ?? const []) {
    items.add(_ActividadItem(
      icon: v.abierta ? Icons.person_search_outlined : Icons.person_add_alt_1_outlined,
      titulo: v.abierta ? l10n.dashboardActividadItemVacanteAbierta : l10n.dashboardActividadItemVacanteCubierta,
      detalle: v.servicioNombre,
      fecha: v.fecha,
      tono: v.abierta ? RisegStatusTone.error : RisegStatusTone.success,
    ));
  }

  items.sort((a, b) => b.fecha.compareTo(a.fecha));
  final truncados = items.take(_limiteActividad).toList();

  final colors = context.colors;
  final ahora = DateTime.now();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l10n.dashboardSeccionActividad, style: AppTypography.heading2),
      const SizedBox(height: AppSpacing.sm),
      if (truncados.isEmpty)
        Text(l10n.dashboardActividadVacia, style: AppTypography.body.copyWith(color: colors.textMuted))
      else
        RisegCard(
          child: Column(
            children: [
              for (var i = 0; i < truncados.length; i++)
                _FilaActividadTimeline(
                  item: truncados[i],
                  esUltimo: i == truncados.length - 1,
                  textoRelativo: _formatoRelativoActividad(l10n, truncados[i].fecha, ahora),
                ),
            ],
          ),
        ),
    ],
  );
}

/// Renglón de Actividad reciente como Timeline (Etapa 15 v1.1, Parte 7)
/// — punto de color por tono + línea vertical conectora, en vez de la
/// lista de filas plana anterior.
class _FilaActividadTimeline extends StatelessWidget {
  const _FilaActividadTimeline({required this.item, required this.esUltimo, required this.textoRelativo});

  final _ActividadItem item;
  final bool esUltimo;
  final String textoRelativo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final colorTono = switch (item.tono) {
      RisegStatusTone.success => colors.success,
      RisegStatusTone.warning => colors.warning,
      RisegStatusTone.error => colors.error,
      RisegStatusTone.info => colors.info,
      RisegStatusTone.neutral => colors.neutralText,
    };

    final fila = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.sm + 4),
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colorTono, shape: BoxShape.circle)),
                  if (!esUltimo) Expanded(child: Container(width: 2, color: colors.borderSubtle)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm, bottom: esUltimo ? AppSpacing.sm : AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(item.titulo, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                          Text(item.detalle, style: AppTypography.caption.copyWith(color: colors.textMuted), overflow: TextOverflow.ellipsis),
                          Text(textoRelativo, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                        ],
                      ),
                    ),
                    if (item.valor != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(item.valor!, style: AppTypography.data.copyWith(color: colors.textPrimary)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (item.onTap == null) return fila;
    return InkWell(onTap: item.onTap, child: fila);
  }
}

