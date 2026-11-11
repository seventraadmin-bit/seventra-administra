import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL: esta feature no puede importar el catálogo de
// permisos y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../app/shell/se_cierra_al_cambiar_la_direccion.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/servicios_repositorio_http.dart';
import '../modelos/servicio.dart';

/// Tipos de servicio: el catálogo con el que la empresa clasifica sus servicios.
///
/// ## No es una pestaña, y es la misma decisión que en Sucursales
///
/// Vive **dentro de Servicios**, detrás de un botón. Un cliente abre «Servicios» para ver
/// sus servicios; los tipos son el catálogo que los ordena, y no merecen el mismo peso en
/// la navegación que la cosa que ordenan. Tampoco va en Configuración: eso lo alejaría de
/// la única pantalla que lo usa.
///
/// ## El botón de recomendados existe porque el alta en blanco es un muro
///
/// Dar de alta un servicio **exige** un tipo. El catálogo es Company-owned y **nace
/// vacío**, así que el primer servicio de una empresa nueva es imposible hasta que alguien
/// invente un catálogo.
///
/// 🚫 **Y por eso es un botón y no una siembra.** SEVENTRA se vende también a empresas que
/// **no son de seguridad**, y a una constructora «Escolta» o «Rondín» no le corresponden.
/// Una fila que el sistema puso sin preguntar es una fila que su dueño tiene que entender
/// y borrar; cuatro así en el primer minuto son cuatro preguntas. Pulsándolo, la empresa
/// de seguridad tiene su catálogo en un clic y la que no lo es jamás lo ve lleno de algo
/// ajeno.
///
/// **Es idempotente:** el servidor salta los que ya existen **por código**, así que
/// pulsarlo dos veces no duplica nada y la segunda vez crea cero — que es un resultado
/// distinto de un error y se dice distinto.
class TiposDeServicioWebScreen extends StatefulWidget {
  const TiposDeServicioWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.capacidades,
    required this.guardia,
    this.onVolver,
    super.key,
  });

  final ServiciosRepositorioHttp repositorio;
  final String empresaId;

  /// Dónde se registra que hay trabajo sin guardar (D-56).
  ///
  /// **Esta pantalla no lo usa: lo pasa** a su panel de alta y edición, que es el que
  /// tiene campos. La regla es permanente: toda pantalla con «Guardar» se registra.
  final GuardiaDeSalida guardia;

  /// Qué puede hacer aquí quien mira.
  ///
  /// **EL CATÁLOGO DE UN MÓDULO USA EL PERMISO DE SU MÓDULO**, y aquí no hubo nada que
  /// decidir: `/service-types` ya exige `clients_services.read` para leer y
  /// `clients_services.manage` para escribir desde 5D.10D. Las tres escrituras son el
  /// mismo código porque el módulo tiene **dos** permisos, no cuatro — ver
  /// `CapacidadesDeModulo.deClientes`. Así **ningún permiso se ensancha**.
  final CapacidadesDeModulo capacidades;

  /// Cómo se vuelve a Servicios. `null` cuando se muestra sola.
  final VoidCallback? onVolver;

  @override
  State<TiposDeServicioWebScreen> createState() => _TiposDeServicioWebScreenState();
}

class _TiposDeServicioWebScreenState extends State<TiposDeServicioWebScreen> {
  List<TipoDeServicio>? _tipos;
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

    // SIN `usados`: aquí se administra el catálogo entero, no se filtra una lista. El
    // parámetro no tiene valor por omisión justamente para que cada pantalla lo diga.
    final resultado = await widget.repositorio.tipos(
      widget.empresaId,
      usados: null,
    );

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
        // ⚠️ `resultantes` ES EL CATÁLOGO RESULTANTE, NO LO QUE SE CREÓ. Al segundo clic
        // devuelve los cuatro otra vez, así que contar su longitud diría «Se agregaron 4»
        // cuando no se creó ninguno. La base queda bien —la ruta es idempotente— pero el
        // mensaje mentiría.
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

