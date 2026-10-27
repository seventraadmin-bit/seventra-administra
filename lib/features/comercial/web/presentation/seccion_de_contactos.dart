import 'package:flutter/material.dart';

import '../../../../app/shell/se_cierra_al_cambiar_la_direccion.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/clientes_repositorio_http.dart';
import '../modelos/contacto.dart';

/// **Los contactos de un cliente**, con sus tres tipos y un principal por tipo.
///
/// ## Las cuatro acciones, y cuál pide motivo
///
/// | Acción | Motivo | Por qué |
/// |---|---|---|
/// | **Añadir** | no | el motivo es para corregir, no para crear |
/// | **Corregir** | **sí** | es R2 de los actos que lo piden, y el servidor lo valida antes que los campos |
/// | **Designar principal** | no | tiene su propia ruta y el servidor pone el motivo solo: es un acto con nombre, no una edición |
/// | **Eliminar** | **sí** | la fila se va, así que el motivo es lo único que dirá por qué dejó de existir |
///
/// ## ⚠️ ELIMINAR NO ES ARCHIVAR, y conviene que se vea en pantalla
///
/// El escritorio archiva el contacto y el archivado desaparece de la vista. Aquí **la fila
/// se borra**, y es del contrato del servidor: «no son historia de nada, y son listas donde
/// una fila capturada por error no se puede corregir sobrescribiendo». El diálogo lo dice
/// con esas palabras en lugar de llamarlo «archivar», que prometería poder recuperarlo.
///
/// Lo que sí queda es el **evento de la bitácora**, con el nombre, el tipo, si era
/// principal y las vías de contacto **enmascaradas**.
///
/// ## Y no se elimina al responsable de un servicio
///
/// El servidor lo bloquea **nombrando el servicio**, y la pantalla muestra ese mensaje tal
/// cual: es lo único que dice dónde ir a cambiar el responsable.
class SeccionDeContactos extends StatefulWidget {
  const SeccionDeContactos({
    required this.repositorio,
    required this.empresaId,
    required this.clienteId,
    required this.puedeAdministrar,
    required this.guardia,
    super.key,
  });

  final ClientesRepositorioHttp repositorio;
  final String empresaId;
  final String clienteId;

  /// `clients_events_services.manage`, resuelto por el shell. **Lo que no se puede hacer
  /// no se muestra.**
  final bool puedeAdministrar;

  /// D-56 · para el panel de alta y edición, que es el que tiene campos.
  final GuardiaDeSalida guardia;

  @override
  State<SeccionDeContactos> createState() => _SeccionDeContactosState();
}

class _SeccionDeContactosState extends State<SeccionDeContactos> {
  List<ContactoDeCliente>? _contactos;
  Failure? _fallo;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(SeccionDeContactos anterior) {
    super.didUpdateWidget(anterior);

    // CAMBIAR DE CLIENTE SIN DESMONTAR PASA: las dos direcciones son la misma ruta con
    // otro `<id>`, así que go_router reutiliza el `State` de arriba y este con él.
    if (anterior.clienteId != widget.clienteId) _cargar();
  }

  Future<void> _cargar() async {
    final id = widget.clienteId;

    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.listarContactos(
      empresaId: widget.empresaId,
      clienteId: id,
    );

    if (!mounted || widget.clienteId != id) return;

    resultado.when(
      ok: (contactos) => setState(() {
        _contactos = contactos;
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
      title: 'Contactos',
      description:
          'Con quién se habla, y para qué. Puede haber un principal de cada tipo: la '
          'factura va al de cobranza, que no es el comercial.',
      children: [
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_fallo case final f?)
          _Aviso(
            icono: Icons.cloud_off_outlined,
            mensaje: 'No se pudieron cargar los contactos: ${f.message}',
            accion: RisegButton(
              label: 'Intentar de nuevo',
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _cargar,
            ),
          )
        else if ((_contactos ?? const []).isEmpty)
          const _Aviso(
            icono: Icons.person_add_alt,
            mensaje:
                'Este cliente todavía no tiene contactos. Sin uno de cobranza, la '
                'factura no sabe a quién llegarle.',
          )
        else
          for (final c in _contactos!)
            _Fila(
              contacto: c,
              puedeAdministrar: widget.puedeAdministrar,
              onEditar: () => _abrirPanel(c),
              onPrincipal: c.esPrincipal ? null : () => _designar(c),
              onEliminar: () => _eliminar(c),
            ),

        if (widget.puedeAdministrar) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: RisegButton(
              label: 'Añadir contacto',
              icon: Icons.add,
              variant: RisegButtonVariant.secondary,
              size: RisegButtonSize.compact,
              onPressed: _cargando ? null : () => _abrirPanel(null),
            ),
          ),
        ],

        if (!widget.puedeAdministrar && (_contactos ?? const []).isNotEmpty)
          Text(
            'Para añadir o corregir contactos hace falta el permiso de administrar '
            'clientes y servicios.',
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
      ],
    );
  }

