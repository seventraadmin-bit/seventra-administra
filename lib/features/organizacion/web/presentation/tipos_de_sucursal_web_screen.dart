import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL: esta feature no puede importar el catálogo de
// permisos y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/sucursales_repositorio_http.dart';
import '../modelos/tipo_de_sucursal.dart';
import 'eliminar_estructura.dart';

/// Tipos de sucursal: el catálogo con el que el cliente clasifica sus sucursales.
///
/// ## No es una pestaña, y es una decisión
///
/// Vive **dentro de Sucursales**, detrás de un botón. Un cliente abre «Sucursales»
/// para ver sus sucursales; los tipos son el catálogo que las ordena, y no merecen el
/// mismo peso en la navegación que la cosa que ordenan.
///
/// ## El botón de recomendados existe porque el alta en blanco es un muro
///
/// Dar de alta una sucursal **exige** un tipo. Una empresa nueva tiene cero, así que
/// su primera sucursal es imposible hasta que alguien invente un catálogo. El
/// servidor trae un juego recomendado justo para eso, y el botón lo agrega de una vez.
///
/// **Y es idempotente:** salta los que ya existen por código. Pulsarlo dos veces no
/// duplica nada, y la segunda vez crea cero — que es un resultado distinto de un
/// error y se dice distinto.
class TiposDeSucursalWebScreen extends StatefulWidget {
  const TiposDeSucursalWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.esMaestro,
    required this.capacidades,
    this.onVolver,
    super.key,
  });

  final SucursalesRepositorioHttp repositorio;
  final String empresaId;

  /// Si quien mira es Maestro. **Sólo gobierna si el botón de eliminar se OFRECE**,
  /// nunca si se puede: eso lo decide el servidor.
  final bool esMaestro;

  /// Qué puede hacer aquí quien mira.
  ///
  /// **EL CATÁLOGO DE TIPOS SIGUE EL MISMO MAPA que el resto de la estructura**, por
  /// decisión del dueño: no tiene permisos propios. Verlo es `organizacion.ver`,
  /// crear un tipo es `organizacion.crear`, renombrarlo `organizacion.modificar` y
  /// el interruptor `organizacion.archivar`.
  final CapacidadesDeModulo capacidades;

  /// Cómo se vuelve a Sucursales. `null` cuando se muestra sola.
  final VoidCallback? onVolver;

  @override
  State<TiposDeSucursalWebScreen> createState() => _TiposDeSucursalWebScreenState();
}

class _TiposDeSucursalWebScreenState extends State<TiposDeSucursalWebScreen> {
  List<TipoDeSucursal>? _tipos;
  Failure? _fallo;
  bool _cargando = true;
  bool _agregandoRecomendados = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.listarTipos(widget.empresaId);

    if (!mounted) return;