        final nuevos = tiposDeServicioNuevos(antes: antes, despues: resultantes);

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
                          'Servicios',
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
                          'Tipos de servicio',
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
                  // crean filas, y el de recomendados crea cuatro de un golpe.
                  //
                  // EL DE RECOMENDADOS VA SECUNDARIO Y A LA IZQUIERDA del principal: es
                  // un atajo para empezar, no la forma normal de crear un tipo.
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

    final tipos = _tipos ?? const <TipoDeServicio>[];

    if (tipos.isEmpty) {
      // EL VACÍO EXPLICA QUÉ ES Y OFRECE EL ATAJO, porque aquí empieza todo: sin un tipo
      // no se puede dar de alta ningún servicio.
      //
      // Y NOMBRA LOS CUATRO: quien no es una empresa de seguridad tiene que poder ver qué
      // va a entrar ANTES de pulsar, para decidir crear los suyos en vez de éstos.
      return RisegEmptyState(
        icon: Icons.category_outlined,
        title: 'Todavía no hay tipos de servicio',
        message:
            'Un tipo clasifica tus servicios —vigilancia fija, rondín, escolta— y hace '
            'falta al menos uno para dar de alta el primero. Puedes empezar con los '
            'recomendados —Vigilancia fija, Rondín, Escolta y Monitoreo— y cambiarlos '
            'después, o crear los tuyos.',
        // EL VACÍO TAMBIÉN CREA —cuatro de golpe—, así que pide `crear`.
        primaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Agregar tipos recomendados',
                icon: Icons.auto_awesome_outlined,
                loading: _agregandoRecomendados,
                onPressed: _agregarRecomendados,
              )
            : null,
        secondaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Crear el mío',
                variant: RisegButtonVariant.secondary,
                onPressed: () => _abrirPanel(),
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

  Future<void> _abrirPanel({TipoDeServicio? tipo}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeTipo(
        tipo: tipo,
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
        capacidades: widget.capacidades,
        guardia: widget.guardia,
      ),
    );

    if (guardado ?? false) await _cargar();
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.tipo, required this.onTocar});

  final TipoDeServicio tipo;
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
              label: tipo.estaActivo ? 'Activo' : 'Inactivo',
              tone: tipo.estaActivo
                  ? RisegStatusTone.success
                  : RisegStatusTone.neutral,
              icon: tipo.estaActivo
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
    required this.capacidades,
    required this.guardia,
  });

  /// D-56 · dónde declara que tiene algo que perder.
  final GuardiaDeSalida guardia;

  /// Qué se puede hacer. Las tres escrituras son `clients_services.manage`, pero se
  /// preguntan por su nombre y no por una sola: el día que el módulo tenga un permiso de
  /// archivar propio, este archivo no se entera.
  final CapacidadesDeModulo capacidades;

  /// ¿Hay algo que guardar?
  bool get sePuedeGuardar => tipo == null
      ? capacidades.puedeCrear
      : capacidades.puedeModificar || capacidades.puedeArchivar;

  final TipoDeServicio? tipo;
  final String empresaId;
  final ServiciosRepositorioHttp repositorio;

  @override
  State<_PanelDeTipo> createState() => _PanelDeTipoState();
}

