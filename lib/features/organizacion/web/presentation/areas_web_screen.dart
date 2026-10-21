import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../datos/areas_repositorio_http.dart';
import '../modelos/area.dart';
import '../modelos/codigo_sugerido.dart';
import 'eliminar_estructura.dart';

/// Áreas, en la web.
///
/// **La primera pantalla de Administra en la nube.** Es la más simple de las cuatro de
/// M3 a propósito: prueba la plomería completa —sesión, empresa, permisos, 402— con el
/// dominio más pequeño que hay.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo.</b> El completo
/// exporta un componente que lee del disco con `dart:io` y rompería la build web sin
/// que nada en este archivo parezca estar mal. Una prueba de arquitectura lo exige.
class AreasWebScreen extends StatefulWidget {
  const AreasWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.esMaestro,
    required this.puedeEditar,
    super.key,
  });

  final AreasRepositorioHttp repositorio;
  final String empresaId;

  /// Si quien mira es Maestro de ESTA empresa.
  ///
  /// **Sólo gobierna si el botón de eliminar se OFRECE**, nunca si se puede. La
  /// autorización la decide el servidor —que exige rol de Maestro en la propia
  /// empresa—, y esconder el botón es cortesía, no seguridad. Sale de
  /// `CompanyContext.isMaestro`, que vino de `/context`: ni de la lista de empresas, ni
  /// de una preferencia guardada, ni de la URL.
  final bool esMaestro;

  /// Si quien mira puede **modificar** la configuración de la empresa.
  ///
  /// <b>NO ES `esMaestro`</b>, y confundirlos es lo que dejó esta pantalla abierta:
  /// un usuario con rol Usuario y CERO permisos veía «Nueva área» y el panel de
  /// edición completo, porque el botón no estaba atado a nada y `esMaestro` sólo
  /// bajaba al panel para ofrecer el borrado.
  ///
  /// **LO QUE NO SE PUEDE HACER NO SE MUESTRA.** Sin esto, la pantalla sólo puede
  /// ocultar el fallo: el servidor contesta 403 y la persona se queda sin saber si
  /// hizo algo mal o si nunca pudo.
  ///
  /// **OFRECERLO NO ES AUTORIZARLO.** El servidor vuelve a decidir en cada petición;
  /// esto evita enseñar una puerta que va a cerrarse en la cara.
  final bool puedeEditar;

  @override
  State<AreasWebScreen> createState() => _AreasWebScreenState();
}

class _AreasWebScreenState extends State<AreasWebScreen> {
  List<Area>? _areas;
  Failure? _fallo;
  bool _cargando = true;

  /// **Las inactivas se ocultan por omisión**, y el filtro vive aquí y no en la
  /// petición: pedirle al servidor sólo las activas obligaría a una segunda petición
  /// al encender el interruptor, y a tener dos listas que pueden discrepar.
  bool _mostrarInactivas = false;

  final _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    // LIBERAR EL CONTROLLER NO ES OPCIONAL, y en este proyecto ya costó una vez.
    // `Future.delayed(300ms)` para "esperar la animación" está PROHIBIDO.
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.listar(widget.empresaId);

    if (!mounted) return;

