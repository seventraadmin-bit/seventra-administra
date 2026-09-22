import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/core/security/abridor_enlaces.dart';
import 'package:riseg_one/core/security/portapapeles_sensible.dart';
import 'package:riseg_one/features/boveda/domain/usecases/dar_de_baja_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/reactivar_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/boveda/domain/usecases/revelar_secreto_credencial_boveda_usecase.dart';
import 'package:riseg_one/features/organizacion/presentation/shared/campo_consulta.dart';

import '../../boveda_providers.dart';
import '../boveda_controller.dart';
import '../boveda_labels.dart';
import 'cambiar_secreto_credencial_boveda_dialog.dart';
import 'credencial_boveda_historial_dialog.dart';
import 'gestionar_credencial_boveda_dialog.dart';

/// Ficha de una credencial de la Bóveda.
///
/// Es la pantalla principal para consultar un acceso: hasta ahora todo vivía
/// detrás del menú `⋮` y hacer clic en la fila no hacía nada.
///
/// **La contraseña nunca se descifra al abrir.** Para pintar `••••••••••`
/// basta con saber que existe una contraseña guardada, y eso lo dice
/// `secretoCifrado != null` sin tocar el cifrado. Sólo "Mostrar" y "Copiar"
/// —ambas autorizadas y auditadas— piden el valor real, y ese valor vive
/// únicamente en el estado de este widget, que muere al cerrarse.
class CredencialBovedaDetalleDialog extends ConsumerStatefulWidget {
  const CredencialBovedaDetalleDialog({required this.credencialId, super.key});

  final String credencialId;

  @override
  ConsumerState<CredencialBovedaDetalleDialog> createState() => _CredencialBovedaDetalleDialogState();
}

class _CredencialBovedaDetalleDialogState extends ConsumerState<CredencialBovedaDetalleDialog> {
  /// La contraseña en claro mientras está revelada. **Efímera por diseño**:
  /// no viaja a ningún provider, no se serializa y se borra en cuanto se
  /// oculta, se cambia, o se cierra la ficha.
  String? _contrasenaRevelada;

  /// El portapapeles NO pertenece a esta ficha: se toma del contenedor.
  /// Si fuera suyo, cerrar la ventana cancelaría la limpieza y la
  /// contraseña se quedaría indefinidamente disponible para cualquiera.
  PortapapelesSensible get _portapapeles => ref.read(portapapelesSensibleProvider);
  final _abridor = const AbridorEnlaces();

  bool _procesando = false;

  @override
  void dispose() {
    // Sólo se suelta la copia en pantalla. La limpieza del portapapeles
    // sigue su curso: cerrar la ficha no puede dejar una contraseña
    // disponible para siempre, y quien vigila que no se borre contenido
    // ajeno es la comparación previa, no este ciclo de vida.
    _contrasenaRevelada = null;
    super.dispose();
  }