class _PanelDeTipoState extends State<_PanelDeTipo>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDeTipo>,
        // D-56 · UNA HOJA MODAL NO VIVE EN EL HISTORIAL, así que un cambio de dirección
        // no se la lleva: sin esto se quedaría encima de la pantalla nueva, con los
        // campos puestos y un guardar que escribiría en el sitio de antes.
        SeCierraAlCambiarLaDireccion<_PanelDeTipo> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Lo escrito que se perdería al salir.
  ///
  /// **Dando de alta, cuenta cualquier campo con algo**; editando, lo que difiera del tipo
  /// cargado. Las dos formas son la misma regla —comparar contra lo que había— y en un
  /// alta lo que había es nada.
  @override
  bool get hayCambiosSinGuardar {
    final t = widget.tipo;

    if (t == null) {
      return _codigo.text.trim().isNotEmpty ||
          _nombre.text.trim().isNotEmpty ||
          !_activo;
    }

    return _nombre.text.trim() != t.nombre || _activo != t.estaActivo;
  }

  /// ⚠️ **EL NOMBRE SALE DEL TIPO CARGADO, no del campo**: a quien está renombrando, la
  /// pregunta le hablaría de algo que todavía no existe con ese nombre.
  @override
  String get queSePierde => switch (widget.tipo) {
    final t? => 'el tipo de servicio ${t.nombre}',
    null => 'el tipo de servicio que estás dando de alta',
  };

  final _codigo = TextEditingController();
  final _nombre = TextEditingController();

  bool _activo = true;
  bool _guardando = false;
  String? _errorDeCodigo;
  String? _errorDeNombre;

  bool get _esNuevo => widget.tipo == null;

  @override
  void initState() {
    super.initState();

    if (widget.tipo case final t?) {
      _codigo.text = t.codigo;
      _nombre.text = t.nombre;
      _activo = t.estaActivo;
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
                      ? 'Tipo de servicio'
                      : (_esNuevo ? 'Nuevo tipo de servicio' : 'Editar tipo'),
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                // EL CÓDIGO NO SE PUEDE CAMBIAR AL EDITAR, y el campo lo dice en lugar de
                // aceptarlo y descartarlo en silencio: es la identidad del tipo, un
                // disparador lo respalda en la base y la ruta no lo recibe en un `PATCH`.
                // Reclasificar es desactivar éste y crear otro.
                RisegTextField(
                  label: 'Código',
                  controller: _codigo,
                  enabled: widget.capacidades.puedeCrear && _esNuevo,
                  errorText: _errorDeCodigo,
                  helperText: _esNuevo
                      ? 'Corto y en mayúsculas, como RONDIN. No se podrá cambiar.'
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
                  helperText: 'Lo que vas a leer en las listas, como Rondín.',
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
                              ? 'Activo: se puede elegir al dar de alta un servicio.'
                              : 'Inactivo: desaparece del alta, pero los servicios que '
                                    'ya lo usan no cambian y se siguen pudiendo filtrar '
                                    'por él.',
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
                        onPressed: _guardando
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      RisegButton(
                        label: 'Guardar',
                        loading: _guardando,
                        onPressed: _guardando ? null : _guardar,
                      ),
                    ],
                  ),

                // 🚫 NO HAY «ELIMINAR», y no es un olvido: el servidor no publica un
                // `DELETE` para los tipos de servicio. Un tipo que sobra se desactiva, y
                // entonces desaparece del alta sin tocar los servicios que ya lo usan.
                if (!_esNuevo) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Un tipo no se elimina: se desactiva. Así los servicios que lo usan '
                    'conservan su historia.',
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
            // SÓLO VIAJA LO QUE SE MOVIÓ. Mandar los dos siempre haría que renombrar
            // reactivara de paso un tipo que alguien acaba de retirar — y el servidor
            // responde `nada_que_cambiar` si no se manda ninguno, que es lo correcto.
            nombre: nombre == widget.tipo!.nombre ? null : nombre,
            activo: _activo == widget.tipo!.estaActivo ? null : _activo,
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
        // único que el usuario puede arreglar sin salir del formulario.
        //
        // Y SE MIRA EL CÓDIGO DEL SERVIDOR, no el 409 a secas: el mismo estatus lo usan
        // otras reglas que no se arreglan cambiando nada de este formulario.
        if (f case ApiHttpFailure(codigo: 'code_conflict')) {
          _errorDeCodigo = f.message;
        } else {
          mostrarRechazoDelServidor(context, f);
        }
      }),
    );
  }
}
