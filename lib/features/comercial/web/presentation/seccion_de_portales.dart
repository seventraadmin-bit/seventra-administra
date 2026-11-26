import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../../app/shell/se_cierra_al_cambiar_la_direccion.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/clientes_repositorio_http.dart';
import '../modelos/portal_de_cliente.dart';

/// **Los portales del cliente**, con su usuario y su contraseña.
///
/// ## Lo que esta sección resuelve, y el escritorio no
///
/// 🔑 En RISEG ONE escritorio **la contraseña de un portal no se puede ver en ninguna
/// pantalla** —es su duda 12—, así que quien la necesitaba la tenía apuntada en otro sitio:
/// exactamente lo que un sitio para guardarla viene a evitar. Aquí existen **Mostrar** y
/// **Copiar**, cada uno con **su propio evento** en la bitácora y detrás de un permiso
/// propio que el Maestro **no hereda**.
///
/// ## Tres permisos, y la pantalla no los confunde
///
/// Ver la lista, administrarla y **ver la contraseña** son tres códigos independientes. Lo
/// que más se presta a confundir es el tercero: quien administra portales **fija** la
/// contraseña y puede no poder verla, así que los dos botones de revelar salen **apagados
/// con su porqué** en vez de escondidos — escondidos harían pensar que la función no existe.
///
/// ## La contraseña no vive en esta pantalla
///
/// No hay ningún campo de estado que la guarde: se pide al servidor **una vez por acto**, se
/// enseña en un diálogo y se va con él. Recargar el expediente la vuelve a ocultar, igual
/// que en el escritorio, y eso sale gratis porque nunca estuvo guardada.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo</b>, que exporta un
/// componente con `dart:io` y rompería la build web.
/// Cómo se manda un texto al portapapeles. **Lanza si no se pudo.**
typedef CopiaAlPortapapeles = Future<void> Function(String texto);

/// El de verdad. Se separa para que la sección pueda recibir otro en las pruebas, igual
/// que el selector de logotipo del expediente.
Future<void> copiarAlPortapapelesDelSistema(String texto) =>
    Clipboard.setData(ClipboardData(text: texto));

class SeccionDePortales extends StatefulWidget {
  const SeccionDePortales({
    required this.repositorio,
    required this.empresaId,
    required this.clienteId,
    required this.puedeAdministrar,
    required this.puedeRevelar,
    required this.guardia,
    this.copiarAlPortapapeles = copiarAlPortapapelesDelSistema,
    super.key,
  });

  /// Cómo se copia. Por omisión el portapapeles del sistema; se recibe **para que las
  /// pruebas puedan ejercitar lo que pasa después** —y, sobre todo, lo que pasa cuando el
  /// navegador no deja copiar—. Mismo criterio que `elegirUnLogotipo` en el expediente.
  final CopiaAlPortapapeles copiarAlPortapapeles;

  final ClientesRepositorioHttp repositorio;
  final String empresaId;
  final String clienteId;

  /// Alta, corrección, archivar, y **fijar o borrar** la contraseña.
  final bool puedeAdministrar;

  /// **Mostrar y Copiar.** Independiente del anterior en los dos sentidos.
  final bool puedeRevelar;

  final GuardiaDeSalida guardia;

  @override
  State<SeccionDePortales> createState() => _SeccionDePortalesState();
}

class _SeccionDePortalesState extends State<SeccionDePortales> {
  List<PortalDeCliente>? _portales;
  Failure? _fallo;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(SeccionDePortales anterior) {
    super.didUpdateWidget(anterior);

    if (anterior.clienteId != widget.clienteId) _cargar();
  }

