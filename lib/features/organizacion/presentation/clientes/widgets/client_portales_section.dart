import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/tables/audit_columns.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/cliente_portal_table.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_portal_errors.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/cliente_portal_validator.dart';
import 'package:riseg_one/features/organizacion/presentation/servicios/widgets/servicio_configuracion_cobro_section.dart' show tipoPortalClienteLabel;

/// Sección "Portales" dentro de "Datos de cobranza / Facturación" del
/// expediente de Cliente — mismo patrón de lista embebida que
/// `EntidadesFiscalesSection`: muestra activos **y** archivados (un
/// archivado debe seguir siendo encontrable para reactivarlo), sin
/// pantalla propia.
class ClientePortalesSection extends StatelessWidget {
  const ClientePortalesSection({
    required this.portales,
    required this.deshabilitado,
    required this.onAgregar,
    required this.onEditar,
    required this.onArchivar,
    required this.onReactivar,
    super.key,
  });

  final List<ClientePortalData> portales;
  final bool deshabilitado;
  final VoidCallback onAgregar;
  final ValueChanged<ClientePortalData> onEditar;
  final ValueChanged<ClientePortalData> onArchivar;
  final ValueChanged<ClientePortalData> onReactivar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.clientePortalSeccionTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
            ),
            RisegButton(
              key: const Key('cliente_portal_boton_agregar'),
              label: l10n.clientePortalBotonAgregar,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: deshabilitado ? null : onAgregar,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (portales.isEmpty)
          Text(l10n.clientePortalSinPortales, style: AppTypography.caption.copyWith(color: colors.textMuted))
        else
          for (final portal in portales)
            _ClientePortalRow(
              portal: portal,
              deshabilitado: deshabilitado,
              onEditar: () => onEditar(portal),
              onArchivar: () => onArchivar(portal),
              onReactivar: () => onReactivar(portal),
            ),
      ],
    );
  }
}

class _ClientePortalRow extends StatelessWidget {
  const _ClientePortalRow({
    required this.portal,
    required this.deshabilitado,
    required this.onEditar,
    required this.onArchivar,
    required this.onReactivar,
  });

  final ClientePortalData portal;
  final bool deshabilitado;
  final VoidCallback onEditar;
  final VoidCallback onArchivar;
  final VoidCallback onReactivar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final archivado = portal.cicloVidaRegistro == CicloVidaRegistro.archivado.name;
    final detalle = [
      if (portal.url != null && portal.url!.isNotEmpty) portal.url,
      if (portal.usuario != null && portal.usuario!.isNotEmpty) '${l10n.clientePortalCampoUsuario}: ${portal.usuario}',
    ].whereType<String>().join(' · ');

    return Padding(
      key: Key('cliente_portal_fila_${portal.id}'),
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
                    Text(portal.nombre, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                    RisegStatusBadge(
                      label: tipoPortalClienteLabel(l10n, TipoPortalCliente.values.byName(portal.tipo)),
                      tone: RisegStatusTone.info,
                    ),
                    RisegStatusBadge(
                      label: archivado ? l10n.clientePortalEstadoArchivada : l10n.clientePortalEstadoActivo,
                      tone: archivado ? RisegStatusTone.neutral : RisegStatusTone.success,
                    ),
                  ],
                ),
                if (detalle.isNotEmpty)
                  Text(detalle, style: AppTypography.caption.copyWith(color: colors.textMuted)),
              ],
            ),
          ),
          IconButton(
            key: Key('cliente_portal_boton_editar_${portal.id}'),
            tooltip: l10n.clientePortalBotonEditar,
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: (deshabilitado || archivado) ? null : onEditar,
          ),
          IconButton(
            key: Key('cliente_portal_boton_ciclo_vida_${portal.id}'),
            tooltip: archivado ? l10n.clientePortalBotonReactivar : l10n.clientePortalBotonArchivar,
            icon: Icon(archivado ? Icons.unarchive_outlined : Icons.archive_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: deshabilitado ? null : (archivado ? onReactivar : onArchivar),
          ),
        ],
      ),
    );
  }
}

/// Contenido del diálogo de alta/edición de portal — nombre, tipo, URL,
/// usuario, contraseña y observaciones. `portalInicial` prellena todo
/// **excepto** la contraseña (nunca se descifra para mostrarla) —
/// dejarla en blanco al editar significa "no cambiarla" (ver el doc
/// comment de `ActualizarClientePortalUseCase`).
class ClientePortalForm extends StatefulWidget {
  const ClientePortalForm({required this.onCambio, this.portalInicial, super.key});

  final ClientePortalData? portalInicial;
  final ValueChanged<ClientePortalBorrador> onCambio;

  @override
  State<ClientePortalForm> createState() => _ClientePortalFormState();
}

class _ClientePortalFormState extends State<ClientePortalForm> {
  late final _nombreController = TextEditingController(text: widget.portalInicial?.nombre ?? '');
  late TipoPortalCliente _tipo =
      widget.portalInicial == null ? TipoPortalCliente.otro : TipoPortalCliente.values.byName(widget.portalInicial!.tipo);
  late final _urlController = TextEditingController(text: widget.portalInicial?.url ?? '');
  late final _usuarioController = TextEditingController(text: widget.portalInicial?.usuario ?? '');
  late final _contrasenaController = TextEditingController();
  late final _observacionesController = TextEditingController(text: widget.portalInicial?.observaciones ?? '');

  @override
  void dispose() {
    _nombreController.dispose();
    _urlController.dispose();
    _usuarioController.dispose();
    _contrasenaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      ClientePortalBorrador(
        nombre: _nombreController.text,
        tipo: _tipo,
        url: _urlController.text,
        usuario: _usuarioController.text,
        contrasenaNueva: _contrasenaController.text.isEmpty ? null : _contrasenaController.text,
        observaciones: _observacionesController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final esEdicion = widget.portalInicial != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTextField(
          label: l10n.clientePortalCampoNombre,
          controller: _nombreController,
          autofocus: true,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<TipoPortalCliente>(
          label: l10n.clientePortalCampoTipo,
          value: _tipo,
          items: [
            for (final t in TipoPortalCliente.values) RisegSelectItem(value: t, label: tipoPortalClienteLabel(l10n, t)),
          ],
          onChanged: (valor) {
            if (valor == null) return;
            setState(() => _tipo = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clientePortalCampoUrl,
          controller: _urlController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clientePortalCampoUsuario,
          controller: _usuarioController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clientePortalCampoContrasena,
          controller: _contrasenaController,
          obscureText: true,
          helperText: esEdicion ? l10n.clientePortalCampoContrasenaAyudaEdicion : l10n.clientePortalCampoContrasenaAyudaAlta,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.clientePortalCampoObservaciones,
          controller: _observacionesController,
          onChanged: (_) => _notificar(),
        ),
      ],
    );
  }
}

/// Mapea un [ErrorCampoClientePortal] a un mensaje visible — mismo
/// patrón que `mensajeErrorCampoEntidadFiscal`.
String mensajeErrorCampoClientePortal(AppLocalizations l10n, ErrorCampoClientePortal error) {
  return switch (error.campo) {
    CampoClientePortal.cliente => l10n.clientePortalErrorClienteInactivo,
    CampoClientePortal.nombre => l10n.clientePortalErrorNombreRequerido,
  };
}