  Future<void> _abrirPanel(ContactoDeCliente? contacto) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeContacto(
        contacto: contacto,
        empresaId: widget.empresaId,
        clienteId: widget.clienteId,
        repositorio: widget.repositorio,
        guardia: widget.guardia,
      ),
    );

    if ((guardado ?? false) && mounted) await _cargar();
  }

  /// Designa al principal **de su tipo**. Sin motivo: lo pone el servidor.
  Future<void> _designar(ContactoDeCliente contacto) async {
    final resultado = await widget.repositorio.designarPrincipal(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      contactoId: contacto.id,
    );

    if (!mounted) return;

    await resultado.when(
      ok: (_) async {
        // SE DICE DE QUÉ TIPO, porque es la pregunta que la persona se hace: designar al
        // de cobranza no le quita la marca al comercial.
        final tipo = contacto.comoTipo?.nombre.toLowerCase() ?? contacto.tipo;

        RisegFeedback.showSuccess(
          context,
          '${contacto.nombre} es el contacto $tipo principal.',
        );

        await _cargar();
      },
      failure: (f) async => mostrarRechazoDelServidor(context, f),
    );
  }

  /// Elimina un contacto, con motivo. **La fila se va**, y el diálogo lo dice.
  Future<void> _eliminar(ContactoDeCliente contacto) async {
    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Eliminar el contacto',
      etiquetaMotivo: 'Motivo',
      confirmarLabel: 'Eliminar',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. La fila se borra, así que el motivo es lo único que '
          'quedará de este contacto.',
      // ⚠️ SE DICE QUE SE BORRA, Y QUE NO SE PUEDE RECUPERAR. Llamarlo «archivar»
      // —como el escritorio— prometería poder volver atrás, y aquí no se puede.
      advertencia:
          '${contacto.nombre}${contacto.puesto == null ? '' : ' (${contacto.puesto})'}\n\n'
          'El contacto se elimina y no se puede recuperar. En la bitácora queda su '
          'nombre, su tipo y sus datos de contacto parcialmente ocultos, con tu motivo.',
      destructivo: true,
    );

    if (motivo == null || !mounted) return;

    if (motivo.length > motivoMaximo) {
      RisegFeedback.showError(
        context,
        'El motivo admite hasta $motivoMaximo caracteres; escribiste ${motivo.length}.',
      );

      return;
    }

    final resultado = await widget.repositorio.eliminarContacto(
      empresaId: widget.empresaId,
      clienteId: widget.clienteId,
      contactoId: contacto.id,
      motivo: motivo,
    );

    if (!mounted) return;

    await resultado.when(
      ok: (_) async {
        RisegFeedback.showSuccess(
          context,
          'Se eliminó el contacto ${contacto.nombre}.',
        );

        await _cargar();
      },
      // EL MENSAJE DEL SERVIDOR SALE TAL CUAL, y aquí es lo importante: cuando el
      // contacto es responsable de un servicio, **nombra el servicio** — y eso es lo
      // único que dice dónde ir a cambiar el responsable.
      failure: (f) async => mostrarRechazoDelServidor(context, f),
    );
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _Fila extends StatelessWidget {
  const _Fila({
    required this.contacto,
    required this.puedeAdministrar,
    required this.onEditar,
    required this.onPrincipal,
    required this.onEliminar,
  });

  final ContactoDeCliente contacto;
  final bool puedeAdministrar;
  final VoidCallback onEditar;

  /// Nulo cuando **ya es el principal**: marcar al que ya está no hace nada.
  final VoidCallback? onPrincipal;

  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
                        contacto.nombre,
                        style: AppTypography.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _InsigniaDeTipo(contacto: contacto),
                    if (contacto.esPrincipal) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const RisegStatusBadge(
                        label: 'Principal',
                        tone: RisegStatusTone.info,
                        icon: Icons.star_outline,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    if (contacto.puesto case final p?) p,
                    contacto.vias,
                  ].join(' — '),
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),

          if (puedeAdministrar) ...[
            IconButton(
              // EL TOOLTIP DICE DE QUÉ TIPO: «principal» a secas haría pensar que hay uno
              // solo para todo el cliente.
              tooltip: onPrincipal == null
                  ? 'Ya es el principal de su tipo'
                  : 'Designar principal de ${contacto.comoTipo?.nombre.toLowerCase() ?? contacto.tipo}',
              icon: Icon(
                contacto.esPrincipal ? Icons.star : Icons.star_outline,
                color: contacto.esPrincipal ? colors.accent : colors.textMuted,
              ),
              onPressed: onPrincipal,
            ),
            IconButton(
              tooltip: 'Corregir',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEditar,
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: onEliminar,
            ),
          ],
        ],
      ),
    );
  }
}