  Future<void> _cargar() async {
    final id = widget.clienteId;

    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.listarPortales(
      empresaId: widget.empresaId,
      clienteId: id,
    );

    // ⚠️ SI EL CLIENTE CAMBIÓ MIENTRAS SE CARGABA, esta respuesta es de otro: pintarla
    // enseñaría los portales del cliente anterior bajo el nombre del nuevo.
    if (!mounted || widget.clienteId != id) return;

    resultado.when(
      ok: (lista) => setState(() {
        _portales = lista;
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return RisegFormSection(
      title: 'Portales',
      // «SE GUARDA AL MOMENTO», igual que las razones sociales y los contactos: cada portal
      // y su contraseña se escriben por su propia ruta, así que el «Cancelar» del
      // expediente no los deshace. Lo que no se adivina es eso, no que las archivadas se
      // sigan viendo —eso se entiende al verlas con su insignia—.
      description:
          'Por dónde se le sube una factura o se le da de alta como proveedor. Se '
          'guarda al momento.',
      children: [
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_fallo case final f?)
          _Aviso(
            icono: Icons.cloud_off_outlined,
            mensaje: 'No se pudieron cargar los portales: ${f.message}',
            accion: RisegButton(
              label: 'Intentar de nuevo',
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _cargar,
            ),
          )
        else if ((_portales ?? const []).isEmpty)
          const _Aviso(
            icono: Icons.vpn_key_outlined,
            mensaje:
                'Este cliente todavía no tiene portales. Aquí se guarda por dónde se '
                'le sube una factura, con su usuario y su contraseña.',
          )
        else
          for (final p in _portales!)
            _Fila(
              portal: p,
              puedeAdministrar: widget.puedeAdministrar,
              puedeRevelar: widget.puedeRevelar,
              onCorregir: () => _abrirPanel(p),
              onContrasena: () => _abrirContrasena(p),
              onMostrar: () => _revelar(p, ActoDeRevelar.mostrar),
              onCopiar: () => _revelar(p, ActoDeRevelar.copiar),
              onCicloDeVida: () => _cambiarCicloDeVida(p),
            ),

        if (widget.puedeAdministrar) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: RisegButton(
              label: 'Añadir portal',
              icon: Icons.add,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _cargando ? null : () => _abrirPanel(null),
            ),
          ),
        ],

        // 🔑 QUIEN ADMINISTRA Y NO PUEDE VER SE LO ENCUENTRA DICHO, no deducido de dos
        // botones apagados. Es la asimetría que más confunde de las tres, y la que el
        // escritorio no tiene.
        if (widget.puedeAdministrar && !widget.puedeRevelar && !_cargando)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Puedes guardar contraseñas y no verlas: mostrarlas o copiarlas necesita '
              'un permiso aparte, que se concede uno por uno.',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }

  Future<void> _abrirPanel(PortalDeCliente? portal) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDePortal(
        portal: portal,
        empresaId: widget.empresaId,
        clienteId: widget.clienteId,
        repositorio: widget.repositorio,
        guardia: widget.guardia,
      ),
    );

    if ((guardado ?? false) && mounted) await _cargar();
  }

