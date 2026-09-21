import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/finanzas/presentation/pagos/pagos_list_screen.dart' show formatoCentavosPago;

import '../../../domain/analitica/obtener_analisis_pagos_usecase.dart';
import '../../widgets/cobranza_labels.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Sección Pagos.
///
/// El objeto proyectado es el **Pago**, nunca la aplicación: un pago de
/// $50,000 repartido entre dos facturas es una fila de $50,000 con dos
/// documentos cubiertos, jamás dos filas que suman $100,000.
class SeccionPagos extends StatelessWidget {
  const SeccionPagos({required this.pagos, super.key});

  final AnalisisPagos pagos;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.date_range, size: AppSizes.iconSm, color: colors.textMuted),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                l10n.reportesAvisoEnElPeriodo,
                style: AppTypography.caption.copyWith(color: colors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        RisegKpiGrid(
          children: [
            RisegStatCard(
              label: l10n.reportesPagosRecibidos,
              value: '${pagos.pagosRecibidos}',
              icon: Icons.payments_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesPagosImporteRecibido,
              value: formatoCentavosPago(pagos.importeRecibido),
              icon: Icons.savings_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesPagosClientes,
              value: '${pagos.clientesQuePagaron}',
              icon: Icons.groups_outlined,
            ),
            RisegStatCard(
              label: l10n.reportesPagosImporteAplicado,
              value: formatoCentavosPago(pagos.importeAplicado),
              icon: Icons.playlist_add_check,
            ),
            RisegStatCard(
              label: l10n.reportesPagosPorAplicar,
              value: formatoCentavosPago(pagos.importePorAplicar),
              icon: Icons.pending_actions_outlined,
              deltaTone: pagos.importePorAplicar > 0 ? RisegStatusTone.warning : null,
            ),
            RisegStatCard(
              label: l10n.reportesPagosComplementoPendiente,
              value: '${pagos.complementosPendientes}',
              icon: Icons.receipt_outlined,
              deltaTone: pagos.complementosPendientes > 0 ? RisegStatusTone.error : RisegStatusTone.success,
            ),
            RisegStatCard(
              label: l10n.reportesPagosComplementoRegistrado,
              value: '${pagos.complementosRegistrados}',
              icon: Icons.verified_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.reportesPagosDetalleTitulo, style: AppTypography.heading3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        RisegTableBase<PagoProyectado>(
          rows: pagos.pagos,
          emptyState: RisegEmptyState(
            icon: Icons.payments_outlined,
            title: l10n.reportesSinDatosTitulo,
            message: l10n.reportesPagosVacia,
          ),
          // Al Pago real, por id. El destino vuelve a verificar permiso.
          onRowTap: (p) => context.go('/finanzas/pagos/${p.pago.id}'),
          columns: [
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaFecha,
              width: 110,
              cellBuilder: (p) => Text(_formatoFecha.format(p.pago.fechaPago)),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaFolio,
              width: 120,
              cellBuilder: (p) => Text(p.pago.folioPago),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaCliente,
              width: 180,
              cellBuilder: (p) => Text(p.clienteNombre, overflow: TextOverflow.ellipsis),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaImporte,
              width: 130,
              alignment: TextAlign.right,
              cellBuilder: (p) => Text(
                formatoCentavosPago(p.importe),
                style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary),
              ),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaAplicado,
              width: 130,
              alignment: TextAlign.right,
              cellBuilder: (p) => Text(formatoCentavosPago(p.aplicado)),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaDocumentos,
              width: 190,
              // Los documentos cubiertos viven aquí, dentro de la fila
              // del Pago — nunca como filas propias.
              cellBuilder: (p) => Text(
                p.aplicaciones.isEmpty
                    ? '—'
                    : p.aplicaciones.map((a) => a.folioDocumento ?? '—').join(', '),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaCuenta,
              width: 160,
              cellBuilder: (p) => Text(p.cuentaFinancieraNombre ?? '—', overflow: TextOverflow.ellipsis),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaForma,
              width: 120,
              cellBuilder: (p) => Text(p.pago.formaPago),
            ),
            RisegColumn<PagoProyectado>(
              label: l10n.reportesPagosColumnaComplemento,
              width: 120,
              cellBuilder: (p) => RisegStatusBadge(
                label: etiquetaEstadoComplemento(l10n, p.estadoComplemento),
                tone: tonoEstadoComplemento(p.estadoComplemento),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