    resultado.when(
      ok: (areas) => setState(() {
        _areas = areas;
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  /// Lo que se pinta: filtrado por estado y por el buscador, en ese orden.
  ///
  /// **El buscador mira nombre Y código.** Quien escribe «ops» puede estar buscando
  /// «Operaciones» o el código `OPS`, y no tiene por qué saber cuál de los dos es.
  List<Area> get _visibles {
    final todas = _areas ?? const <Area>[];
    final texto = _buscador.text.trim().toLowerCase();

    return todas.where((a) {
      if (!_mostrarInactivas && !a.activa) return false;
      if (texto.isEmpty) return true;

      return a.nombre.toLowerCase().contains(texto) ||
          a.codigo.toLowerCase().contains(texto);
    }).toList();
  }

  int get _inactivas => (_areas ?? const <Area>[]).where((a) => !a.activa).length;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Encabezado(
                total: _areas?.length ?? 0,
                inactivas: _inactivas,
                // SIN PERMISO NO HAY BOTÓN, y no es lo mismo que un botón apagado:
                // `null` lo deshabilitaría y seguiría ahí, enseñando una capacidad
                // que esta persona no tiene.
                onNueva: widget.puedeEditar
                    ? (_cargando ? null : _abrirPanelDeAlta)
                    : null,
                ofrecerNueva: widget.puedeEditar,
              ),
              const SizedBox(height: AppSpacing.md),
              _Filtros(
                buscador: _buscador,
                mostrarInactivas: _mostrarInactivas,
                // EL INTERRUPTOR SÓLO APARECE SI HAY ALGO QUE MOSTRAR. Ofrecer
                // «Mostrar inactivas» cuando no hay ninguna es prometer algo que no
                // pasa al pulsarlo.
                hayInactivas: _inactivas > 0,
                onBuscar: (_) => setState(() {}),
                onMostrarInactivas: (v) => setState(() => _mostrarInactivas = v),
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
        title: 'No se pudieron cargar las áreas',
        message: f.message,
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    // VACÍO DE VERDAD: no hay ni una área. El texto EXPLICA qué es un área, porque
    // quien abre esta pantalla por primera vez puede no saberlo.
    if ((_areas ?? const <Area>[]).isEmpty) {
      return RisegEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Todavía no hay áreas',
        message:
            'Un área agrupa puestos, por ejemplo Operaciones o Administración.',
        // EL VACÍO TAMBIÉN OFRECE UN ALTA, y se le aplica la misma regla: sin
        // permiso explica qué es un área y no invita a crear una.
        primaryAction: widget.puedeEditar
            ? RisegButton(
                label: 'Nueva área',
                icon: Icons.add,
                onPressed: _abrirPanelDeAlta,
              )
            : null,
      );
    }

    // VACÍO POR FILTRO: hay áreas, pero ninguna encaja. Es un mensaje DISTINTO, y
    // confundirlos haría pensar que no hay nada capturado.
    if (_visibles.isEmpty) {
      return RisegEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Ninguna área coincide',
        message: _buscador.text.trim().isEmpty
            ? 'Todas las áreas están inactivas. Enciende «Mostrar inactivas» para '
                  'verlas.'
            : 'Ninguna área se llama o se codifica como «${_buscador.text.trim()}».',
      );
    }

    return ListView.separated(
      itemCount: _visibles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _Fila(
        area: _visibles[i],
        onTocar: () => _abrirPanelDeEdicion(_visibles[i]),
      ),
    );
  }

  // =========================================================================
  // El panel lateral
  // =========================================================================

  /// **Panel lateral, no diálogo modal centrado.** En web el modal se siente viejo y
  /// se rompe en pantallas pequeñas; un panel deja ver la lista detrás, que es el
  /// contexto de lo que se está escribiendo.
  Future<void> _abrirPanelDeAlta() => _abrirPanel();

  Future<void> _abrirPanelDeEdicion(Area area) => _abrirPanel(area: area);

  Future<void> _abrirPanel({Area? area}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeArea(
        area: area,
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
        esMaestro: widget.esMaestro,
        // SIN PERMISO, EL PANEL ES UNA FICHA. Tocar una fila sigue sirviendo —ver el
        // código, el nombre y si está activa es consultar— pero no aparece ni un
        // campo editable ni un botón que guarde.
        puedeEditar: widget.puedeEditar,
        // EL CÓDIGO SE SUGIERE, COMO EN EL ESCRITORIO. Y si las áreas no se pudieron
        // leer —`_areas` nulo—, NO SE SUGIERE NADA: un `ARE-0001` inventado chocaría
        // con el que ya existe, y el usuario recibiría un 409 por un número que no
        // escribió.
        codigoSugerido: _areas == null
            ? null
            : siguienteCodigo(
                PrefijoDeCodigo.area,
                _areas!.map((a) => a.codigo),
              ),
      ),
    );

    if (guardado ?? false) await _cargar();
  }
}