  Future<void> _abrirContrasena(PortalDeCliente portal) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeContrasena(
        portal: portal,
        empresaId: widget.empresaId,
        clienteId: widget.clienteId,
        repositorio: widget.repositorio,
        guardia: widget.guardia,
      ),
    );

    if ((guardado ?? false) && mounted) await _cargar();
  }

  /// **Mostrar o copiar**, que son dos actos y dos eventos.
  ///
  /// ⚠️ **No hay estado de «revelando»** y es deliberado: los dos botones se apagan mientras
  /// la petición está en vuelo con `_revelando`, porque pulsar dos veces dejaría **dos
  /// eventos** en la bitácora por un solo acto de la persona.
  Future<void> _revelar(PortalDeCliente portal, String acto) async {
    if (_revelando) return;

    setState(() => _revelando = true);

    final resultado = await widget.repositorio.revelarContrasenaDePortal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      portalId: portal.id,
      acto: acto,
    );

    if (!mounted) return;

    setState(() => _revelando = false);

    await resultado.when(
      ok: (contrasena) async {
        if (acto == ActoDeRevelar.copiar) {
          // ⚠️ **COPIAR PUEDE FALLAR Y HAY QUE DECIRLO.** El navegador puede negar el
          // portapapeles —sin permiso, sin gesto reciente, en una pestaña en segundo
          // plano— y entonces avisar «copiada» sería mentir: la persona pega y aparece lo
          // que tenía antes. Que no se note es lo peor de este fallo.
          var copiada = true;

          try {
            await widget.copiarAlPortapapeles(contrasena);
          } on Object {
            copiada = false;
          }

          if (!mounted) return;

          if (!copiada) {
            // 🔑 Y EL MENSAJE NO DICE «NO PASÓ NADA», porque sí pasó: el servidor ya
            // descifró y **ya dejó el evento**. Lo que falló es el último paso, así que
            // lo honesto es decir qué hacer en su lugar.
            RisegFeedback.showError(
              context,
              'El navegador no dejó copiarla. Usa Mostrar y tómala con el ratón.',
            );

            return;
          }

          // 🚫 NO SE PROMETE QUE EL PORTAPAPELES SE BORRE (C4-3). El escritorio lo borra a
          // los 60 segundos; en el navegador eso no se puede garantizar, así que decirlo
          // sería prometer una protección que no existe. Lo que protege de verdad es el
          // permiso y el evento, y el aviso dice lo que SÍ es cierto.
          RisegFeedback.showSuccess(
            context,
            'Contraseña copiada. Queda en el portapapeles hasta que copies algo más.',
          );

          return;
        }

        await showDialog<void>(
          context: context,
          builder: (_) =>
              _DialogoDeContrasenaRevelada(portal: portal, contrasena: contrasena),
        );
      },
      failure: (f) async => mostrarRechazoDelServidor(context, f),
    );
  }

  bool _revelando = false;

  /// Archiva o reactiva, **con motivo**.
  Future<void> _cambiarCicloDeVida(PortalDeCliente portal) async {
    final archivar = portal.estaActivo;

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: archivar ? 'Archivar el portal' : 'Reactivar el portal',
      etiquetaMotivo: 'Motivo',
      confirmarLabel: archivar ? 'Archivar' : 'Reactivar',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. Queda en la bitácora: por este portal se le cobra a este '
          'cliente.',
      advertencia: archivar
          ? '${portal.nombre}\n\n'
                'Archivar NO lo borra —una vigencia de cobro vieja todavía dice que se '
                'cobró por aquí— y sigue apareciendo en esta lista. Lo que no se puede '
                'es corregirlo ni cambiarle la contraseña mientras esté archivado; '
                'mostrar la que tiene, sí.'
          : '${portal.nombre}\n\nVuelve a poderse corregir y a aceptar una contraseña '
                'nueva.',
    );

    if (motivo == null || !mounted) return;

    if (motivo.length > motivoMaximo) {
      RisegFeedback.showError(context, 'El motivo se pasó de largo: recórtalo.');

      return;
    }

    final resultado = await widget.repositorio.cambiarEstatusDePortal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      portalId: portal.id,
      estatus: archivar ? 'archived' : 'active',
      motivo: motivo,
    );

    if (!mounted) return;

    await resultado.when(
      ok: (_) async {
        RisegFeedback.showSuccess(
          context,
          archivar
              ? 'Se archivó ${portal.nombre}.'
              : 'Se reactivó ${portal.nombre}.',
        );

        await _cargar();
      },
      failure: (f) async => mostrarRechazoDelServidor(context, f),
    );
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _Fila extends StatelessWidget {
  const _Fila({
    required this.portal,
    required this.puedeAdministrar,
    required this.puedeRevelar,
    required this.onCorregir,
    required this.onContrasena,
    required this.onMostrar,
    required this.onCopiar,
    required this.onCicloDeVida,
  });

  final PortalDeCliente portal;
  final bool puedeAdministrar;
  final bool puedeRevelar;
  final VoidCallback onCorregir;
  final VoidCallback onContrasena;
  final VoidCallback onMostrar;
  final VoidCallback onCopiar;
  final VoidCallback onCicloDeVida;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // UN PORTAL ARCHIVADO ES SÓLO CONSULTA, y el servidor responde 409 a quien lo intente.
    // Las acciones salen apagadas **con su porqué en el tooltip**, no escondidas.
    final sePuedeEditar = puedeAdministrar && portal.estaActivo;

    final porQueNo = portal.estaActivo
        ? null
        : 'Está archivado: reactívalo para poder cambiarlo.';

    // 🔑 Y REVELAR **SÍ** FUNCIONA ARCHIVADO: consultar un acceso retirado es legítimo. Lo
    // único que apaga estos dos botones es no tener contraseña o no tener el permiso.
    final sePuedeRevelar = puedeRevelar && portal.tieneContrasena;

    final porQueNoRevelar = !portal.tieneContrasena
        ? 'Este portal no tiene contraseña guardada.'
        : !puedeRevelar
        ? 'Ver la contraseña necesita un permiso aparte, que no tienes.'
        : null;

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
                    Flexible(
                      child: Text(
                        portal.nombre,
                        style: AppTypography.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    RisegStatusBadge(
                      label: portal.nombreDelTipo,
                      tone: RisegStatusTone.info,
                      icon: Icons.local_offer_outlined,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    RisegStatusBadge(
                      label: portal.estaActivo ? 'Activo' : 'Archivado',
                      tone: portal.estaActivo
                          ? RisegStatusTone.success
                          : RisegStatusTone.neutral,
                      icon: portal.estaActivo
                          ? Icons.check_circle_outline
                          : Icons.inventory_2_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    portal.url ?? 'Sin dirección',
                    'Usuario: ${portal.usuario ?? 'sin usuario'}',
                  ].join(' · '),
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.xxs),
                // 🔑 LO QUE SE ENSEÑA DE LA CONTRASEÑA ES QUE HAY UNA Y DE CUÁNDO ES, y
                // nada más. La fecha importa: una contraseña de hace dos años es la
                // primera sospechosa cuando el portal deja de abrir.
                Text(
                  portal.tieneContrasena
                      ? 'Contraseña: •••• · se cambió el '
                            '${fechaCorta(portal.contrasenaCambiadaEl!)}'
                      : 'Sin contraseña',
                  style: AppTypography.caption.copyWith(
                    color: portal.tieneContrasena
                        ? colors.textMuted
                        : colors.warning,
                  ),
                ),
              ],
            ),
          ),

          // LOS DOS DE REVELAR VAN PRIMERO Y SE ENSEÑAN SIEMPRE QUE SE PUEDA VER LA LISTA:
          // quien sólo consulta entra aquí justamente a eso.
          IconButton(
            tooltip: porQueNoRevelar ?? 'Mostrar la contraseña',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: sePuedeRevelar ? onMostrar : null,
          ),
          IconButton(
            tooltip: porQueNoRevelar ?? 'Copiar la contraseña',
            icon: const Icon(Icons.content_copy_outlined),
            onPressed: sePuedeRevelar ? onCopiar : null,
          ),

          if (puedeAdministrar) ...[
            IconButton(
              tooltip: porQueNo ?? 'Contraseña',
              icon: const Icon(Icons.key_outlined),
              onPressed: sePuedeEditar ? onContrasena : null,
            ),
            IconButton(
              tooltip: porQueNo ?? 'Corregir',
              icon: const Icon(Icons.edit_outlined),
              onPressed: sePuedeEditar ? onCorregir : null,
            ),
            IconButton(
              // ARCHIVAR Y REACTIVAR SIEMPRE SE PUEDEN: es la salida de un archivado.
              tooltip: portal.estaActivo ? 'Archivar' : 'Reactivar',
              icon: Icon(
                portal.estaActivo
                    ? Icons.inventory_2_outlined
                    : Icons.unarchive_outlined,
              ),
              onPressed: onCicloDeVida,
            ),
          ],
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.mensaje, this.accion});

  final IconData icono;
  final String mensaje;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: colors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            mensaje,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ),
        if (accion case final a?) ...[const SizedBox(width: AppSpacing.sm), a],
      ],
    );
  }
}

