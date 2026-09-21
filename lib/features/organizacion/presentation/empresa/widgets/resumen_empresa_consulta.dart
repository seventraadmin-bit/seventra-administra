import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/tarjeta_fiscal_data.dart' show construirLineasDomicilioFiscal;
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

/// Resumen de Empresa en modo consulta (Etapa 16, tercera pasada
/// visual) — "Información fiscal" + "Contacto" lado a lado, y
/// "Domicilio fiscal" como dirección legible (nunca 9 campos sueltos).
/// Reutiliza `construirLineasDomicilioFiscal` (Etapa 16, Tarjeta
/// fiscal) — mismo formato, nunca una segunda función de formateo.
/// Ningún dato nuevo: es únicamente una representación visual distinta
/// de los mismos campos que ya muestran `DatosGeneralesSection`/
/// `MediosContactoSection`/`DireccionFiscalSection` en modo edición.
class ResumenEmpresaConsulta extends StatefulWidget {
  const ResumenEmpresaConsulta({required this.empresa, required this.direccion, required this.contacto, super.key});

  final EmpresaData empresa;
  final DireccionData? direccion;
  final MedioContactoData? contacto;

  @override
  State<ResumenEmpresaConsulta> createState() => _ResumenEmpresaConsultaState();
}

class _ResumenEmpresaConsultaState extends State<ResumenEmpresaConsulta> {
  bool _mostrarCompleta = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    final infoFiscal = RisegFormSection(
      title: l10n.empresaSeccionInformacionFiscalTitulo,
      grid: true,
      children: [
        CampoConsulta(label: l10n.empresaCampoRazonSocial, value: widget.empresa.razonSocial),
        CampoConsulta(label: l10n.empresaCampoRfc, value: widget.empresa.rfc),
        CampoConsulta(label: l10n.empresaCampoCodigo, value: widget.empresa.codigo),
        // Régimen fiscal deliberadamente ausente: no existe hoy como dato
        // estructurado en `Empresa` (auditado antes de esta pasada) — se
        // documenta como deuda en el reporte final, nunca se inventa un
        // valor ni se muestra un campo vacío para él.
      ],
    );

    final contacto = RisegFormSection(
      title: l10n.empresaSeccionContactoTitulo,
      grid: true,
      children: [
        CampoConsulta(label: l10n.empresaCampoTelefono, value: widget.contacto?.telefono),
        CampoConsulta(label: l10n.empresaCampoCorreo, value: widget.contacto?.correo),
        CampoConsulta(label: l10n.empresaCampoSitioWeb, value: widget.contacto?.sitioWeb),
      ],
    );

    final direccion = widget.direccion;
    final tieneReferenciasAdicionales = direccion?.referencias != null && direccion!.referencias!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < AppBreakpoints.medium) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [infoFiscal, const SizedBox(height: AppSpacing.xl), contacto],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: infoFiscal),
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: contacto),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        RisegFormSection(
          title: l10n.empresaSeccionDireccionFiscalTitulo,
          children: [
            if (direccion == null)
              Text(l10n.organizacionValorPendiente, style: AppTypography.body.copyWith(color: colors.textMuted, fontStyle: FontStyle.italic))
            else ...[
              for (final linea in construirLineasDomicilioFiscal(direccion))
                Text(linea, style: AppTypography.body.copyWith(color: colors.textPrimary)),
              if (tieneReferenciasAdicionales) ...[
                const SizedBox(height: AppSpacing.xs),
                if (!_mostrarCompleta)
                  RisegButton(
                    label: l10n.empresaVerDireccionCompleta,
                    variant: RisegButtonVariant.ghost,
                    size: RisegButtonSize.compact,
                    onPressed: () => setState(() => _mostrarCompleta = true),
                  )
                else
                  Text(direccion.referencias!, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              ],
            ],
          ],
        ),
      ],
    );
  }
}
