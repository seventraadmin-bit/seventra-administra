import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/catalogo_repository.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_con_vigencia.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/configuracion_cobro_validator.dart';

final _formatoFecha = DateFormat('dd/MM/yyyy');

/// Sección "Configuración de cobro" de Servicio (Etapa 4H.1) — 1:1, así
/// que se muestra como una ficha resumen (no una tabla) con la vigencia
/// vigente (o, si todavía no ha empezado, la programada más próxima).
/// El alta de una nueva vigencia y el historial cronológico quedan para
/// la Etapa 4H.2, junto con las reglas temporales.
class ServicioConfiguracionCobroSection extends StatelessWidget {
  const ServicioConfiguracionCobroSection({
    required this.configuracionCobro,
    required this.deshabilitado,
    required this.onAgregar,
    super.key,
  });

  final ConfiguracionCobroConVigencia? configuracionCobro;
  final bool deshabilitado;
  final VoidCallback onAgregar;

  ConfiguracionCobroVigenciaData? _filaVisible(ConfiguracionCobroConVigencia c) =>
      c.vigenciaActual ?? (c.vigenciasProgramadas.isEmpty ? null : c.vigenciasProgramadas.first);

  String _tipoDocumentoLabel(AppLocalizations l10n, String valor) {
    return switch (TipoDocumentoCobro.values.byName(valor)) {
      TipoDocumentoCobro.cfdi => l10n.servicioCobroTipoDocumentoCfdi,
      TipoDocumentoCobro.reciboDePago => l10n.servicioCobroTipoDocumentoReciboDePago,
    };
  }

  String _agrupacionLabel(AppLocalizations l10n, String valor) {
    return switch (AgrupacionCobro.values.byName(valor)) {
      AgrupacionCobro.porServicio => l10n.servicioCobroAgrupacionPorServicio,
      AgrupacionCobro.porEntidadFiscal => l10n.servicioCobroAgrupacionPorEntidadFiscal,
      AgrupacionCobro.porCliente => l10n.servicioCobroAgrupacionPorCliente,
      AgrupacionCobro.manual => l10n.servicioCobroAgrupacionManual,
    };
  }

  String _metodoLabel(AppLocalizations l10n, String valor) {
    return switch (MetodoPagoCobro.values.byName(valor)) {
      MetodoPagoCobro.pue => l10n.servicioCobroMetodoPue,
      MetodoPagoCobro.ppd => l10n.servicioCobroMetodoPpd,
      MetodoPagoCobro.noAplica => l10n.servicioCobroMetodoNoAplica,
    };
  }

  Widget _estadoBadge(AppLocalizations l10n, ConfiguracionCobroConVigencia c) {
    if (c.vigenciaActual != null) {
      return RisegStatusBadge(label: l10n.servicioCobroEstadoVigente, tone: RisegStatusTone.success);
    }
    if (c.vigenciasProgramadas.isNotEmpty) {
      return RisegStatusBadge(label: l10n.servicioCobroEstadoProgramada, tone: RisegStatusTone.info);
    }
    return RisegStatusBadge(label: l10n.servicioCobroEstadoSinCondicionVigente, tone: RisegStatusTone.neutral);
  }

  Widget _dato(BuildContext context, String etiqueta, String valor) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        Text(valor, style: AppTypography.body.copyWith(color: colors.textPrimary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final configuracion = configuracionCobro;
    final fila = configuracion == null ? null : _filaVisible(configuracion);

    return RisegFormSection(
      title: l10n.servicioSeccionConfiguracionCobroTitulo,
      children: [
        if (configuracion == null || fila == null)
          Text(l10n.servicioCobroSinConfiguracion)
        else
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              _dato(context, l10n.servicioCobroColumnaTipoDocumento, _tipoDocumentoLabel(l10n, fila.tipoDocumento)),
              _dato(context, l10n.servicioCobroColumnaFrecuencia, configuracion.frecuenciaNombre ?? '—'),
              _dato(context, l10n.servicioCobroColumnaAgrupacion, _agrupacionLabel(l10n, fila.agrupacion)),
              _dato(context, l10n.servicioCobroColumnaMetodo, _metodoLabel(l10n, fila.metodo)),
              _dato(
                context,
                l10n.servicioCobroColumnaEntidadFiscal,
                configuracion.entidadFiscalRazonSocial ?? l10n.servicioCobroSinEntidadFiscal,
              ),
              _dato(context, l10n.servicioCobroColumnaVigenteDesde, _formatoFecha.format(fila.fechaInicioVigencia)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.servicioCobroColumnaEstado, style: AppTypography.caption.copyWith(color: context.colors.textMuted)),
                  _estadoBadge(l10n, configuracion),
                ],
              ),
            ],
          ),
        if (fila?.requiereComplemento == true) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.servicioCobroRequiereComplementoAviso,
            style: AppTypography.caption.copyWith(color: context.colors.info),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: RisegButton(
            key: const Key('servicio_boton_agregar_configuracion_cobro'),
            label: l10n.servicioCobroBotonAgregar,
            variant: RisegButtonVariant.secondary,
            size: RisegButtonSize.compact,
            onPressed: deshabilitado || configuracion != null ? null : onAgregar,
          ),
        ),
      ],
    );
  }
}