// ===========================================================================
// Encabezado
// ===========================================================================

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.total,
    required this.inactivas,
    required this.onNueva,
    required this.ofrecerNueva,
  });

  final int total;
  final int inactivas;
  final VoidCallback? onNueva;

  /// Si el botón de alta **se pinta**. Distinto de `onNueva == null`, que lo dejaría
  /// visible y apagado: lo que esta persona no puede hacer no se le enseña.
  final bool ofrecerNueva;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Áreas', style: AppTypography.heading1),
              const SizedBox(height: AppSpacing.xxs),
              Text(_resumen(), style: AppTypography.caption.copyWith(color: colors.textMuted)),
            ],
          ),
        ),
        // UN SOLO BOTÓN PRINCIPAL, arriba a la derecha.
        if (ofrecerNueva)
          RisegButton(label: 'Nueva área', icon: Icons.add, onPressed: onNueva),
      ],
    );
  }

  /// **Un cero no se anuncia.** «3 áreas» a secas cuando ninguna está inactiva; el
  /// «· 1 inactiva» sólo aparece cuando hay algo que decir.
  String _resumen() {
    final areas = total == 1 ? '1 área' : '$total áreas';

    if (inactivas == 0) return areas;

    return '$areas · ${inactivas == 1 ? '1 inactiva' : '$inactivas inactivas'}';
  }
}