/// La insignia del tipo. **Uno desconocido se enseña tal cual**, igual que el estatus de un
/// cliente: un `_ => comercial` diría algo falso de un contacto.
class _InsigniaDeTipo extends StatelessWidget {
  const _InsigniaDeTipo({required this.contacto});

  final ContactoDeCliente contacto;

  @override
  Widget build(BuildContext context) => switch (contacto.comoTipo) {
    TipoDeContacto.comercial => const RisegStatusBadge(
      label: 'Comercial',
      tone: RisegStatusTone.neutral,
      icon: Icons.handshake_outlined,
    ),
    TipoDeContacto.operativo => const RisegStatusBadge(
      label: 'Operativo',
      tone: RisegStatusTone.neutral,
      icon: Icons.build_outlined,
    ),
    TipoDeContacto.cobranza => const RisegStatusBadge(
      label: 'Cobranza',
      tone: RisegStatusTone.neutral,
      icon: Icons.request_quote_outlined,
    ),
    null => RisegStatusBadge(
      label: contacto.tipo,
      tone: RisegStatusTone.neutral,
      icon: Icons.help_outline,
    ),
  };
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
// El panel de alta y corrección
// ===========================================================================

/// Alta y corrección de un contacto.
///
/// **Panel lateral y no diálogo centrado**, igual que los cinco de Organización y por la
/// misma razón que se escribió allí: en web el modal se siente viejo y se rompe en
/// pantallas pequeñas, y un panel deja ver detrás el contexto de lo que se escribe.
///
/// ⚠️ **NO HAY CASILLA DE «PRINCIPAL», y es del contrato**: designar al principal tiene su
/// propia ruta para que quede en la traza como el acto que es. Una casilla aquí lo
/// convertiría en el efecto colateral de una edición — y además no habría forma de
/// desmarcarla, porque siempre hay un principal por tipo en cuanto hay uno.
class _PanelDeContacto extends StatefulWidget {
  const _PanelDeContacto({
    required this.contacto,
    required this.empresaId,
    required this.clienteId,
    required this.repositorio,
    required this.guardia,
  });

  final ContactoDeCliente? contacto;
  final String empresaId;
  final String clienteId;
  final ClientesRepositorioHttp repositorio;
  final GuardiaDeSalida guardia;

  bool get esNuevo => contacto == null;

  @override
  State<_PanelDeContacto> createState() => _PanelDeContactoState();
}

class _PanelDeContactoState extends State<_PanelDeContacto>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDeContacto>,
        SeCierraAlCambiarLaDireccion<_PanelDeContacto> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Las bases, **perezosas**: el mixin registra en el `super.initState()`, antes de que
  /// este estado haya acabado de armarse.
  late final String _nombreInicial = widget.contacto?.nombre ?? '';
  late final String _puestoInicial = widget.contacto?.puesto ?? '';
  late final String _telefonoInicial = widget.contacto?.telefono ?? '';
  late final String _correoInicial = widget.contacto?.correo ?? '';
  late final TipoDeContacto? _tipoInicial = widget.contacto?.comoTipo;

  @override
  bool get hayCambiosSinGuardar =>
      _nombre.text.trim() != _nombreInicial.trim() ||
      _puesto.text.trim() != _puestoInicial.trim() ||
      _telefono.text.trim() != _telefonoInicial.trim() ||
      _correo.text.trim() != _correoInicial.trim() ||
      _tipo != _tipoInicial;

  /// **El nombre GUARDADO y no el del campo**: a quien está renombrando, la pregunta le
  /// hablaría de alguien que todavía no existe con ese nombre.
  @override
  String get queSePierde => switch (widget.contacto) {
    final c? => 'el contacto ${c.nombre}',
    null => 'el contacto que estás dando de alta',
  };

  final _nombre = TextEditingController();
  final _puesto = TextEditingController();
  final _telefono = TextEditingController();
  final _correo = TextEditingController();

  TipoDeContacto? _tipo;

  bool _guardando = false;

  String? _errorDeNombre;
  String? _errorDeTipo;
  String? _errorDeVias;

  @override
  void initState() {
    super.initState();

    final c = widget.contacto;

    _nombre.text = c?.nombre ?? '';
    _puesto.text = c?.puesto ?? '';
    _telefono.text = c?.telefono ?? '';
    _correo.text = c?.correo ?? '';
    _tipo = c?.comoTipo;
  }