  /// La credencial de ESTA ficha.
  ///
  /// Se lee por id, nunca buscándola en la lista: el listado filtra por
  /// "sólo activas", así que dar de baja la sacaba de ahí y la ficha abierta
  /// se quedaba sin datos justo después de la acción que acababa de hacerse.
  BovedaCredencialData? _credencial;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    // Una consulta, de una fila. Abrir una credencial no toca a las demás.
    Future.microtask(_recargarFicha);
  }

  Future<void> _recargarFicha() async {
    final credencial = await ref.read(bovedaCredencialRepositoryProvider).obtenerPorId(widget.credencialId);
    if (!mounted) return;
    setState(() {
      _credencial = credencial;
      _cargando = false;
    });
  }

  /// Tras una mutación: la ficha y el listado de atrás, en el mismo paso.
  Future<void> _refrescarTodo() async {
    await ref.read(bovedaControllerProvider.notifier).recargar();
    await _recargarFicha();
  }

  void _olvidarContrasena() {
    if (_contrasenaRevelada != null) setState(() => _contrasenaRevelada = null);
  }

  Future<RevelarSecretoCredencialBovedaResultado> _pedirContrasena(AccionRevelacionSecreto accion) {
    // Pasa por el provider autorizado (`exigirMaestro`), nunca por el caso de
    // uso directo: la protección real no está en esconder el botón.
    return ref.read(revelarSecretoCredencialBovedaAutorizadoProvider)(
      credencialId: widget.credencialId,
      accion: accion,
    );
  }

  Future<void> _alternarContrasena(AppLocalizations l10n) async {
    if (_contrasenaRevelada != null) {
      _olvidarContrasena();
      return;
    }
    final resultado = await _pedirContrasena(AccionRevelacionSecreto.mostrar);
    if (!mounted) return;
    switch (resultado) {
      case RevelarSecretoCredencialBovedaExitoso(:final secreto):
        setState(() => _contrasenaRevelada = secreto);
      case RevelarSecretoCredencialBovedaSinSecreto():
        RisegFeedback.showError(context, l10n.bovedaSecretoNoConfigurado);
      case RevelarSecretoCredencialBovedaErrorInesperado():
        RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
    }
  }

  Future<void> _copiarContrasena(AppLocalizations l10n) async {
    final resultado = await _pedirContrasena(AccionRevelacionSecreto.copiar);
    if (!mounted) return;
    switch (resultado) {
      case RevelarSecretoCredencialBovedaExitoso(:final secreto):
        await _portapapeles.copiarTemporal(secreto);
        if (!mounted) return;
        RisegFeedback.showSuccess(context, l10n.bovedaSecretoCopiadoExito);
      case RevelarSecretoCredencialBovedaSinSecreto():
        RisegFeedback.showError(context, l10n.bovedaSecretoNoConfigurado);
      case RevelarSecretoCredencialBovedaErrorInesperado():
        RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
    }
  }

  /// Usuario, correo y URL son metadatos: se copian sin descifrar nada, sin
  /// ventana de limpieza y sin generar un evento sensible — la arquitectura
  /// actual sólo audita la contraseña, y esta ficha no cambia ese criterio.
  Future<void> _copiarMetadato(String valor, String mensaje) async {
    await Clipboard.setData(ClipboardData(text: valor));
    if (mounted) RisegFeedback.showSuccess(context, mensaje);
  }

  Future<void> _editar(BovedaCredencialData credencial) async {
    final actualizo = await mostrarDialogoGestionarCredencialBoveda(context, ref, existente: credencial);
    if (!actualizo || !mounted) return;
    await _refrescarTodo();
  }

  Future<void> _cambiarContrasena() async {
    final actualizo = await mostrarDialogoCambiarSecretoCredencialBoveda(
      context,
      ref,
      credencialId: widget.credencialId,
    );
    if (!mounted) return;
    // Aunque el diálogo se cancele: una contraseña en pantalla mientras se
    // manipula su reemplazo no tiene por qué seguir ahí.
    _olvidarContrasena();
    if (actualizo) await _refrescarTodo();
  }

  Future<void> _cambiarEstado(BovedaCredencialData credencial, AppLocalizations l10n) async {
    setState(() => _procesando = true);
    final esActiva = credencial.cicloVidaRegistro == 'activo';
    final resultado =
        esActiva
            ? await ref.read(darDeBajaCredencialBovedaAutorizadoProvider)(id: credencial.id)
            : await ref.read(reactivarCredencialBovedaAutorizadoProvider)(id: credencial.id);
    if (!mounted) return;
    setState(() => _procesando = false);

    final exito = resultado is DarDeBajaCredencialBovedaExitoso || resultado is ReactivarCredencialBovedaExitoso;
    if (!exito) {
      RisegFeedback.showError(context, l10n.bovedaErrorInesperado);
      return;
    }
    _olvidarContrasena();
    await _refrescarTodo();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.colors;
    final credencial = _credencial;

    if (_cargando) {
      return _Marco(
        titulo: l10n.bovedaDetalleTitulo,
        cuerpo: const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
        acciones: const [],
      );
    }

    if (credencial == null) {
      return _Marco(
        titulo: l10n.bovedaDetalleTitulo,
        cuerpo: RisegEmptyState(title: l10n.bovedaListaVaciaTitulo, message: ''),
        acciones: const [],
      );
    }

    final esActiva = credencial.cicloVidaRegistro == 'activo';
    final tieneContrasena = credencial.secretoCifrado != null;

    return _Marco(
      titulo: credencial.nombre,
      cuerpo: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  tipoAccesoBovedaLabel(l10n, credencial.tipo),
                  style: AppTypography.body.copyWith(color: colors.textMuted),
                ),
                const SizedBox(width: AppSpacing.sm),
                RisegStatusBadge(
                  label: esActiva ? l10n.bovedaEstatusActivo : l10n.bovedaEstatusBaja,
                  tone: esActiva ? RisegStatusTone.success : RisegStatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            RisegSectionHeader(title: l10n.bovedaSeccionAcceso),
            const SizedBox(height: AppSpacing.xs),

            if ((credencial.usuarioAcceso ?? '').isNotEmpty)
              _FilaDato(
                etiqueta: l10n.bovedaCampoUsuarioAcceso,
                valor: credencial.usuarioAcceso!,
                acciones: [
                  _AccionTexto(
                    clave: 'boveda_detalle_copiar_usuario',
                    etiqueta: l10n.bovedaAccionCopiar,
                    onPressed: () => _copiarMetadato(credencial.usuarioAcceso!, l10n.bovedaUsuarioCopiado),
                  ),
                ],
              ),

            if ((credencial.correo ?? '').isNotEmpty)
              _FilaDato(
                etiqueta: l10n.bovedaCampoCorreo,
                valor: credencial.correo!,
                acciones: [
                  _AccionTexto(
                    clave: 'boveda_detalle_copiar_correo',
                    etiqueta: l10n.bovedaAccionCopiar,
                    onPressed: () => _copiarMetadato(credencial.correo!, l10n.bovedaCorreoCopiado),
                  ),
                ],
              ),

            _FilaDato(
              etiqueta: l10n.bovedaCampoSecreto,
              // Diez puntos fijos: la longitud real tampoco se filtra.
              valor: tieneContrasena ? (_contrasenaRevelada ?? '••••••••••') : l10n.bovedaSinContrasena,
              seleccionable: _contrasenaRevelada != null,
              acciones: [
                if (tieneContrasena) ...[
                  _AccionTexto(
                    clave: 'boveda_detalle_alternar_contrasena',
                    etiqueta:
                        _contrasenaRevelada == null ? l10n.bovedaAccionMostrarSecreto : l10n.bovedaAccionOcultarSecreto,
                    onPressed: () => _alternarContrasena(l10n),
                  ),
                  _AccionTexto(
                    clave: 'boveda_detalle_copiar_contrasena',
                    etiqueta: l10n.bovedaAccionCopiar,
                    onPressed: () => _copiarContrasena(l10n),
                  ),
                ],
              ],
            ),

            if ((credencial.url ?? '').isNotEmpty)
              _FilaDato(
                etiqueta: l10n.bovedaCampoUrl,
                valor: credencial.url!,
                acciones: [
                  // El botón sólo aparece si la dirección es realmente
                  // abrible; el abridor vuelve a comprobarlo de todos modos.
                  if (AbridorEnlaces.esAbrible(credencial.url))
                    _AccionTexto(
                      clave: 'boveda_detalle_abrir_url',
                      etiqueta: l10n.bovedaAccionAbrir,
                      onPressed: () async {
                        final abrio = await _abridor.abrir(credencial.url);
                        if (!abrio && mounted) RisegFeedback.showError(context, l10n.bovedaUrlInvalida);
                      },
                    ),
                  _AccionTexto(
                    clave: 'boveda_detalle_copiar_url',
                    etiqueta: l10n.bovedaAccionCopiar,
                    onPressed: () => _copiarMetadato(credencial.url!, l10n.bovedaUrlCopiada),
                  ),
                ],
              ),

            const SizedBox(height: AppSpacing.md),
            RisegSectionHeader(title: l10n.bovedaSeccionInformacion),
            const SizedBox(height: AppSpacing.xs),
            if ((credencial.observaciones ?? '').isNotEmpty)
              CampoConsulta(label: l10n.bovedaCampoObservaciones, value: credencial.observaciones!),
            if (credencial.fechaActualizacionSecreto != null) ...[
              const SizedBox(height: AppSpacing.xs),
              CampoConsulta(
                label: l10n.bovedaCampoContrasenaActualizada,
                value: _fecha(credencial.fechaActualizacionSecreto!),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            CampoConsulta(label: l10n.bovedaCampoUltimaActualizacion, value: _fecha(credencial.updatedAt)),
          ],
        ),
      ),
      acciones: [
        RisegButton(
          key: const Key('boveda_detalle_historial'),
          label: l10n.bovedaAccionHistorial,
          variant: RisegButtonVariant.ghost,
          onPressed: () => mostrarDialogoHistorialCredencialBoveda(context, ref, credencialId: widget.credencialId),
        ),
        RisegButton(
          key: const Key('boveda_detalle_cambiar_estado'),
          label: esActiva ? l10n.bovedaAccionDarDeBaja : l10n.bovedaAccionReactivar,
          variant: RisegButtonVariant.ghost,
          loading: _procesando,
          onPressed: () => _cambiarEstado(credencial, l10n),
        ),
        // Cambiar la contraseña de un acceso retirado no significa nada: el
        // dominio también lo rechaza, esto sólo evita ofrecerlo.
        if (esActiva)
          RisegButton(
            key: const Key('boveda_detalle_cambiar_contrasena'),
            label: l10n.bovedaAccionCambiarSecreto,
            variant: RisegButtonVariant.secondary,
            onPressed: _cambiarContrasena,
          ),
        RisegButton(
          key: const Key('boveda_detalle_editar'),
          label: l10n.bovedaAccionEditar,
          onPressed: () => _editar(credencial),
        ),
      ],
    );
  }

  String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Un dato con sus acciones a la derecha. Se apila en vertical en anchos