// ===========================================================================
// Buscador e interruptor
// ===========================================================================

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.buscador,
    required this.mostrarInactivas,
    required this.hayInactivas,
    required this.onBuscar,
    required this.onMostrarInactivas,
  });

  final TextEditingController buscador;
  final bool mostrarInactivas;
  final bool hayInactivas;
  final ValueChanged<String> onBuscar;
  final ValueChanged<bool> onMostrarInactivas;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Expanded(
          child: RisegSearchField(
            hint: 'Buscar por nombre o código',
            controller: buscador,
            onChanged: onBuscar,
          ),
        ),
        if (hayInactivas) ...[
          const SizedBox(width: AppSpacing.md),
          Row(
            children: [
              Switch(value: mostrarInactivas, onChanged: onMostrarInactivas),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Mostrar inactivas',
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _Fila extends StatelessWidget {
  const _Fila({required this.area, required this.onTocar});

  final Area area;
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
                  // EL NOMBRE ES LO QUE IDENTIFICA, y va grande.
                  Text(area.nombre, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  // EL CÓDIGO, PEQUEÑO Y EN GRIS. Lo escribe el cliente y lo
                  // reconoce, pero no es lo que busca con la vista.
                  Text(
                    area.codigo,
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            // COLOR MÁS ÍCONO, no sólo color: quien no distingue verde de gris sigue
            // viendo la diferencia.
            RisegStatusBadge(
              label: area.activa ? 'Activa' : 'Inactiva',
              tone: area.activa ? RisegStatusTone.success : RisegStatusTone.neutral,
              icon: area.activa
                  ? Icons.check_circle_outline
                  : Icons.remove_circle_outline,
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// El panel de alta y edición
// ===========================================================================

class _PanelDeArea extends StatefulWidget {
  const _PanelDeArea({
    required this.area,
    required this.empresaId,
    required this.repositorio,
    required this.esMaestro,
    required this.puedeEditar,
    required this.codigoSugerido,
  });

  final Area? area;
  final String empresaId;
  final AreasRepositorioHttp repositorio;
  final bool esMaestro;

  /// Si este panel es un **formulario** o una **ficha**.
  final bool puedeEditar;

  /// El código que se propone para un área nueva, o `null` si no se pudo calcular.
  final String? codigoSugerido;

  @override
  State<_PanelDeArea> createState() => _PanelDeAreaState();
}

class _PanelDeAreaState extends State<_PanelDeArea> {
  late final TextEditingController _codigo;
  late final TextEditingController _nombre;

  late bool _activa;
  bool _guardando = false;
  bool _eliminando = false;

  /// **El error va EN EL CAMPO, no en una barra roja arriba.** Quien escribe un
  /// código repetido tiene que verlo donde está el código.
  String? _errorDeCodigo;
  String? _errorDeNombre;

  bool get _esNueva => widget.area == null;

  @override
  void initState() {
    super.initState();
    // AL CREAR, EL CÓDIGO LLEGA SUGERIDO Y SIGUE SIENDO EDITABLE: quien quiera poner
    // `OPERACIONES` puede. Lo que se evita es tener que inventarlo desde cero.
    _codigo = TextEditingController(
      text: widget.area?.codigo ?? widget.codigoSugerido ?? '',
    );
    _nombre = TextEditingController(text: widget.area?.nombre ?? '');
    _activa = widget.area?.activa ?? true;
  }

  @override
  void dispose() {
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
                  // EL TÍTULO NO PROMETE LO QUE NO SE PUEDE. «Editar área» sobre una
                  // ficha sin campos editables sería una etiqueta que miente.
                  !widget.puedeEditar
                      ? 'Área'
                      : (_esNueva ? 'Nueva área' : 'Editar área'),
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                // EL CÓDIGO NO SE PUEDE CAMBIAR AL EDITAR, y el campo lo dice en
                // lugar de aceptarlo y descartarlo en silencio: un código es la
                // identidad del área, y la ruta no lo recibe en un `PATCH`.
                RisegTextField(
                  label: 'Código',
                  controller: _codigo,
                  enabled: widget.puedeEditar && _esNueva,
                  errorText: _errorDeCodigo,
                  // LA AYUDA SALE DE UNA SOLA FUNCIÓN para las tres pantallas. Tres
                  // textos escritos aparte ya habían divergido, y tres pantallas que
                  // hacen lo mismo explicándolo distinto enseñan que no hacen lo mismo.
                  helperText: ayudaDelCodigo(
                    esNuevo: _esNueva,
                    haySugerencia: widget.codigoSugerido != null,
                    queEs: 'al área',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                RisegTextField(
                  label: 'Nombre',
                  controller: _nombre,
                  enabled: widget.puedeEditar,
                  errorText: _errorDeNombre,
                  autofocus: widget.puedeEditar && !_esNueva,
                ),

                if (!_esNueva) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Switch(
                        value: _activa,
                        // UN INTERRUPTOR SIN `onChanged` SE PINTA APAGADO Y NO SE
                        // MUEVE, que es lo correcto aquí: el estado de un área es
                        // dato que se consulta, no un botón que sobra.
                        onChanged: widget.puedeEditar
                            ? (v) => setState(() => _activa = v)
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _activa ? 'Activa' : 'Inactiva',
                        style: AppTypography.body,
                      ),
                    ],
                  ),
                  Text(
                    'Una área inactiva no aparece al crear un puesto.',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],

                const Spacer(),

                // ELIMINAR VA APARTE Y ABAJO, separado de Guardar y Cancelar por una
                // línea. Dos razones: no se pulsa por error buscando «Guardar», y
                // visualmente pertenece a otra categoría —esto destruye, aquello
                // conserva—.
                //
                // SÓLO AL EDITAR Y SÓLO PARA EL MAESTRO. En un área que todavía no
                // existe no hay nada que eliminar.
                // Y TAMBIÉN EXIGE EL PERMISO, no sólo el rol: el Maestro lo hereda,
                // así que para él no cambia nada; lo que esto cierra es que alguien
                // con el rol y sin el permiso viera la puerta de destruir.
                if (!_esNueva && widget.esMaestro && widget.puedeEditar) ...[
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
                    'Sólo se puede eliminar un área que nunca se usó. Si tiene '
                    'puestos, desactívala.',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // UNA FICHA SE CIERRA; UN FORMULARIO SE CANCELA O SE GUARDA. Dejar
                // «Cancelar» en una ficha sugeriría que había algo que cancelar.
                if (!widget.puedeEditar)
                  Align(
                    alignment: Alignment.centerRight,
                    child: RisegButton(
                      label: 'Cerrar',
                      variant: RisegButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: RisegButton(
                          label: 'Cancelar',
                          variant: RisegButtonVariant.secondary,
                          onPressed: _guardando || _eliminando
                              ? null
                              : () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: RisegButton(
                          label: 'Guardar',
                          loading: _guardando,
                          onPressed: _guardando || _eliminando ? null : _guardar,
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
    final codigo = _codigo.text.trim().toUpperCase();
    final nombre = _nombre.text.trim();

    setState(() {
      _errorDeCodigo = _esNueva && codigo.isEmpty ? 'Falta el código.' : null;
      _errorDeNombre = nombre.isEmpty ? 'Falta el nombre.' : null;
    });

    if (_errorDeCodigo != null || _errorDeNombre != null) return;

    setState(() => _guardando = true);

    // AL CREAR, UN CHOQUE DEL CÓDIGO SUGERIDO SE REINTENTA UNA VEZ. Es la contra que
    // tiene sugerir desde el cliente: dos personas creando a la vez reciben el mismo
    // número y la segunda recibe un 409 por algo que no escribió. Si el código lo
    // eligió la persona, no se reintenta nada.
    final resultado = _esNueva
        ? await crearConReintentoDeCodigo(
            prefijo: PrefijoDeCodigo.area,
            codigoUsado: codigo,
            codigoSugerido: widget.codigoSugerido,
            crear: (c) => widget.repositorio.crear(
              empresaId: widget.empresaId,
              codigo: c,
              nombre: nombre,
            ),
            codigosActuales: () async =>
                (await widget.repositorio.listar(widget.empresaId)).when(
                  ok: (areas) => Result.ok([for (final a in areas) a.codigo]),
                  failure: Result.failure,
                ),
          )
        : await widget.repositorio.modificar(
            empresaId: widget.empresaId,
            areaId: widget.area!.id,
            nombre: nombre,
            activa: _activa,
          );

    if (!mounted) return;

    resultado.when(
      ok: (_) => Navigator.of(context).pop(true),
      failure: (f) {
        setState(() {
          _guardando = false;

          // EL MENSAJE VA DONDE SE PUEDE ARREGLAR, y distinguirlo importa:
          //
          //  · `code_conflict` SÍ es del campo del código: hay que cambiarlo ahí.
          //  · `desactivacion_bloqueada` NO es de ningún campo. «1 puesto(s)
          //    activo(s) en esta área» no se arregla reescribiendo el formulario, se
          //    arregla en la pestaña de Puestos.
          //
          // Hasta M3 todo 409 caía en el campo del código, porque era el único 409
          // posible. Dejarlo así habría puesto «No se puede desactivar: 1 puesto(s)
          // activo(s)» debajo de un código perfectamente correcto.
          if (f case ApiHttpFailure(codigo: 'code_conflict')) {
            _errorDeCodigo = f.message;
          } else {
            mostrarRechazoDelServidor(context, f.message);
          }
        });
      },
    );
  }

  /// Elimina el área, con motivo, y cierra el panel si se logró.
  ///
  /// **El rechazo se muestra y el panel se queda abierto.** Cerrarlo obligaría a volver
  /// a entrar para leer por qué no se pudo, y el conteo que el servidor manda —«tiene 3
  /// puestos»— es justo lo que la persona necesita tener delante.
  Future<void> _eliminar() async {
    final motivo = await pedirMotivoDeEliminacion(
      context,
      queEs: 'el área',
      comoSeLlama: '${widget.area!.codigo} · ${widget.area!.nombre}',
      queSePierde: 'El área desaparece de la empresa.',
    );

    if (motivo == null || !mounted) return;

    setState(() => _eliminando = true);

    final resultado = await widget.repositorio.eliminar(
      empresaId: widget.empresaId,
      areaId: widget.area!.id,
      motivo: motivo,
    );

    if (!mounted) return;

    resultado.when(
      ok: (area) {
        // SE DICE QUÉ DESAPARECIÓ, por su nombre. «Eliminado» a secas deja la duda de
        // si se borró lo que se quería.
        RisegFeedback.showSuccess(context, 'Se eliminó el área ${area.nombre}.');
        Navigator.of(context).pop(true);
      },
      failure: (f) {
        setState(() => _eliminando = false);
        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }
}
