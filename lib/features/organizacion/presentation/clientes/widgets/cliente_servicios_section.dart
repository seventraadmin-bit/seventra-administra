import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_comercial_resumen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_comercial_section.dart' show formatoCentavos;

String _nombreEstatusServicio(AppLocalizations l10n, String estatus) {
  return switch (estatus) {
    'activo' => l10n.servicioEstatusActivo,
    'suspendido' => l10n.servicioEstatusSuspendido,
    'terminado' => l10n.servicioEstatusTerminado,
    _ => l10n.servicioEstatusCotizado,
  };
}

RisegStatusTone _tonoEstatusServicio(String estatus) {
  return switch (estatus) {
    'activo' => RisegStatusTone.success,
    'suspendido' => RisegStatusTone.warning,
    'terminado' => RisegStatusTone.neutral,
    _ => RisegStatusTone.info,
  };
}

/// Sección "Servicios" del expediente de Cliente (Etapa 16, ficha
/// comercial) — listado compacto de los Servicios de ESTE Cliente
/// únicamente (nunca el catálogo completo), cada uno con Personal
/// asignado e importe mensual ya resueltos por
/// `clienteComercialResumenProvider`. Navega al expediente del propio
/// Servicio sin duplicar ninguno de sus datos aquí.
class ClienteServiciosSection extends StatelessWidget {
  const ClienteServiciosSection({required this.servicios, super.key});

  final List<ServicioResumenCliente> servicios;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return RisegFormSection(
      title: l10n.clienteSeccionServiciosTitulo,
      children: [
        if (servicios.isEmpty)
          Text(
            l10n.clienteSeccionServiciosVacio,
            style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic),
          )
        else
          for (var i = 0; i < servicios.length; i++) ...[
            if (i > 0) const Divider(height: AppSpacing.lg),
            _FilaServicio(resumen: servicios[i]),
          ],
      ],
    );
  }
}

class _FilaServicio extends StatelessWidget {
  const _FilaServicio({required this.resumen});

  final ServicioResumenCliente resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final item = resumen.item;
    final ubicacion = item.municipioAlcaldia != null && item.estado != null
        ? '${item.municipioAlcaldia}, ${item.estado}'
        : null;

    return InkWell(
      onTap: () => context.push('/comercial/servicios/${item.servicio.id}'),
      borderRadius: AppRadius.mdRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.servicio.nombre, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                  if (ubicacion != null) ...[
                    const SizedBox(height: 2),
                    Text(ubicacion, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                l10n.clienteServiciosPersonalCantidad(resumen.personalAsignado),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(formatoCentavos(resumen.importeMensual), style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
            ),
            RisegStatusBadge(
              label: _nombreEstatusServicio(l10n, item.servicio.estatus),
              tone: _tonoEstatusServicio(item.servicio.estatus),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right, size: AppSizes.iconMd, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