// ===========================================================================
// El panel del portal
// ===========================================================================

/// Alta y corrección de un portal. **La contraseña va aparte**, en su propio panel.
///
/// ## Por qué la contraseña no está en este formulario
///
/// Porque «dejar el campo vacío significa no cambiarla» es una regla que **se adivina mal**:
/// un campo en blanco al lado de otros cuatro llenos parece un dato que falta. Con la
/// contraseña en su propio panel, el formulario del portal **no la toca nunca** y la regla
/// deja de hacer falta. Y guardar el portal no puede borrar la contraseña por accidente,
/// que es el mismo criterio con el que el domicilio fiscal vive aparte de su razón social.
class _PanelDePortal extends StatefulWidget {
  const _PanelDePortal({
    required this.portal,
    required this.empresaId,
    required this.clienteId,
    required this.repositorio,
    required this.guardia,
  });

  final PortalDeCliente? portal;
  final String empresaId;
  final String clienteId;
  final ClientesRepositorioHttp repositorio;
  final GuardiaDeSalida guardia;

  bool get esNuevo => portal == null;

  @override
  State<_PanelDePortal> createState() => _PanelDePortalState();
}

class _PanelDePortalState extends State<_PanelDePortal>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDePortal>,
        SeCierraAlCambiarLaDireccion<_PanelDePortal> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  late final String _nombreInicial = widget.portal?.nombre ?? '';
  late final String _urlInicial = widget.portal?.url ?? '';
  late final String _usuarioInicial = widget.portal?.usuario ?? '';
  late final String _observacionesInicial = widget.portal?.observaciones ?? '';
  late final String? _tipoInicial = widget.portal?.tipo;

  @override
  bool get hayCambiosSinGuardar =>
      _nombre.text.trim() != _nombreInicial.trim() ||
      _url.text.trim() != _urlInicial.trim() ||
      _usuario.text.trim() != _usuarioInicial.trim() ||
      _observaciones.text.trim() != _observacionesInicial.trim() ||
      _tipo != _tipoInicial;

  @override
  String get queSePierde => switch (widget.portal) {
    final p? => 'el portal ${p.nombre}',
    null => 'el portal que estás dando de alta',
  };

  final _nombre = TextEditingController();
  final _url = TextEditingController();
  final _usuario = TextEditingController();
  final _observaciones = TextEditingController();

  String? _tipo;

  bool _guardando = false;
  String? _errorDeNombre;
  String? _errorDeTipo;

  @override
  void initState() {
    super.initState();

    _nombre.text = widget.portal?.nombre ?? '';
    _url.text = widget.portal?.url ?? '';
    _usuario.text = widget.portal?.usuario ?? '';
    _observaciones.text = widget.portal?.observaciones ?? '';
    _tipo = widget.portal?.tipo;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _url.dispose();
    _usuario.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: colors.surfaceSunken,
        child: SizedBox(
          width: 460,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.esNuevo ? 'Nuevo portal' : 'Corregir el portal',
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RisegTextField(
                          label: 'Nombre',
                          controller: _nombre,
                          enabled: !_guardando,
                          errorText: _errorDeNombre,
                          helperText:
                              'Cómo lo reconoce quien entra: «Portal de facturación '
                              'Sportium».',
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegSelect<String>(
                          label: 'Tipo',
                          value: _tipo,
                          hint: 'Para qué sirve este portal',
                          errorText: _errorDeTipo,
                          items: [
                            for (final t in tiposDePortal.entries)
                              RisegSelectItem(value: t.key, label: t.value),
                          ],
                          onChanged: _guardando
                              ? null
                              : (v) => setState(() => _tipo = v),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'Dirección',
                          controller: _url,
                          enabled: !_guardando,
                          helperText: 'Opcional. La página donde se entra.',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'Usuario',
                          controller: _usuario,
                          enabled: !_guardando,
                          helperText: 'Opcional. Con qué cuenta se entra.',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'Observaciones',
                          controller: _observaciones,
                          enabled: !_guardando,
                          maxLines: 3,
                          // 🚫 EL AVISO QUE DEJA DE SER UNA DEUDA EN CUANTO HAY DÓNDE. En
                          // el escritorio este campo es donde la contraseña acaba cuando el
                          // sistema no ofrece otro sitio — y ahí la ve cualquiera que pueda
                          // leer el portal. Ahora hay un sitio, y el aviso dice cuál.
                          helperText:
                              'Opcional. No escribas aquí la contraseña: tiene su '
                              'propio sitio, cifrado, con el botón de la llave.',
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                Row(
                  children: [
                    Expanded(
                      child: RisegButton(
                        label: 'Cancelar',
                        variant: RisegButtonVariant.secondary,
                        onPressed: _guardando
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: RisegButton(
                        label: 'Guardar',
                        loading: _guardando,
                        onPressed: _guardando ? null : _guardar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();

    setState(() {
      _errorDeNombre = nombre.isEmpty ? 'Falta el nombre.' : null;
      _errorDeTipo = _tipo == null ? 'Elige para qué sirve este portal.' : null;
    });

    if (_errorDeNombre != null || _errorDeTipo != null) return;

    final motivo = widget.esNuevo ? null : await _pedirElMotivo();
    if (!widget.esNuevo && (motivo == null || !mounted)) return;

    setState(() => _guardando = true);

    final url = _url.text.trim();
    final usuario = _usuario.text.trim();
    final observaciones = _observaciones.text.trim();

    final resultado = widget.esNuevo
        ? await widget.repositorio.crearPortal(
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            nombre: nombre,
            tipo: _tipo!,
            url: url.isEmpty ? null : url,
            usuario: usuario.isEmpty ? null : usuario,
            observaciones: observaciones.isEmpty ? null : observaciones,
          )
        : await widget.repositorio.modificarPortal(
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            portalId: widget.portal!.id,
            motivo: motivo!,
            // SÓLO VIAJA LO QUE CAMBIÓ: el servidor rechaza un `PATCH` que no cambia nada,
            // así que mandar el cuerpo completo haría que guardar sin tocar nada
            // respondiera un error.
            nombre: nombre == _nombreInicial.trim() ? null : nombre,
            tipo: _tipo == _tipoInicial ? null : _tipo,
            // VACIAR UN OPCIONAL SE MANDA COMO CADENA VACÍA: en este `PATCH`, nulo
            // significa «no lo toques».
            url: url == _urlInicial.trim() ? null : url,
            usuario: usuario == _usuarioInicial.trim() ? null : usuario,
            observaciones: observaciones == _observacionesInicial.trim()
                ? null
                : observaciones,
          );

    if (!mounted) return;

    resultado.when(
      ok: (_) => Navigator.of(context).pop(true),
      failure: (f) {
        setState(() => _guardando = false);

        // LOS RECHAZOS SALEN TAL CUAL, y cada uno dice qué hacer: `portal_archivado`
        // —reactívalo primero— y `cliente_terminado` —este cliente ya no admite portales
        // nuevos—.
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<String?> _pedirElMotivo() => mostrarDialogoMotivo(
    context,
    titulo: 'Corregir el portal',
    etiquetaMotivo: 'Motivo de la corrección',
    confirmarLabel: 'Guardar',
    cancelarLabel: 'Seguir editando',
    errorMotivoRequerido:
        'Falta el motivo. Queda en la bitácora: por este portal se le cobra a este '
        'cliente.',
  );
}

// ===========================================================================
// El panel de la contraseña
// ===========================================================================

/// **Fijar, cambiar o borrar la contraseña de un portal.**
///
/// ## Por qué es un panel propio y no un campo del formulario
///
/// Dos razones, y la segunda es la que importa:
///
///  1. **guardar el portal no puede borrar la contraseña por accidente**, porque este panel
///     es el único que la toca;
///  2. **borrarla es un acto, no un campo vacío.** El servidor lo impone —una contraseña
///     vacía se rechaza, y borrarla tiene su propia ruta y su propio evento—, así que la
///     pantalla ofrece **un botón de borrar** en vez de esperar que alguien deduzca que
///     dejar el campo en blanco y guardar hace algo.
///
/// 🚫 **No se enseña la que hay**, ni enmascarada con su largo real: el campo nace vacío y
/// lo que se escriba **sustituye**. Precargarlo obligaría a revelarla para poder dibujarla,
/// y entonces abrir este panel sería un acto de revelar sin su permiso ni su evento.
class _PanelDeContrasena extends StatefulWidget {
  const _PanelDeContrasena({
    required this.portal,
    required this.empresaId,
    required this.clienteId,
    required this.repositorio,
    required this.guardia,
  });

  final PortalDeCliente portal;
  final String empresaId;
  final String clienteId;
  final ClientesRepositorioHttp repositorio;
  final GuardiaDeSalida guardia;

  @override
  State<_PanelDeContrasena> createState() => _PanelDeContrasenaState();
}

class _PanelDeContrasenaState extends State<_PanelDeContrasena>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDeContrasena>,
        SeCierraAlCambiarLaDireccion<_PanelDeContrasena> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// ⚠️ **SE COMPARA CONTRA VACÍO Y NO CONTRA «LO CARGADO»**, que es la única excepción
  /// honesta a la regla de D-53: aquí no hay nada cargado —la contraseña que hay no se lee
  /// para dibujarla—, así que cualquier cosa escrita **es** trabajo sin guardar.
  @override
  bool get hayCambiosSinGuardar => _contrasena.text.isNotEmpty;

  @override
  String get queSePierde => 'la contraseña de ${widget.portal.nombre}';

  final _contrasena = TextEditingController();

  bool _guardando = false;
  bool _aLaVista = false;
  String? _error;

  @override
  void dispose() {
    _contrasena.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: colors.surfaceSunken,
        child: SizedBox(
          width: 460,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.portal.tieneContrasena
                      ? 'Cambiar la contraseña'
                      : 'Guardar la contraseña',
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.portal.nombre,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RisegTextField(
                          label: 'Contraseña',
                          controller: _contrasena,
                          enabled: !_guardando,
                          errorText: _error,
                          obscureText: !_aLaVista,
                          autofocus: true,
                          // ⚠️ LA DE ANTES NO SE ENSEÑA, Y SE DICE POR QUÉ. Sin esta
                          // frase, un campo vacío donde ya hay una contraseña parece un
                          // error de carga.
                          helperText: widget.portal.tieneContrasena
                              ? 'La que hay no se muestra aquí. Lo que escribas la '
                                    'sustituye, y la anterior no se guarda en ninguna '
                                    'parte.'
                              : 'Se guarda cifrada. Nadie puede verla sin el permiso de '
                                    'mostrarla, y cada vez que alguien la vea queda '
                                    'registrado.',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: RisegButton(
                            // VER LO QUE SE ESTÁ ESCRIBIENDO NO ES REVELAR: es el texto
                            // de esta persona, que todavía no ha salido de la pantalla.
                            // No pide el permiso de mostrar ni deja evento.
                            label: _aLaVista ? 'Ocultar' : 'Ver lo que escribo',
                            icon: _aLaVista
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            variant: RisegButtonVariant.ghost,
                            size: RisegButtonSize.compact,
                            onPressed: () =>
                                setState(() => _aLaVista = !_aLaVista),
                          ),
                        ),

                        if (widget.portal.tieneContrasena) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            'Dejar el portal sin contraseña',
                            style: AppTypography.bodyStrong,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Es otro acto, y no se puede deshacer: no se guarda ninguna '
                            'contraseña anterior.',
                            style: AppTypography.caption.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: RisegButton(
                              label: 'Borrar la contraseña',
                              icon: Icons.delete_outline,
                              variant: RisegButtonVariant.secondary,
                              size: RisegButtonSize.compact,
                              onPressed: _guardando ? null : _borrar,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                Row(
                  children: [
                    Expanded(
                      child: RisegButton(
                        label: 'Cancelar',
                        variant: RisegButtonVariant.secondary,
                        onPressed: _guardando
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: RisegButton(
                        label: 'Guardar',
                        loading: _guardando,
                        onPressed: _guardando ? null : _guardar,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    final contrasena = _contrasena.text;

    // 🚫 NO SE RECORTA. Una contraseña puede terminar en un espacio a propósito, y
    // «limpiarla» guardaría una que el portal del cliente no acepta — y el fallo
    // aparecería al intentar entrar, lejos de aquí. Lo único que se rechaza es vacío.
    setState(
      () => _error = contrasena.trim().isEmpty
          ? 'Escribe la contraseña. Para dejar el portal sin ninguna, bórrala.'
          : null,
    );

    if (_error != null) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.fijarContrasenaDePortal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      portalId: widget.portal.id,
      contrasena: contrasena,
    );

    if (!mounted) return;

    resultado.when(
      ok: (_) {
        RisegFeedback.showSuccess(
          context,
          'Se guardó la contraseña de ${widget.portal.nombre}.',
        );

        Navigator.of(context).pop(true);
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<void> _borrar() async {
    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: 'Borrar la contraseña',
      message:
          '${widget.portal.nombre}\n\nEl portal se queda sin contraseña. No se guarda '
          'ninguna anterior, así que habrá que capturarla de nuevo.',
      confirmLabel: 'Borrar',
      cancelLabel: 'Cancelar',
      destructive: true,
    );

    if (!(confirmado ?? false) || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.borrarContrasenaDePortal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      portalId: widget.portal.id,
    );

    if (!mounted) return;

    resultado.when(
      ok: (_) {
        RisegFeedback.showSuccess(
          context,
          '${widget.portal.nombre} se quedó sin contraseña.',
        );

        Navigator.of(context).pop(true);
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }
}

// ===========================================================================
// La contraseña, a la vista
// ===========================================================================

/// La contraseña revelada, **en un diálogo que se la lleva al cerrarse**.
///
/// 🔑 **No se guarda en ningún campo de estado de la pantalla**, y por eso recargar el
/// expediente la vuelve a ocultar sin que nadie tenga que acordarse de limpiarla: nunca
/// estuvo guardada. Verla otra vez es **otro acto**, con su propio evento.
class _DialogoDeContrasenaRevelada extends StatelessWidget {
  const _DialogoDeContrasenaRevelada({
    required this.portal,
    required this.contrasena,
  });

  final PortalDeCliente portal;
  final String contrasena;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      title: Text(portal.nombre, style: AppTypography.heading3),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (portal.usuario case final u?) ...[
            Text(
              'Usuario: $u',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            // SELECCIONABLE: quien no tiene el permiso de copiar —o prefiere no dejar el
            // evento de copiar— tiene que poder tomarla con el ratón.
            child: SelectableText(
              contrasena,
              style: AppTypography.bodyStrong.copyWith(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Queda registrado que la viste. Al cerrar, se oculta.',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
      actions: [
        RisegButton(
          label: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
