import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/entidad_fiscal_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/direccion_controllers.dart';

/// Sección "Entidades fiscales" del expediente de Cliente — mismo
/// patrón de lista embebida que Contactos, con dos diferencias
/// deliberadas: (1) muestra también las archivadas (deben poder
/// encontrarse para reactivarlas — a diferencia de Contactos, que solo
/// lista activos); (2) el domicilio fiscal se administra con su propia
/// acción de fila ("Editar domicilio"), nunca junto con razón social/
/// RFC en el mismo envío, para que editar uno nunca arriesgue borrar el
/// otro por no haberlo incluido.
class EntidadesFiscalesSection extends StatelessWidget {
  const EntidadesFiscalesSection({
    required this.entidades,
    required this.deshabilitado,
    required this.onAgregar,
    required this.onEditar,
    required this.onEditarDomicilio,
    required this.onArchivar,
    required this.onReactivar,
    super.key,
  });

  final List<EntidadFiscalConDomicilio> entidades;
  final bool deshabilitado;
  final VoidCallback onAgregar;
  final ValueChanged<EntidadFiscalData> onEditar;
  final ValueChanged<EntidadFiscalConDomicilio> onEditarDomicilio;
  final ValueChanged<EntidadFiscalData> onArchivar;
  final ValueChanged<EntidadFiscalData> onReactivar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RisegFormSection(
      title: l10n.entidadFiscalSeccionTitulo,
      children: [
        RisegButton(
          key: const Key('entidad_fiscal_boton_agregar'),
          label: l10n.entidadFiscalBotonAgregar,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          onPressed: deshabilitado ? null : onAgregar,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final entidad in entidades)
          _EntidadFiscalRow(
            entidad: entidad,
            deshabilitado: deshabilitado,
            onEditar: () => onEditar(entidad.entidadFiscal),
            onEditarDomicilio: () => onEditarDomicilio(entidad),
            onArchivar: () => onArchivar(entidad.entidadFiscal),
            onReactivar: () => onReactivar(entidad.entidadFiscal),
          ),
      ],
    );
  }
}

class _EntidadFiscalRow extends StatelessWidget {
  const _EntidadFiscalRow({
    required this.entidad,
    required this.deshabilitado,
    required this.onEditar,
    required this.onEditarDomicilio,
    required this.onArchivar,
    required this.onReactivar,
  });

  final EntidadFiscalConDomicilio entidad;
  final bool deshabilitado;
  final VoidCallback onEditar;
  final VoidCallback onEditarDomicilio;
  final VoidCallback onArchivar;
  final VoidCallback onReactivar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final data = entidad.entidadFiscal;
    final archivada = data.cicloVidaRegistro == CicloVidaRegistro.archivado.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Text(data.razonSocial, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                    RisegStatusBadge(
                      label: archivada ? l10n.entidadFiscalEstadoArchivada : l10n.entidadFiscalEstadoActiva,
                      tone: archivada ? RisegStatusTone.neutral : RisegStatusTone.success,
                    ),
                    if (!entidad.datosFiscalesCompletos)
                      RisegStatusBadge(label: l10n.entidadFiscalDatosIncompletos, tone: RisegStatusTone.warning),
                  ],
                ),
                Text(
                  '${data.codigo} · ${data.rfc}',
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.entidadFiscalBotonEditarDomicilio,
            icon: const Icon(Icons.home_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: (deshabilitado || archivada) ? null : onEditarDomicilio,
          ),
          IconButton(
            tooltip: l10n.entidadFiscalBotonEditar,
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: (deshabilitado || archivada) ? null : onEditar,
          ),
          IconButton(
            tooltip: archivada ? l10n.entidadFiscalBotonReactivar : l10n.entidadFiscalBotonArchivar,
            icon: Icon(archivada ? Icons.unarchive_outlined : Icons.archive_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: deshabilitado ? null : (archivada ? onReactivar : onArchivar),
          ),
        ],
      ),
    );
  }
}

/// Contenido del diálogo de alta/edición de Entidad fiscal — solo razón
/// social + RFC. El domicilio fiscal nunca es parte de este formulario
/// (ver `DomicilioFiscalForm`).
class EntidadFiscalForm extends StatefulWidget {
  const EntidadFiscalForm({required this.onCambio, this.entidadInicial, super.key});

  final EntidadFiscalData? entidadInicial;
  final ValueChanged<EntidadFiscalBorrador> onCambio;

  @override
  State<EntidadFiscalForm> createState() => _EntidadFiscalFormState();
}

class _EntidadFiscalFormState extends State<EntidadFiscalForm> {
  late final _razonSocialController = TextEditingController(text: widget.entidadInicial?.razonSocial ?? '');
  late final _rfcController = TextEditingController(text: widget.entidadInicial?.rfc ?? '');

  @override
  void dispose() {
    _razonSocialController.dispose();
    _rfcController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      EntidadFiscalBorrador(razonSocial: _razonSocialController.text, rfc: _rfcController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.entidadFiscalCampoRazonSocial,
          controller: _razonSocialController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.entidadFiscalCampoRfc,
          controller: _rfcController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}

/// Contenido del diálogo de domicilio fiscal — reutiliza los mismos
/// `DireccionControllers` compartidos (Empresa, Sucursal, Cliente).
class DomicilioFiscalForm extends StatefulWidget {
  const DomicilioFiscalForm({required this.onCambio, this.domicilioInicial, super.key});

  final DireccionData? domicilioInicial;
  final ValueChanged<DireccionBorrador> onCambio;

  @override
  State<DomicilioFiscalForm> createState() => _DomicilioFiscalFormState();
}

class _DomicilioFiscalFormState extends State<DomicilioFiscalForm> {
  final _controllers = DireccionControllers();

  @override
  void initState() {
    super.initState();
    _controllers.poblar(widget.domicilioInicial);
  }

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  void _notificar() => widget.onCambio(_controllers.capturar());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.empresaCampoCalle,
          controller: _controllers.calle,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoNumeroExterior,
          controller: _controllers.numeroExterior,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoNumeroInterior,
          controller: _controllers.numeroInterior,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoColonia,
          controller: _controllers.colonia,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoMunicipioAlcaldia,
          controller: _controllers.municipioAlcaldia,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoCiudadLocalidad,
          controller: _controllers.ciudadLocalidad,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoEstadoDireccion,
          controller: _controllers.estado,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoCodigoPostal,
          controller: _controllers.codigoPostal,
          keyboardType: TextInputType.number,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoPais,
          controller: _controllers.pais,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.empresaCampoReferencias,
          controller: _controllers.referencias,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}

/// Mapea un [ErrorCampoEntidadFiscal] a un mensaje visible — mantiene
/// el dominio agnóstico de idioma (mismo patrón que
/// `mensajeErrorCampoContacto`).
String mensajeErrorCampoEntidadFiscal(AppLocalizations l10n, ErrorCampoEntidadFiscal error) {
  return switch (error.campo) {
    CampoEntidadFiscal.cliente => l10n.entidadFiscalErrorClienteInactivo,
    CampoEntidadFiscal.razonSocial => l10n.entidadFiscalErrorRazonSocialRequerida,
    CampoEntidadFiscal.rfc => switch (error.codigo) {
        CodigoErrorEntidadFiscal.formatoInvalido => l10n.entidadFiscalErrorRfcFormatoInvalido,
        CodigoErrorEntidadFiscal.yaExiste => l10n.entidadFiscalErrorRfcYaExiste,
        _ => l10n.entidadFiscalErrorRfcRequerido,
      },
  };
}
