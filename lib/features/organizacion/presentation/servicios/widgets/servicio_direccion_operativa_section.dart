import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/validation/direccion_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/direccion_controllers.dart';

/// Sección "Dirección operativa" de Servicio — siempre de solo lectura
/// (la captura/edición es un diálogo propio, `ServicioDireccionOperativaForm`,
/// nunca parte del formulario general de Datos generales). Opcional
/// mientras el Servicio no esté activo; su ausencia es justo lo que
/// bloquea el botón "Activar" en la pantalla (ver
/// `ServicioExpedienteData.tieneDireccionOperativaActiva`).
class ServicioDireccionOperativaSection extends StatelessWidget {
  const ServicioDireccionOperativaSection({
    required this.direccion,
    required this.deshabilitado,
    required this.onEditar,
    super.key,
  });

  final DireccionData? direccion;
  final bool deshabilitado;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final d = direccion;

    return RisegFormSection(
      title: l10n.servicioSeccionDireccionOperativaTitulo,
      grid: d != null,
      children: [
        if (d == null)
          Row(
            children: [
              Expanded(child: Text(l10n.servicioDireccionOperativaVacia)),
              RisegButton(
                key: const Key('servicio_boton_agregar_direccion_operativa'),
                label: l10n.servicioBotonAgregarDireccionOperativa,
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                onPressed: deshabilitado ? null : onEditar,
              ),
            ],
          )
        else ...[
          CampoConsulta(label: l10n.empresaCampoCalle, value: d.calle),
          CampoConsulta(label: l10n.empresaCampoNumeroExterior, value: d.numeroExterior),
          CampoConsulta(label: l10n.empresaCampoNumeroInterior, value: d.numeroInterior),
          CampoConsulta(label: l10n.empresaCampoColonia, value: d.colonia),
          CampoConsulta(label: l10n.empresaCampoMunicipioAlcaldia, value: d.municipioAlcaldia),
          CampoConsulta(label: l10n.empresaCampoCiudadLocalidad, value: d.ciudadLocalidad),
          CampoConsulta(label: l10n.empresaCampoEstadoDireccion, value: d.estado),
          CampoConsulta(label: l10n.empresaCampoCodigoPostal, value: d.codigoPostal),
          CampoConsulta(label: l10n.empresaCampoPais, value: d.pais),
          CampoConsulta(label: l10n.empresaCampoReferencias, value: d.referencias),
          Align(
            alignment: Alignment.centerLeft,
            child: RisegButton(
              key: const Key('servicio_boton_editar_direccion_operativa'),
              label: l10n.servicioBotonEditarDireccionOperativa,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: deshabilitado ? null : onEditar,
            ),
          ),
        ],
      ],
    );
  }
}

/// Contenido del diálogo de captura/edición — reutiliza los mismos
/// `DireccionControllers` compartidos (mismo patrón que
/// `DomicilioFiscalForm` de Entidad fiscal).
class ServicioDireccionOperativaForm extends StatefulWidget {
  const ServicioDireccionOperativaForm({required this.onCambio, this.direccionInicial, super.key});

  final DireccionData? direccionInicial;
  final ValueChanged<DireccionBorrador> onCambio;

  @override
  State<ServicioDireccionOperativaForm> createState() => _ServicioDireccionOperativaFormState();
}

class _ServicioDireccionOperativaFormState extends State<ServicioDireccionOperativaForm> {
  final _controllers = DireccionControllers();

  @override
  void initState() {
    super.initState();
    _controllers.poblar(widget.direccionInicial);
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