  @override
  void dispose() {
    for (final c in [_nombre, _puesto, _telefono, _correo]) {
      c.dispose();
    }

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
          width: 440,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.esNuevo ? 'Nuevo contacto' : 'Corregir el contacto',
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
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegSelect<TipoDeContacto>(
                          label: 'Tipo',
                          value: _tipo,
                          hint: 'Elige para qué es este contacto',
                          errorText: _errorDeTipo,
                          // LA AYUDA DICE PARA QUÉ SIRVE CADA UNO. Sin esto, «comercial»
                          // y «cobranza» se eligen al azar la primera vez.
                          helperText: _tipo?.paraQue,
                          items: [
                            for (final t in TipoDeContacto.values)
                              RisegSelectItem(value: t, label: t.nombre),
                          ],
                          onChanged: _guardando
                              ? null
                              : (v) => setState(() => _tipo = v),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'Puesto',
                          controller: _puesto,
                          enabled: !_guardando,
                          helperText: 'Opcional.',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'Teléfono',
                          controller: _telefono,
                          enabled: !_guardando,
                          errorText: _errorDeVias,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'Correo',
                          controller: _correo,
                          enabled: !_guardando,
                          keyboardType: TextInputType.emailAddress,
                          // LA REGLA DEL SERVIDOR, DICHA DONDE SE ESCRIBE: un contacto sin
                          // ninguna vía no sirve de nada, y el servidor lo rechaza.
                          helperText: 'Hace falta al menos un teléfono o un correo.',
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
    final telefono = _telefono.text.trim();
    final correo = _correo.text.trim();

    setState(() {
      _errorDeNombre = nombre.isEmpty ? 'Falta el nombre.' : null;
      _errorDeTipo = _tipo == null ? 'Elige el tipo.' : null;

      // LAS TRES SE PARAN AQUÍ porque el servidor las rechaza igual y con el formulario
      // delante no hace falta ir a preguntarlo. **No sustituyen al servidor**: si acepta
      // algo que él rechaza, su mensaje sale tal cual.
      _errorDeVias = telefono.isEmpty && correo.isEmpty
          ? 'Hace falta al menos un teléfono o un correo.'
          : null;
    });

    if (_errorDeNombre != null || _errorDeTipo != null || _errorDeVias != null) {
      return;
    }

    final motivo = widget.esNuevo ? null : await _pedirElMotivo();

    // EL ALTA NO PIDE MOTIVO; la corrección sí, y cancelarlo no guarda nada.
    if (!widget.esNuevo && (motivo == null || !mounted)) return;

    setState(() => _guardando = true);

    final resultado = widget.esNuevo
        ? await widget.repositorio.crearContacto(
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            nombre: nombre,
            tipo: _tipo!,
            puesto: _opcional(_puesto.text),
            telefono: _opcional(telefono),
            correo: _opcional(correo),
          )
        : await widget.repositorio.modificarContacto(
            empresaId: widget.empresaId,
            clienteId: widget.clienteId,
            contactoId: widget.contacto!.id,
            motivo: motivo!,
            // ⚠️ **LOS OPCIONALES SE MANDAN COMO CADENA VACÍA PARA VACIARLOS**, no como
            // nulo: en este `PATCH` `null` significa «no lo toques», así que con nulo no
            // habría forma de quitar un puesto. El servidor recorta la cadena vacía a
            // nulo.
            nombre: nombre == _nombreInicial.trim() ? null : nombre,
            tipo: _tipo == _tipoInicial ? null : _tipo,
            puesto: _puesto.text.trim() == _puestoInicial.trim()
                ? null
                : _puesto.text.trim(),
            telefono: telefono == _telefonoInicial.trim() ? null : telefono,
            correo: correo == _correoInicial.trim() ? null : correo,
          );

    if (!mounted) return;

    resultado.when(
      ok: (_) => Navigator.of(context).pop(true),
      failure: (f) {
        setState(() => _guardando = false);

        // EL 409 DE «UN PRINCIPAL POR TIPO» SALE TAL CUAL: dice qué resolver —«designa
        // otro principal de ese tipo antes de moverlo»— y eso no es un error de campo.
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  static String? _opcional(String texto) {
    final t = texto.trim();

    return t.isEmpty ? null : t;
  }

  Future<String?> _pedirElMotivo() => mostrarDialogoMotivo(
    context,
    titulo: 'Corregir el contacto',
    etiquetaMotivo: 'Motivo de la corrección',
    confirmarLabel: 'Guardar',
    cancelarLabel: 'Seguir editando',
    errorMotivoRequerido:
        'Falta el motivo. Queda en la bitácora y es lo que explica por qué cambió '
        'este dato.',
  );
}