    resultado.when(
      ok: (tipos) => setState(() {
        _tipos = tipos;
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  Future<void> _agregarRecomendados() async {
    // LO QUE HABÍA ANTES, CAPTURADO ANTES DE LLAMAR. Es lo único que permite decir
    // cuántos se crearon de verdad.
    final antes = _tipos;

    setState(() => _agregandoRecomendados = true);

    final resultado = await widget.repositorio.agregarTiposRecomendados(
      widget.empresaId,
    );

    if (!mounted) return;

    setState(() => _agregandoRecomendados = false);

    resultado.when(
      ok: (resultantes) {
        // ⚠️ `resultantes` ES EL CONJUNTO RESULTANTE, NO LO QUE SE CREÓ. Al segundo
        // clic devuelve los tres otra vez, así que contar su longitud diría «Se
        // agregaron 3» cuando no se creó ninguno. La base queda bien —el endpoint es
        // idempotente— pero el mensaje mentiría.
        //
        // SIN SABER QUÉ HABÍA ANTES NO SE INVENTA UN NÚMERO. Si la lista no se había
        // podido cargar, se dice lo único que es cierto en los dos casos.
        if (antes == null) {
          RisegFeedback.showSuccess(
            context,
            'Los tipos recomendados ya están en tu catálogo.',
          );
          return;
        }

        final nuevos = tiposNuevos(antes: antes, despues: resultantes);

        // CERO NUEVOS NO ES UN ERROR, Y DECIR «LISTO» SERÍA ENGAÑOSO: significa que ya
        // estaban todos, y eso es lo que se dice.
        RisegFeedback.showSuccess(
          context,
          switch (nuevos.length) {
            0 => 'Ya tenías todos los tipos recomendados.',
            1 => 'Se agregó 1 tipo recomendado.',
            final n => 'Se agregaron $n tipos recomendados.',
          },
        );
      },
      failure: (f) => RisegFeedback.showError(context, f.message),
    );

    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = _tipos?.length ?? 0;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.onVolver case final volver?) ...[
                // EL REGRESO VA ARRIBA Y A LA IZQUIERDA, donde se busca. No es una
                // pestaña, así que sin esto no habría forma de salir.
                InkWell(
                  onTap: volver,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 16, color: colors.accent),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'Sucursales',
                          style: AppTypography.caption.copyWith(color: colors.accent),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tipos de sucursal',
                          style: AppTypography.heading1,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          total == 1 ? '1 tipo' : '$total tipos',
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // SIN `crear`, EL CATÁLOGO SE CONSULTA Y NADA MÁS: los dos botones
                  // crean filas, y el de recomendados crea tres de un golpe.
                  //
                  // EL DE RECOMENDADOS VA SECUNDARIO Y A LA IZQUIERDA del principal:
                  // es un atajo para empezar, no la forma normal de crear un tipo.
                  if (widget.capacidades.puedeCrear) ...[
                    RisegButton(
                      label: 'Agregar tipos recomendados',
                      variant: RisegButtonVariant.secondary,
                      icon: Icons.auto_awesome_outlined,
                      loading: _agregandoRecomendados,
                      onPressed: _cargando ? null : _agregarRecomendados,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    RisegButton(
                      label: 'Nuevo tipo',
                      icon: Icons.add,
                      onPressed: _cargando ? null : () => _abrirPanel(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: _cuerpo()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los tipos',
        message: f.message,
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    final tipos = _tipos ?? const <TipoDeSucursal>[];

    if (tipos.isEmpty) {
      // EL VACÍO EXPLICA QUÉ ES Y OFRECE EL ATAJO, porque aquí empieza todo: sin un
      // tipo no se puede dar de alta ninguna sucursal.
      return RisegEmptyState(
        icon: Icons.category_outlined,
        title: 'Todavía no hay tipos de sucursal',
        message:
            'Un tipo clasifica tus sucursales —oficina, bodega, caseta— y hace falta '
            'al menos uno para dar de alta la primera. Puedes empezar con los '
            'recomendados y cambiarlos después.',
        // EL VACÍO TAMBIÉN CREA —tres de golpe—, así que pide `crear`.
        primaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Agregar tipos recomendados',
                icon: Icons.auto_awesome_outlined,
                loading: _agregandoRecomendados,
                onPressed: _agregarRecomendados,
              )
            : null,
      );
    }

    return ListView.separated(
      itemCount: tipos.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _Fila(
        tipo: tipos[i],
        onTocar: () => _abrirPanel(tipo: tipos[i]),
      ),
    );
  }

  Future<void> _abrirPanel({TipoDeSucursal? tipo}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeTipo(
        tipo: tipo,
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
        esMaestro: widget.esMaestro,
        capacidades: widget.capacidades,
      ),
    );

    if (guardado ?? false) await _cargar();
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.tipo, required this.onTocar});

  final TipoDeSucursal tipo;
  final VoidCallback onTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tipo.nombre, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    tipo.codigo,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            // COLOR MÁS ÍCONO, no sólo color: quien no distingue verde de gris sigue
            // viendo la diferencia.
            RisegStatusBadge(
              label: tipo.activo ? 'Activo' : 'Inactivo',
              tone: tipo.activo ? RisegStatusTone.success : RisegStatusTone.neutral,
              icon: tipo.activo
                  ? Icons.check_circle_outline
                  : Icons.remove_circle_outline,
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// El panel de alta y edición
// ===========================================================================

class _PanelDeTipo extends StatefulWidget {
  const _PanelDeTipo({
    required this.tipo,
    required this.empresaId,
    required this.repositorio,
    required this.esMaestro,
    required this.capacidades,
  });

  /// Qué se puede hacer: campos con `puedeModificar` —o `puedeCrear` si es nuevo—,
  /// interruptor con `puedeArchivar`, y el borrado con el rol más `puedeArchivar`.
  final CapacidadesDeModulo capacidades;

  /// ¿Hay algo que guardar?
  bool get sePuedeGuardar => tipo == null
      ? capacidades.puedeCrear
      : capacidades.puedeModificar || capacidades.puedeArchivar;

  final TipoDeSucursal? tipo;
  final String empresaId;
  final SucursalesRepositorioHttp repositorio;
  final bool esMaestro;

  @override
  State<_PanelDeTipo> createState() => _PanelDeTipoState();
}

class _PanelDeTipoState extends State<_PanelDeTipo> {
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();

  bool _activo = true;
  bool _guardando = false;
  bool _eliminando = false;
  String? _errorDeCodigo;
  String? _errorDeNombre;

  bool get _esNuevo => widget.tipo == null;

  @override
  void initState() {
    super.initState();

    if (widget.tipo case final t?) {
      _codigo.text = t.codigo;
      _nombre.text = t.nombre;
      _activo = t.activo;
    }
  }

  @override
  void dispose() {
    // Liberar los controllers no es opcional, y en este proyecto ya costó una vez.
    _codigo.dispose();
    _nombre.dispose();
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
          width: 420,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // EL TÍTULO NO PROMETE LO QUE NO SE PUEDE.
                  !widget.sePuedeGuardar
                      ? 'Tipo de sucursal'
                      : (_esNuevo ? 'Nuevo tipo de sucursal' : 'Editar tipo'),
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                // EL CÓDIGO NO SE PUEDE CAMBIAR AL EDITAR, y el campo lo dice en
                // lugar de aceptarlo y descartarlo en silencio: es la identidad del
                // tipo, y la ruta no lo recibe en un `PATCH`.
                RisegTextField(
                  label: 'Código',
                  controller: _codigo,
                  enabled: widget.capacidades.puedeCrear && _esNuevo,
                  errorText: _errorDeCodigo,
                  helperText: _esNuevo
                      ? 'Corto y en mayúsculas, como OFI. No se podrá cambiar.'
                      : 'El código no se cambia.',
                ),
                const SizedBox(height: AppSpacing.md),

                RisegTextField(
                  label: 'Nombre',
                  controller: _nombre,
                  enabled: _esNuevo
                      ? widget.capacidades.puedeCrear
                      : widget.capacidades.puedeModificar,
                  errorText: _errorDeNombre,
                  helperText: 'Lo que vas a leer en las listas, como Oficina.',
                ),
                const SizedBox(height: AppSpacing.md),

                if (!_esNuevo)
                  Row(
                    children: [
                      Switch(
                        value: _activo,
                        // EL INTERRUPTOR ES «ARCHIVAR», en las dos direcciones.
                        onChanged: widget.capacidades.puedeArchivar
                            ? (v) => setState(() => _activo = v)
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _activo
                              ? 'Activo: se puede elegir al dar de alta una sucursal.'
                              : 'Inactivo: desaparece de los selectores, pero las '
                                    'sucursales que ya lo usan no cambian.',
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),

                const Spacer(),

                // UNA FICHA SE CIERRA; UN FORMULARIO SE CANCELA O SE GUARDA.
                if (!widget.sePuedeGuardar)
                  Row(
                    children: [
                      const Spacer(),
                      RisegButton(
                        label: 'Cerrar',
                        variant: RisegButtonVariant.secondary,
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  )
                else
                Row(
                  children: [
                    const Spacer(),
                    RisegButton(
                      label: 'Cancelar',
                      variant: RisegButtonVariant.secondary,
                      onPressed: _guardando || _eliminando
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    RisegButton(
                      label: 'Guardar',
                      loading: _guardando,
                      onPressed: _guardando || _eliminando ? null : _guardar,
                    ),
                  ],
                ),

                // ELIMINAR, APARTE Y ABAJO. Un tipo creado de más es el caso más
                // común de los cuatro: el botón de recomendados crea tres, y puede que
                // la empresa sólo use dos.
                // EL ROL Y ADEMÁS `archivar`, igual que en el servidor.
                if (!_esNuevo && widget.esMaestro && widget.capacidades.puedeArchivar) ...[
                  const Divider(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RisegButton(
                      label: 'Eliminar definitivamente',
                      variant: RisegButtonVariant.danger,
                      icon: Icons.delete_outline,
                      size: RisegButtonSize.compact,
                      loading: _eliminando,
                      onPressed: _guardando || _eliminando ? null : _eliminar,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Sólo se puede eliminar un tipo que ninguna sucursal usó nunca '
                    '—ni una inactiva—. Si alguna lo usó, desactívalo.',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    final codigo = _codigo.text.trim().toUpperCase();
    final nombre = _nombre.text.trim();

    setState(() {
      _errorDeCodigo = _esNuevo && codigo.isEmpty ? 'Escribe un código.' : null;
      _errorDeNombre = nombre.isEmpty ? 'Escribe un nombre.' : null;
    });

    if (_errorDeCodigo != null || _errorDeNombre != null) return;

    setState(() => _guardando = true);

    final resultado = _esNuevo
        ? await widget.repositorio.crearTipo(
            empresaId: widget.empresaId,
            codigo: codigo,
            nombre: nombre,
          )
        : await widget.repositorio.modificarTipo(
            empresaId: widget.empresaId,
            tipoId: widget.tipo!.id,
            nombre: nombre,
            // EL ESTADO SÓLO VIAJA SI SE MOVIÓ: ver el comentario largo en Áreas.
            activo: _activo == widget.tipo!.activo ? null : _activo,
          );

    if (!mounted) return;

    resultado.when(
      ok: (_) {
        RisegFeedback.showSuccess(
          context,
          _esNuevo ? 'Tipo creado.' : 'Tipo actualizado.',
        );
        Navigator.of(context).pop(true);
      },
      failure: (f) => setState(() {
        _guardando = false;

        // EL CHOQUE DE CÓDIGO SE MUESTRA EN EL CAMPO, no en un aviso que se va: es lo
        // único que el usuario puede arreglar sin salir del formulario. Mismo patrón
        // que Áreas.
        //
        // Y SE MIRA EL CÓDIGO DEL SERVIDOR, no el 409 a secas: desde M3 un
        // `desactivacion_bloqueada` —«lo usan 2 sucursales activas»— también es 409, y
        // no se arregla cambiando nada de este formulario.
        if (f case ApiHttpFailure(codigo: 'code_conflict')) {
          _errorDeCodigo = f.message;
        } else {
          mostrarRechazoDelServidor(context, f.message);
        }
      }),
    );
  }

  /// Elimina el tipo, con motivo. **Sólo Maestro, y sólo si nunca se usó.**
  Future<void> _eliminar() async {
    final motivo = await pedirMotivoDeEliminacion(
      context,
      queEs: 'el tipo de sucursal',
      comoSeLlama: '${widget.tipo!.codigo} · ${widget.tipo!.nombre}',
      queSePierde: 'El tipo desaparece del catálogo de la empresa.',
    );

    if (motivo == null || !mounted) return;

    setState(() => _eliminando = true);

    final resultado = await widget.repositorio.eliminarTipo(
      empresaId: widget.empresaId,
      tipoId: widget.tipo!.id,
      motivo: motivo,
    );

    if (!mounted) return;

    resultado.when(
      ok: (tipo) {
        RisegFeedback.showSuccess(context, 'Se eliminó el tipo ${tipo.nombre}.');
        Navigator.of(context).pop(true);
      },
      failure: (f) {
        setState(() => _eliminando = false);
        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }
}
