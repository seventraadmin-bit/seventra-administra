import 'dart:io';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/copiar_datos_tarjeta_fiscal.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/empresa_expediente_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/generar_tarjeta_fiscal_pdf_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/tarjeta_fiscal_data.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/validar_datos_fiscales_tarjeta.dart';
import 'package:riseg_one/features/organizacion/organizacion_providers.dart';

String etiquetaCampoFiscalFaltante(AppLocalizations l10n, CampoFiscalFaltante campo) {
  return switch (campo) {
    CampoFiscalFaltante.razonSocial => l10n.empresaCampoRazonSocial,
    CampoFiscalFaltante.rfc => l10n.empresaCampoRfc,
    CampoFiscalFaltante.domicilioFiscal => l10n.empresaSeccionDireccionFiscalTitulo,
  };
}

/// Abre la previsualización de la Tarjeta fiscal (Etapa 16) — reutiliza
/// el expediente YA cargado por la pantalla de Empresa, sin una
/// consulta nueva. Devuelve `true` únicamente cuando el usuario, ante
/// datos incompletos, elige "Editar empresa" (la pantalla decide qué
/// hacer con eso); en cualquier otro cierre devuelve `false`.
Future<bool> mostrarDialogoTarjetaFiscal(BuildContext context, EmpresaExpedienteData datos, {String? logoPath}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (_) => TarjetaFiscalDialog(datos: datos, logoPath: logoPath),
  );
  return resultado ?? false;
}

class TarjetaFiscalDialog extends ConsumerStatefulWidget {
  const TarjetaFiscalDialog({required this.datos, this.logoPath, super.key});

  final EmpresaExpedienteData datos;

  /// Ruta del logotipo de la Empresa (Etapa 5B.2).
  final String? logoPath;

  @override
  ConsumerState<TarjetaFiscalDialog> createState() => _TarjetaFiscalDialogState();
}

class _TarjetaFiscalDialogState extends ConsumerState<TarjetaFiscalDialog> {
  bool _generandoPdf = false;

  Future<void> _generarPdf() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _generandoPdf = true);

    // Etapa 5B.2: sin logotipo de reserva. El use case lo toma de la
    // Empresa; si no tiene, la tarjeta se emite sin él.
    final resultado = await ref.read(generarTarjetaFiscalPdfAutorizadoProvider)();
    if (!mounted) return;
    setState(() => _generandoPdf = false);

    switch (resultado) {
      case GenerarTarjetaFiscalPdfExitoso():
        RisegFeedback.showSuccess(context, l10n.tarjetaFiscalPdfExito);
      case GenerarTarjetaFiscalPdfDatosIncompletos():
      case GenerarTarjetaFiscalPdfErrorInesperado():
        RisegFeedback.showError(context, l10n.tarjetaFiscalPdfError);
    }
  }

  void _copiarDatos(TarjetaFiscalData data) {
    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(ClipboardData(text: textoCopiarTarjetaFiscal(data)));
    RisegFeedback.showSuccess(context, l10n.tarjetaFiscalCopiadoExito);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final faltantes = validarDatosFiscalesTarjeta(widget.datos);

    if (faltantes.isNotEmpty) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tarjetaFiscalBloqueadaTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.tarjetaFiscalBloqueadaMensaje, style: AppTypography.body.copyWith(color: colors.textMuted)),
                const SizedBox(height: AppSpacing.sm),
                for (final f in faltantes)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text('•  ${etiquetaCampoFiscalFaltante(l10n, f)}', style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.xs,
                  children: [
                    RisegButton(
                      label: l10n.tarjetaFiscalBotonCerrar,
                      variant: RisegButtonVariant.ghost,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    RisegButton(
                      label: l10n.empresaExpedienteBotonEditar,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = construirTarjetaFiscalData(widget.datos);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.tarjetaFiscalTitulo, style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.md),
              Flexible(child: SingleChildScrollView(child: _TarjetaFiscalPreview(data: data, logoPath: widget.logoPath))),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  RisegButton(
                    label: l10n.tarjetaFiscalBotonCerrar,
                    variant: RisegButtonVariant.ghost,
                    onPressed: _generandoPdf ? null : () => Navigator.of(context).pop(false),
                  ),
                  RisegButton(
                    key: const Key('tarjeta_fiscal_boton_copiar'),
                    label: l10n.tarjetaFiscalBotonCopiar,
                    variant: RisegButtonVariant.secondary,
                    onPressed: _generandoPdf ? null : () => _copiarDatos(data),
                  ),
                  RisegButton(
                    key: const Key('tarjeta_fiscal_boton_pdf'),
                    label: l10n.tarjetaFiscalBotonPdf,
                    loading: _generandoPdf,
                    onPressed: _generarPdf,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Previsualización visual — misma composición de datos que el PDF y
/// "Copiar datos" ([TarjetaFiscalData]), pensada para sentirse como una
/// tarjeta corporativa (encabezado azul institucional + bloques
/// jerarquizados), no como un formulario.
class _TarjetaFiscalPreview extends StatelessWidget {
  const _TarjetaFiscalPreview({required this.data, required this.logoPath});

  /// Ruta del logotipo de la Empresa, o `null`. Sin logotipo la cabecera se
  /// dibuja sólo con el nombre comercial.
  final String? logoPath;

  final TarjetaFiscalData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: colors.accent,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // Etapa 5B.2: el logotipo de la Empresa, si lo tiene. Sin él
                // la vista previa se queda sin imagen — nunca con la de otra
                // Empresa ni con la del producto.
                if (logoPath != null && File(logoPath!).existsSync()) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 32, maxWidth: 80),
                    child: Image.file(File(logoPath!), fit: BoxFit.contain),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    data.nombreComercial,
                    style: AppTypography.bodyStrong.copyWith(color: colors.shellForeground),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _seccion(context, 'DATOS PARA FACTURACIÓN', [
                  _campo(context, 'Razón social', data.razonSocial),
                  const SizedBox(height: AppSpacing.sm),
                  _campo(context, 'RFC', data.rfc),
                ]),
                if (data.domicilioLineas.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _seccion(context, 'DOMICILIO FISCAL', [
                    for (final linea in data.domicilioLineas)
                      Text(linea, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                  ]),
                ],
                if (data.correo != null || data.telefono != null || data.sitioWeb != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _seccion(context, 'CONTACTO', [
                    if (data.correo != null) _campo(context, 'Correo', data.correo!),
                    if (data.telefono != null) ...[const SizedBox(height: AppSpacing.sm), _campo(context, 'Teléfono', data.telefono!)],
                    if (data.sitioWeb != null) ...[const SizedBox(height: AppSpacing.sm), _campo(context, 'Sitio web', data.sitioWeb!)],
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccion(BuildContext context, String titulo, List<Widget> contenido) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: AppTypography.label.copyWith(color: colors.accentText, letterSpacing: 0.6)),
        const SizedBox(height: AppSpacing.xs),
        ...contenido,
      ],
    );
  }

  Widget _campo(BuildContext context, String etiqueta, String valor) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        Text(valor, style: AppTypography.bodyStrong.copyWith(color: colors.textPrimary)),
      ],
    );
  }
}