/// Contenido del diálogo de alta de la Configuración de cobro — captura
/// las condiciones de su primera vigencia (Etapa 4H.1: sin reglas
/// temporales todavía, esas llegan en la 4H.2). Los correos de envío se
/// manejan como una lista propia dentro de este formulario (tabla hija
/// `ConfiguracionCobroCorreo`, reconstruida completa al guardar).
class ServicioConfiguracionCobroForm extends StatefulWidget {
  const ServicioConfiguracionCobroForm({
    required this.frecuencias,
    required this.entidadesFiscales,
    required this.onCambio,
    super.key,
  });

  final List<CatalogoItem> frecuencias;
  final List<EntidadFiscalData> entidadesFiscales;
  final ValueChanged<ConfiguracionCobroBorrador> onCambio;

  @override
  State<ServicioConfiguracionCobroForm> createState() => _ServicioConfiguracionCobroFormState();
}

class _ServicioConfiguracionCobroFormState extends State<ServicioConfiguracionCobroForm> {
  TipoDocumentoCobro? _tipoDocumento;
  String? _frecuenciaId;
  late final _diaInicioPeriodoController = TextEditingController();
  AgrupacionCobro? _agrupacion;
  MetodoPagoCobro? _metodo;
  bool _requiereComplemento = false;
  String? _entidadFiscalId;
  DateTime? _fechaInicioVigencia;
  late final _portalNombreController = TextEditingController();
  late final _portalUrlController = TextEditingController();
  late final _portalUsuarioController = TextEditingController();
  late final _portalContrasenaController = TextEditingController();
  late final _portalObservacionesController = TextEditingController();
  late final _cuentaBancariaController = TextEditingController();
  late final _observacionesController = TextEditingController();
  late final _nuevoCorreoController = TextEditingController();
  final List<String> _correos = [];

  @override
  void dispose() {
    _diaInicioPeriodoController.dispose();
    _portalNombreController.dispose();
    _portalUrlController.dispose();
    _portalUsuarioController.dispose();
    _portalContrasenaController.dispose();
    _portalObservacionesController.dispose();
    _cuentaBancariaController.dispose();
    _observacionesController.dispose();
    _nuevoCorreoController.dispose();
    super.dispose();
  }

  void _notificar() {
    widget.onCambio(
      ConfiguracionCobroBorrador(
        tipoDocumento: _tipoDocumento,
        frecuenciaId: _frecuenciaId ?? '',
        diaInicioPeriodo: int.tryParse(_diaInicioPeriodoController.text.trim()),
        agrupacion: _agrupacion,
        metodo: _metodo,
        requiereComplemento: _requiereComplemento,
        fechaInicioVigencia: _fechaInicioVigencia,
        entidadFiscalId: _entidadFiscalId,
        portalNombre: _portalNombreController.text,
        portalUrl: _portalUrlController.text,
        portalUsuario: _portalUsuarioController.text,
        portalContrasena: _portalContrasenaController.text,
        portalObservaciones: _portalObservacionesController.text,
        cuentaBancaria: _cuentaBancariaController.text,
        observaciones: _observacionesController.text,
        correos: List.unmodifiable(_correos),
      ),
    );
  }

  void _agregarCorreo() {
    final correo = _nuevoCorreoController.text.trim();
    if (correo.isEmpty) return;
    setState(() {
      _correos.add(correo);
      _nuevoCorreoController.clear();
    });
    _notificar();
  }

