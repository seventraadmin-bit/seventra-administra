import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/contacto_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/contacto_validator.dart';

/// Sección "Contactos" del expediente de Cliente — terreno nuevo: una
/// lista de longitud variable administrada dentro del mismo expediente
/// (a diferencia de Empresa/Sucursal, que solo administran "el
/// principal", uno solo). Alta/edición vía diálogo; "marcar como
/// principal" es una acción de fila separada — no un campo del
/// formulario — porque el Design System todavía no tiene un control de
/// checkbox/switch propio y esta etapa no lo introduce solo para esto.
class ContactosSection extends StatelessWidget {
  const ContactosSection({
    required this.contactos,
    required this.onAgregar,
    required this.onEditar,
    required this.onArchivar,
    required this.onMarcarPrincipal,
    super.key,
  });

  final List<ContactoData> contactos;
  final VoidCallback onAgregar;
  final ValueChanged<ContactoData> onEditar;
  final ValueChanged<ContactoData> onArchivar;
  final ValueChanged<ContactoData> onMarcarPrincipal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return RisegFormSection(
      title: l10n.clienteSeccionContactosTitulo,
      children: [
        RisegButton(
          key: const Key('cliente_contacto_boton_agregar'),
          label: l10n.clienteContactoBotonAgregar,
          variant: RisegButtonVariant.secondary,
          size: RisegButtonSize.compact,
          onPressed: onAgregar,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (contactos.isEmpty)
          Text(l10n.clienteContactosVacioMensaje, style: AppTypography.body)
        else
          for (final contacto in contactos) _ContactoRow(
            contacto: contacto,
            onEditar: () => onEditar(contacto),
            onArchivar: () => onArchivar(contacto),
            onMarcarPrincipal: () => onMarcarPrincipal(contacto),
          ),
      ],
    );
  }
}

class _ContactoRow extends StatelessWidget {
  const _ContactoRow({
    required this.contacto,
    required this.onEditar,
    required this.onArchivar,
    required this.onMarcarPrincipal,
  });

  final ContactoData contacto;
  final VoidCallback onEditar;
  final VoidCallback onArchivar;
  final VoidCallback onMarcarPrincipal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final esComercial = contacto.tipo == TipoContacto.comercial.name;
    final medio = [contacto.telefono, contacto.correo].where((v) => v != null && v.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(contacto.nombre, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                    const SizedBox(width: AppSpacing.xs),
                    RisegStatusBadge(
                      label: esComercial ? l10n.clienteContactoTipoComercial : l10n.clienteContactoTipoOperativo,
                      tone: RisegStatusTone.info,
                    ),
                    if (contacto.esPrincipal) ...[
                      const SizedBox(width: AppSpacing.xs),
                      RisegStatusBadge(label: l10n.clienteContactoPrincipalBadge, tone: RisegStatusTone.success),
                    ],
                  ],
                ),
                if (medio.isNotEmpty)
                  Text(medio, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              ],
            ),
          ),
          if (!contacto.esPrincipal)
            IconButton(
              tooltip: l10n.clienteContactoPrincipalBadge,
              icon: const Icon(Icons.star_outline, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: onMarcarPrincipal,
            ),
          IconButton(
            tooltip: l10n.clienteContactoBotonEditar,
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onEditar,
          ),
          IconButton(
            tooltip: l10n.clienteContactoBotonArchivar,
            icon: const Icon(Icons.archive_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onArchivar,
          ),
        ],
      ),
    );
  }
}

/// Contenido del diálogo de alta/edición de Contacto — `StatefulWidget`
/// propio para que sus `TextEditingController` vivan y mueran con el
/// ciclo de vida real del widget.
class ContactoForm extends StatefulWidget {
  const ContactoForm({required this.onCambio, this.contactoInicial, super.key});

  final ContactoData? contactoInicial;
  final ValueChanged<ContactoBorrador> onCambio;

  @override
  State<ContactoForm> createState() => _ContactoFormState();
}

class _ContactoFormState extends State<ContactoForm> {
  late final _nombreController = TextEditingController(text: widget.contactoInicial?.nombre ?? '');
  late final _puestoController = TextEditingController(text: widget.contactoInicial?.puesto ?? '');
  late final _telefonoController = TextEditingController(text: widget.contactoInicial?.telefono ?? '');
  late final _correoController = TextEditingController(text: widget.contactoInicial?.correo ?? '');
  TipoContacto? _tipo;

  @override
  void initState() {
    super.initState();
    final tipoInicial = widget.contactoInicial?.tipo;
    _tipo = tipoInicial == null ? null : TipoContacto.values.byName(tipoInicial);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _puestoController.dispose();
    _telefonoController.dispose();
    _correoController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      ContactoBorrador(
        nombre: _nombreController.text,
        tipo: _tipo,
        puesto: _puestoController.text,
        telefono: _telefonoController.text,
        correo: _correoController.text,
        esPrincipal: widget.contactoInicial?.esPrincipal ?? false,
      ),
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
          label: l10n.clienteContactoCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<TipoContacto>(
          label: l10n.clienteContactoCampoTipo,
          value: _tipo,
          items: [
            RisegSelectItem(value: TipoContacto.comercial, label: l10n.clienteContactoTipoComercial),
            RisegSelectItem(value: TipoContacto.operativo, label: l10n.clienteContactoTipoOperativo),
          ],
          onChanged: (valor) {
            setState(() => _tipo = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clienteContactoCampoPuesto,
          controller: _puestoController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clienteContactoCampoTelefono,
          controller: _telefonoController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clienteContactoCampoCorreo,
          controller: _correoController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}

/// Mapea un [ErrorCampoContacto] a un mensaje visible — mantiene el
/// dominio agnóstico de idioma (mismo patrón que
/// `mensajeErrorCampoDireccion`).
String mensajeErrorCampoContacto(AppLocalizations l10n, ErrorCampoContacto error) {
  return switch (error.campo) {
    CampoContacto.nombre => l10n.clienteContactoErrorNombreRequerido,
    CampoContacto.tipo => l10n.clienteContactoErrorTipoRequerido,
    CampoContacto.medioContacto => error.codigo == CodigoErrorContacto.formatoInvalido
        ? l10n.clienteContactoErrorMedioContactoFormatoInvalido
        : l10n.clienteContactoErrorMedioContactoRequerido,
  };
}
