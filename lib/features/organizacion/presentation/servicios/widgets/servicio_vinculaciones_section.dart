import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_expediente_data.dart';

/// Sección "Vinculaciones" de Servicio — una sola tarjeta (Etapa 4F.2,
/// ajuste final de Marlon) con dos subsecciones internas:
///
/// - Relaciones externas: Cliente (solo lectura), Entidad fiscal,
///   Responsable del Cliente.
/// - Relaciones internas: Responsable interno, Sucursal administrativa.
///
/// Una sola tarjeta deliberadamente, no dos separadas — aquí mismo
/// convivirán futuras vinculaciones (contratos, configuraciones,
/// coberturas, etc.) sin reestructurar la pantalla.
class ServicioVinculacionesSection extends StatelessWidget {
  const ServicioVinculacionesSection({
    required this.datos,
    required this.deshabilitado,
    required this.onAsignarEntidadFiscal,
    required this.onQuitarEntidadFiscal,
    required this.onAsignarResponsableCliente,
    required this.onQuitarResponsableCliente,
    required this.onEditarResponsableInterno,
    required this.onAsignarSucursalAdministrativa,
    required this.onQuitarSucursalAdministrativa,
    super.key,
  });

  final ServicioExpedienteData datos;
  final bool deshabilitado;
  final VoidCallback onAsignarEntidadFiscal;
  final VoidCallback onQuitarEntidadFiscal;
  final VoidCallback onAsignarResponsableCliente;
  final VoidCallback onQuitarResponsableCliente;
  final VoidCallback onEditarResponsableInterno;
  final VoidCallback onAsignarSucursalAdministrativa;
  final VoidCallback onQuitarSucursalAdministrativa;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RisegFormSection(
      title: l10n.servicioSeccionVinculacionesTitulo,
      children: [
        Text(l10n.servicioSubseccionRelacionesExternas, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        RisegFieldGrid(
          children: [
            _VinculacionRow(
              key: const Key('servicio_vinculacion_cliente'),
              label: l10n.servicioVinculacionCliente,
              valor: datos.cliente.nombreComercial,
            ),
            _VinculacionRow(
              key: const Key('servicio_vinculacion_entidad_fiscal'),
              label: l10n.servicioVinculacionEntidadFiscal,
              valor: datos.entidadFiscal?.razonSocial,
              archivada: datos.entidadFiscalArchivada,
              etiquetaArchivada: l10n.entidadFiscalEstadoArchivada,
              advertencia: l10n.servicioAdvertenciaEntidadFiscalArchivada,
              deshabilitado: deshabilitado,
              onAsignar: onAsignarEntidadFiscal,
              onQuitar: datos.entidadFiscal == null ? null : onQuitarEntidadFiscal,
            ),
            _VinculacionRow(
              key: const Key('servicio_vinculacion_responsable_cliente'),
              label: l10n.servicioVinculacionResponsableCliente,
              valor: datos.responsableCliente?.nombre,
              archivada: datos.responsableClienteArchivado,
              etiquetaArchivada: l10n.servicioEstadoArchivadoMasculino,
              advertencia: l10n.servicioAdvertenciaResponsableClienteArchivado,
              deshabilitado: deshabilitado,
              onAsignar: onAsignarResponsableCliente,
              onQuitar: datos.responsableCliente == null ? null : onQuitarResponsableCliente,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.servicioSubseccionRelacionesInternas, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        RisegFieldGrid(
          children: [
            _VinculacionRow(
              key: const Key('servicio_vinculacion_responsable_interno'),
              label: l10n.servicioVinculacionResponsableInterno,
              valor: datos.servicio.responsableInterno,
              deshabilitado: deshabilitado,
              onAsignar: onEditarResponsableInterno,
              botonAsignarLabel: l10n.servicioVinculacionBotonEditar,
            ),
            _VinculacionRow(
              key: const Key('servicio_vinculacion_sucursal_administrativa'),
              label: l10n.servicioVinculacionSucursalAdministrativa,
              valor: datos.sucursalAdministrativa?.nombre,
              archivada: datos.sucursalAdministrativaArchivada,
              etiquetaArchivada: l10n.entidadFiscalEstadoArchivada,
              advertencia: l10n.servicioAdvertenciaSucursalAdministrativaArchivada,
              deshabilitado: deshabilitado,
              onAsignar: onAsignarSucursalAdministrativa,
              onQuitar: datos.sucursalAdministrativa == null ? null : onQuitarSucursalAdministrativa,
            ),
          ],
        ),
      ],
    );
  }
}

/// Fila compacta de una vinculación — etiqueta, valor (o "Sin asignar"),
/// badge de archivado si aplica, y acciones Asignar/Editar + Quitar.
/// Si [onAsignar] es `null`, la fila es de solo lectura (caso Cliente).
class _VinculacionRow extends StatelessWidget {
  const _VinculacionRow({
    required this.label,
    required this.valor,
    this.archivada = false,
    this.advertencia,
    this.deshabilitado = false,
    this.onAsignar,
    this.onQuitar,
    this.botonAsignarLabel,
    this.etiquetaArchivada,
    super.key,
  });

  final String label;
  final String? valor;
  final bool archivada;
  final String? etiquetaArchivada;
  final String? advertencia;
  final bool deshabilitado;
  final VoidCallback? onAsignar;
  final VoidCallback? onQuitar;
  final String? botonAsignarLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final tieneValor = valor != null && valor!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    Text(
                      tieneValor ? valor! : l10n.servicioVinculacionSinAsignar,
                      style: AppTypography.body.copyWith(
                        color: tieneValor ? colors.textPrimary : colors.textMuted,
                        fontStyle: tieneValor ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                    if (archivada && etiquetaArchivada != null)
                      RisegStatusBadge(label: etiquetaArchivada!, tone: RisegStatusTone.neutral),
                  ],
                ),
                if (archivada && advertencia != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      advertencia!,
                      style: AppTypography.caption.copyWith(color: colors.warning),
                    ),
                  ),
              ],
            ),
          ),
          if (onAsignar != null)
            IconButton(
              tooltip: botonAsignarLabel ?? (tieneValor ? l10n.servicioVinculacionBotonEditar : l10n.servicioVinculacionBotonAsignar),
              icon: Icon(tieneValor ? Icons.edit_outlined : Icons.add_circle_outline, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: deshabilitado ? null : onAsignar,
            ),
          if (onQuitar != null)
            IconButton(
              tooltip: l10n.servicioVinculacionBotonQuitar,
              icon: const Icon(Icons.link_off, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: deshabilitado ? null : onQuitar,
            ),
        ],
      ),
    );
  }
}