  void _quitarCorreo(int indice) {
    setState(() => _correos.removeAt(indice));
    _notificar();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegSelect<TipoDocumentoCobro>(
          label: l10n.servicioCobroCampoTipoDocumento,
          value: _tipoDocumento,
          items: [
            RisegSelectItem(value: TipoDocumentoCobro.cfdi, label: l10n.servicioCobroTipoDocumentoCfdi),
            RisegSelectItem(value: TipoDocumentoCobro.reciboDePago, label: l10n.servicioCobroTipoDocumentoReciboDePago),
          ],
          onChanged: (valor) {
            setState(() => _tipoDocumento = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioCobroCampoFrecuencia,
          value: _frecuenciaId,
          items: [for (final f in widget.frecuencias) RisegSelectItem(value: f.id, label: f.nombre)],
          onChanged: (valor) {
            setState(() => _frecuenciaId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoDiaInicioPeriodo,
          controller: _diaInicioPeriodoController,
          keyboardType: TextInputType.number,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<AgrupacionCobro>(
          label: l10n.servicioCobroCampoAgrupacion,
          value: _agrupacion,
          items: [
            RisegSelectItem(value: AgrupacionCobro.porServicio, label: l10n.servicioCobroAgrupacionPorServicio),
            RisegSelectItem(value: AgrupacionCobro.porEntidadFiscal, label: l10n.servicioCobroAgrupacionPorEntidadFiscal),
            RisegSelectItem(value: AgrupacionCobro.porCliente, label: l10n.servicioCobroAgrupacionPorCliente),
            RisegSelectItem(value: AgrupacionCobro.manual, label: l10n.servicioCobroAgrupacionManual),
          ],
          onChanged: (valor) {
            setState(() => _agrupacion = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<MetodoPagoCobro>(
          label: l10n.servicioCobroCampoMetodo,
          value: _metodo,
          items: [
            RisegSelectItem(value: MetodoPagoCobro.pue, label: l10n.servicioCobroMetodoPue),
            RisegSelectItem(value: MetodoPagoCobro.ppd, label: l10n.servicioCobroMetodoPpd),
            RisegSelectItem(value: MetodoPagoCobro.noAplica, label: l10n.servicioCobroMetodoNoAplica),
          ],
          onChanged: (valor) {
            setState(() => _metodo = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(l10n.servicioCobroCampoRequiereComplemento, style: AppTypography.body.copyWith(color: colors.textPrimary)),
            ),
            Switch(
              value: _requiereComplemento,
              onChanged: (valor) {
                setState(() => _requiereComplemento = valor);
                _notificar();
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        RisegSelect<String>(
          label: l10n.servicioCobroCampoEntidadFiscal,
          value: _entidadFiscalId,
          items: [for (final e in widget.entidadesFiscales) RisegSelectItem(value: e.id, label: e.razonSocial)],
          enabled: widget.entidadesFiscales.isNotEmpty,
          onChanged: (valor) {
            setState(() => _entidadFiscalId = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          label: l10n.servicioCobroCampoFechaInicioVigencia,
          value: _fechaInicioVigencia,
          onChanged: (valor) {
            setState(() => _fechaInicioVigencia = valor);
            _notificar();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioCobroSeccionPortalTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalNombre,
          controller: _portalNombreController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalUrl,
          controller: _portalUrlController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalUsuario,
          controller: _portalUsuarioController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalContrasena,
          controller: _portalContrasenaController,
          obscureText: true,
          helperText: l10n.servicioCobroCampoPortalContrasenaAyuda,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoPortalObservaciones,
          controller: _portalObservacionesController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.lg),
        RisegTextField(
          label: l10n.servicioCobroCampoCuentaBancaria,
          controller: _cuentaBancariaController,
          helperText: l10n.servicioCobroCampoCuentaBancariaAyuda,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.md),
        RisegTextField(
          label: l10n.servicioCobroCampoObservaciones,
          controller: _observacionesController,
          onChanged: (_) => _notificar(),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.servicioCobroSeccionCorreosTitulo, style: AppTypography.label.copyWith(color: colors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        if (_correos.isEmpty)
          Text(l10n.servicioCobroSinCorreos, style: AppTypography.caption.copyWith(color: colors.textMuted))
        else
          Column(
            children: [
              for (var i = 0; i < _correos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Row(
                    children: [
                      Expanded(child: Text(_correos[i], style: AppTypography.body.copyWith(color: colors.textPrimary))),
                      IconButton(
                        tooltip: l10n.servicioCobroBotonQuitarCorreo,
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _quitarCorreo(i),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: RisegTextField(
                label: l10n.servicioCobroCampoNuevoCorreo,
                controller: _nuevoCorreoController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            RisegButton(
              label: l10n.servicioCobroBotonAgregarCorreo,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _agregarCorreo,
            ),
          ],
        ),
      ],
    );
  }
}