/// reducidos, para no comprimir el valor hasta volverlo ilegible.
class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.etiqueta, required this.valor, this.acciones = const [], this.seleccionable = false});

  final String etiqueta;
  final String valor;
  final List<Widget> acciones;
  final bool seleccionable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final estrecho = constraints.maxWidth < 420;
          final texto = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(etiqueta, style: AppTypography.label.copyWith(color: colors.textMuted)),
              const SizedBox(height: 2),
              seleccionable
                  ? SelectableText(valor, style: AppTypography.body)
                  : Text(valor, style: AppTypography.body, overflow: TextOverflow.ellipsis),
            ],
          );
          final botones = Wrap(spacing: AppSpacing.xs, children: acciones);
          if (estrecho) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [texto, if (acciones.isNotEmpty) botones],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [Expanded(child: texto), if (acciones.isNotEmpty) botones],
          );
        },
      ),
    );
  }
}

class _AccionTexto extends StatelessWidget {
  const _AccionTexto({required this.clave, required this.etiqueta, required this.onPressed});

  final String clave;
  final String etiqueta;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return RisegButton(
      key: Key(clave),
      label: etiqueta,
      variant: RisegButtonVariant.ghost,
      size: RisegButtonSize.compact,
      onPressed: onPressed,
    );
  }
}

/// Abre la ficha de una credencial.
Future<void> mostrarDetalleCredencialBoveda(BuildContext context, String credencialId) {
  return showDialog<void>(context: context, builder: (_) => CredencialBovedaDetalleDialog(credencialId: credencialId));
}

/// Envoltorio del diálogo — mismo patrón que el resto de los detalles del
/// proyecto (`Dialog` + `SingleChildScrollView` + ancho máximo), para que
/// la ficha pueda desplazarse en pantallas bajas en vez de desbordarse.
class _Marco extends StatelessWidget {
  const _Marco({required this.titulo, required this.cuerpo, required this.acciones});

  final String titulo;
  final Widget cuerpo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: AppTypography.heading2.copyWith(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: const Key('boveda_detalle_cerrar'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                cuerpo,
                if (acciones.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  // Wrap y no Row: en 500px las acciones bajan de renglón en
                  // vez de comprimirse hasta no poder pulsarse.
                  Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: acciones),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
