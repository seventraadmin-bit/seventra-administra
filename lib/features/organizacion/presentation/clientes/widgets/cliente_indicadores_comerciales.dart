import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/presentation/clientes/cliente_comercial_resumen.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_comercial_section.dart' show formatoCentavos;

/// Indicadores comerciales del Cliente (Etapa 16, ficha comercial) —
/// Servicios activos | Personal asignado | Importe mensual contratado,
/// las tres derivadas de [ClienteComercialResumen] (ya resuelto sin
/// N+1 por `clienteComercialResumenProvider`). Se reorganiza 3→1
/// columnas según el ancho disponible, mismo criterio ya usado en
/// Empresa/Área.
class ClienteIndicadoresComerciales extends StatelessWidget {
  const ClienteIndicadoresComerciales({required this.resumen, super.key});

  final ClienteComercialResumen resumen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tarjetas = [
      RisegStatCard(
        label: l10n.clienteIndicadorServiciosActivos,
        value: '${resumen.serviciosActivos}',
        dense: true,
      ),
      RisegStatCard(
        label: l10n.clienteIndicadorPersonalAsignado,
        value: '${resumen.personalTotal}',
        dense: true,
      ),
      RisegStatCard(
        label: l10n.clienteIndicadorImporteMensual,
        value: formatoCentavos(resumen.importeMensualTotal),
        dense: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < AppBreakpoints.compact
            ? 1
            : (constraints.maxWidth < AppBreakpoints.medium ? 2 : 3);
        final ancho = (constraints.maxWidth - (AppSpacing.md * (columnas - 1))) / columnas;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final tarjeta in tarjetas) SizedBox(width: ancho, child: tarjeta)],
        );
      },
    );
  }
}
