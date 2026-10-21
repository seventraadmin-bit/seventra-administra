import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL: esta feature no puede importar el catálogo de
// permisos —hay un guardia que lo impide— y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../datos/areas_repositorio_http.dart';
import '../datos/puestos_repositorio_http.dart';
import '../modelos/area.dart';
import '../modelos/codigo_sugerido.dart';
import '../modelos/puesto.dart';
import 'eliminar_estructura.dart';

/// Puestos: el cargo, no la persona.
///
/// «Supervisor general» es un puesto; quién lo ocupa es una asignación de Personal.
/// Por eso un puesto sigue existiendo —inactivo— cuando nadie lo ocupa: su historia
/// laboral lo referencia.
///
/// ## Tres campos que NO se editan, y conviene saber por qué
///
/// **Código, área y tipo.** No es que esta pantalla los omita: *«no existen en el
/// contrato»* del `PATCH`, y **la base lo respalda con un disparador**. Son identidad y
/// configuración estable de una fila que la historia laboral referencia, así que
/// **reclasificar es desactivar y crear otro** — y la pantalla lo dice, porque es la
/// pregunta que alguien va a tener frente a tres campos en gris.
///
/// ## El nivel va como LISTA, no como campo numérico
///
/// Del 1 al 10, y **el 1 es el más bajo**. Una lista de diez no admite un valor
/// inválido, no obliga a teclear, y sobre todo **enseña la escala antes** en vez de
/// dejar que se aprenda por un mensaje de error del servidor.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo</b>, que arrastra
/// `dart:io` y rompe la build web.
class PuestosWebScreen extends StatefulWidget {
  const PuestosWebScreen({
    required this.repositorio,
    required this.repositorioDeAreas,
    required this.empresaId,
    required this.esMaestro,
    required this.capacidades,
    this.alIrAAreas,
    super.key,
  });

  final PuestosRepositorioHttp repositorio;

  /// El de áreas, **que ya existía**: las áreas tienen su propia pestaña y aquí sólo
  /// se leen, para el selector y para poner su nombre en la lista.
  final AreasRepositorioHttp repositorioDeAreas;

  final String empresaId;

  /// Si quien mira es Maestro. **Sólo gobierna si el botón de eliminar se OFRECE**,
  /// nunca si se puede: eso lo decide el servidor.
  final bool esMaestro;

  /// Qué puede hacer aquí quien mira: crear, modificar, archivar.
  ///
  /// <b>NO ES `esMaestro`</b>: un usuario con rol Usuario y CERO permisos veía
  /// «Nuevo puesto» y el panel de edición completo, porque el botón no estaba atado
  /// a nada y `esMaestro` sólo bajaba al panel para ofrecer el borrado.
  ///
  /// **CADA ACCIÓN PREGUNTA POR SU CAPACIDAD**, y ofrecerlo no es autorizarlo: el
  /// servidor vuelve a decidir en cada petición.
  final CapacidadesDeModulo capacidades;

  /// Cómo llevar a la pestaña de Áreas. Lo pasa el portón, que es el dueño de qué
  /// pestaña está abierta; la pantalla no cambia la navegación por su cuenta.
  ///
  /// `null` cuando se monta sola, y entonces el diálogo de «hace falta un área» sólo
  /// informa.
  final VoidCallback? alIrAAreas;

  @override
  State<PuestosWebScreen> createState() => _PuestosWebScreenState();
}

class _PuestosWebScreenState extends State<PuestosWebScreen> {
  List<Puesto>? _puestos;
  List<Area>? _areas;
  Failure? _fallo;
  bool _cargando = true;

  /// **Los inactivos se ocultan por omisión**, y el filtro vive aquí y no en la
  /// petición: pedirle al servidor sólo los activos obligaría a una segunda petición al
  /// encender el interruptor, y a tener dos listas que pueden discrepar.
  bool _mostrarInactivos = false;

  final _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    // Liberar el controller no es opcional, y en este proyecto ya costó una vez.
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    // LAS DOS A LA VEZ: la lista necesita el nombre del área —el servidor manda
    // `areaId`, no el nombre— y el formulario necesita el selector.
    final (puestos, areas) = await (
      widget.repositorio.listar(widget.empresaId),
      widget.repositorioDeAreas.listar(widget.empresaId),
    ).wait;

    if (!mounted) return;

    setState(() {
      _cargando = false;

      puestos.when(ok: (p) => _puestos = p, failure: (f) => _fallo = f);

      // SIN LAS ÁREAS LA LISTA SIGUE SIRVIENDO: los puestos se ven, y lo que no se
      // podrá es dar de alta. Eso se dice al intentarlo, no borrando la pantalla.
      areas.when(ok: (a) => _areas = a, failure: (_) => _areas = null);
    });
  }

  /// Filtrado por estado y por el buscador, en ese orden.
  ///
  /// **El buscador mira nombre, código Y ÁREA.** Quien escribe «monitoreo» busca los
  /// puestos de esa área, no un puesto que se llame así.
  List<Puesto> get _visibles {
    final todos = _puestos ?? const <Puesto>[];
    final texto = _buscador.text.trim().toLowerCase();

    return todos.where((p) {
      if (!_mostrarInactivos && !p.activo) return false;
      if (texto.isEmpty) return true;

      return p.nombre.toLowerCase().contains(texto) ||
          p.codigo.toLowerCase().contains(texto) ||
          (_nombreDelArea(p.areaId) ?? '').toLowerCase().contains(texto);
    }).toList();
  }

  int get _inactivos => (_puestos ?? const <Puesto>[]).where((p) => !p.activo).length;

  /// El nombre del área de un puesto. **Nunca el identificador**: un UUID en una lista
  /// no le dice nada a nadie.
  String? _nombreDelArea(String areaId) {
    for (final a in _areas ?? const <Area>[]) {
      if (a.id == areaId) return a.nombre;
    }

    return null;
  }

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
                ofrecerNuevo: widget.capacidades.puedeCrear,
                total: _puestos?.length ?? 0,
                inactivos: _inactivos,
                onNuevo: _cargando ? null : () => _abrirPanel(),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: RisegSearchField(
                      hint: 'Buscar por nombre, código o área',
                      controller: _buscador,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // EL INTERRUPTOR SÓLO APARECE SI HAY ALGO QUE MOSTRAR.
                  if (_inactivos > 0) ...[
                    const SizedBox(width: AppSpacing.md),
                    Row(
                      children: [
                        Switch(
                          value: _mostrarInactivos,
                          onChanged: (v) => setState(() => _mostrarInactivos = v),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Mostrar inactivos',
                          style: AppTypography.body.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
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
        title: 'No se pudieron cargar los puestos',
        message: f.message,
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    if ((_puestos ?? const <Puesto>[]).isEmpty) {
      // EL VACÍO EXPLICA QUÉ ES UN PUESTO, porque quien abre esto por primera vez
      // puede confundirlo con la persona que lo ocupa.
      return RisegEmptyState(
        icon: Icons.badge_outlined,
        title: 'Todavía no hay puestos',
        message:
            'Un puesto es el cargo dentro de un área —Supervisor, Jefe de turno, '
            'Auxiliar contable—, no la persona que lo ocupa.',
        // EL VACÍO TAMBIÉN OFRECE UN ALTA, y se le aplica la misma regla: sin
        // permiso, el estado vacío explica qué es un puesto y no invita a crear uno.
        // Esto se me habría escapado si sólo hubiera mirado el encabezado.
        primaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Nuevo puesto',
                icon: Icons.add,
                onPressed: () => _abrirPanel(),
              )
            : null,
      );
    }

    // VACÍO POR FILTRO: hay puestos, pero ninguno encaja. Es un mensaje DISTINTO, y
    // confundirlos haría pensar que no hay nada capturado.
    if (_visibles.isEmpty) {
      return RisegEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Ningún puesto coincide',
        message: _buscador.text.trim().isEmpty
            ? 'Todos los puestos están inactivos. Enciende «Mostrar inactivos» para '
                  'verlos.'
            : 'Ningún puesto se llama, se codifica o pertenece a un área como '
                  '«${_buscador.text.trim()}».',
      );
    }

    return ListView.separated(
      itemCount: _visibles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _Fila(
        puesto: _visibles[i],
        area: _nombreDelArea(_visibles[i].areaId),
        onTocar: () => _abrirPanel(puesto: _visibles[i]),
      ),
    );
  }

  Future<void> _abrirPanel({Puesto? puesto}) async {
    // SÓLO LAS ÁREAS ACTIVAS, y al editar también la del puesto aunque esté inactiva:
    // ocultarla haría pensar que el puesto no tiene área.
    //
    // ⚠️ EL SERVIDOR ACEPTARÍA UN ÁREA INACTIVA —sólo valida que exista—, así que
    // esto lo decide el cliente. Archivar un puesto bajo un área fuera de uso es lo
    // contrario de lo que el catálogo quiere.
    final areas = (_areas ?? const <Area>[])
        .where((a) => a.activa || a.id == puesto?.areaId)
        .toList();

    // SIN UN ÁREA ACTIVA NO SE PUEDE DAR DE ALTA, y el servidor lo exige. En vez de
    // apagar el botón —que dejaría al usuario sin saber por qué— se abre el camino
    // para resolverlo: es una precondición de DATOS que el cliente conoce, no una
    // suposición sobre la autorización.
    if (puesto == null && areas.isEmpty) {
      final irAAreas = await RisegDialog.showConfirmation(
        context: context,
        title: 'Primero hace falta un área',
        message:
            'Un puesto pertenece a un área —Monitoreo, Administración—, y todavía no '
            'hay ninguna activa. Créala y vuelve.',
        confirmLabel: widget.alIrAAreas == null ? 'Entendido' : 'Ver áreas',
        cancelLabel: 'Ahora no',
      );

      if ((irAAreas ?? false) && mounted) widget.alIrAAreas?.call();
      return;
    }

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDePuesto(
        puesto: puesto,
        areas: areas,
        // EL CÓDIGO SUGERIDO SALE DE TODOS LOS PUESTOS, no sólo de los visibles: el
        // filtro de la pantalla no puede influir en qué consecutivo toca.
        codigoSugerido: siguienteCodigoDePuesto(
          (_puestos ?? const <Puesto>[]).map((p) => p.codigo),
        ),
        // SIN LISTA NO HAY SUGERENCIA QUE VALGA: si los puestos no se pudieron leer,
        // un «PUE-0001» inventado chocaría con el primero que ya existe.
        sePudoCalcularElCodigo: _puestos != null,
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
        esMaestro: widget.esMaestro,
        // SIN PERMISO, EL PANEL ES UNA FICHA: tocar una fila sigue sirviendo para
        // consultar, sin un campo editable ni un botón que guarde.
        capacidades: widget.capacidades,
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
    required this.inactivos,
    required this.onNuevo,
    required this.ofrecerNuevo,
  });

  /// Si el botón de alta **se pinta**. Distinto de `onNuevo == null`, que lo dejaría
  /// visible y apagado: lo que esta persona no puede hacer no se le enseña.
  final bool ofrecerNuevo;

  final int total;
  final int inactivos;
  final VoidCallback? onNuevo;

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
              const Text('Puestos', style: AppTypography.heading1),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _resumen(),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        // UN SOLO BOTÓN. Los puestos no tienen catálogo detrás, a diferencia de las
        // sucursales con sus tipos.
        if (ofrecerNuevo)
          RisegButton(label: 'Nuevo puesto', icon: Icons.add, onPressed: onNuevo),
      ],
    );
  }

  /// **Un cero no se anuncia.** «4 puestos» a secas cuando ninguno está inactivo.
  String _resumen() {
    final cuantos = total == 1 ? '1 puesto' : '$total puestos';

    if (inactivos == 0) return cuantos;

    return '$cuantos · ${inactivos == 1 ? '1 inactivo' : '$inactivos inactivos'}';
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _Fila extends StatelessWidget {
  const _Fila({required this.puesto, required this.area, required this.onTocar});

  final Puesto puesto;
  final String? area;
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
                  Text(puesto.nombre, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    // SIN ÁREA SE DICE «sin área», no se calla: un hueco parecería un
                    // fallo de carga. Pasa cuando las áreas no se pudieron leer.
                    '${puesto.codigo} · ${area ?? 'sin área'}',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),

            // TIPO Y NIVEL COMO PASTILLAS, como en el escritorio. El nivel va «N3»
            // para que ocupe poco y siga leyéndose como nivel.
            RisegStatusBadge(
              label: puesto.esOperativo ? 'Operativo' : 'Administrativo',
              tone: puesto.esOperativo
                  ? RisegStatusTone.info
                  : RisegStatusTone.neutral,
              icon: puesto.esOperativo
                  ? Icons.shield_outlined
                  : Icons.business_center_outlined,
            ),
            const SizedBox(width: AppSpacing.xs),

            // SIN NIVEL SE DICE «sin nivel», NUNCA «N0». La columna es opcional en la
            // base y hay puestos viejos sin él: ausencia no es cero.
            //
            // EL NIVEL NO LLEVA ÍCONO, y es una corrección: `stairs_outlined` se leía
            // como un lápiz y parecía un botón de editar. Un número no necesita
            // ícono — «N3» ya dice lo que es—, y el Design System pide ícono para que
            // un ESTADO no dependa sólo del color. Un nivel no es un estado.
            //
            // «Sin nivel» SÍ lo lleva, porque eso sí es un estado: es lo único de
            // esta fila que alguien tendría que ir a corregir.
            RisegStatusBadge(
              label: puesto.nivel == null ? 'sin nivel' : 'N${puesto.nivel}',
              tone: puesto.nivel == null
                  ? RisegStatusTone.warning
                  : RisegStatusTone.neutral,
              icon: puesto.nivel == null ? Icons.help_outline : null,
            ),
            const SizedBox(width: AppSpacing.xs),

            RisegStatusBadge(
              label: puesto.activo ? 'Activo' : 'Inactivo',
              tone: puesto.activo ? RisegStatusTone.success : RisegStatusTone.neutral,
              icon: puesto.activo
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

class _PanelDePuesto extends StatefulWidget {
  const _PanelDePuesto({
    required this.puesto,
    required this.areas,
    required this.codigoSugerido,
    required this.sePudoCalcularElCodigo,
    required this.empresaId,
    required this.repositorio,
    required this.esMaestro,
    required this.capacidades,
  });

  final Puesto? puesto;
  final List<Area> areas;
  final String codigoSugerido;
  final bool sePudoCalcularElCodigo;
  final String empresaId;
  final PuestosRepositorioHttp repositorio;
  final bool esMaestro;

  /// Qué se puede hacer desde el panel. Los campos los gobierna `puedeModificar`
  /// —o `puedeCrear` si es nuevo— y el interruptor `puedeArchivar`.
  final CapacidadesDeModulo capacidades;

  /// ¿Hay algo que guardar? Al crear, `puedeCrear`; al editar, cualquiera de las dos
  /// escrituras, porque el `PATCH` lleva datos y estado y cada uno tiene su permiso.
  bool get sePuedeGuardar => puesto == null
      ? capacidades.puedeCrear
      : capacidades.puedeModificar || capacidades.puedeArchivar;

  @override
  State<_PanelDePuesto> createState() => _PanelDePuestoState();
}

class _PanelDePuestoState extends State<_PanelDePuesto> {
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();

  String? _areaId;
  String? _tipo;
  int? _nivel;
  bool _activo = true;
  bool _guardando = false;
  bool _eliminando = false;
  String? _errorDeCodigo;
  String? _errorDeNombre;
  String? _errorDeArea;
  String? _errorDeTipo;
  String? _errorDeNivel;

  bool get _esNuevo => widget.puesto == null;

  @override
  void initState() {
    super.initState();

    if (widget.puesto case final p?) {
      _codigo.text = p.codigo;
      _nombre.text = p.nombre;
      _descripcion.text = p.descripcion ?? '';
      _areaId = p.areaId;
      _tipo = p.tipo;
      _nivel = p.nivel;
      _activo = p.activo;
    } else {
      // EL CONSECUTIVO SUGERIDO, como en el escritorio. Editable: alguien puede
      // querer su propia nomenclatura, y el servidor acepta cualquier código válido.
      if (widget.sePudoCalcularElCodigo) _codigo.text = widget.codigoSugerido;

      // CON UNA SOLA ÁREA SE PRESELECCIONA, porque elegir entre una no es una
      // decisión. Con dos o más no se adivina.
      if (widget.areas.length == 1) _areaId = widget.areas.single.id;
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _descripcion.dispose();
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // EL TÍTULO NO PROMETE LO QUE NO SE PUEDE.
                  !widget.sePuedeGuardar
                      ? 'Puesto'
                      : (_esNuevo ? 'Nuevo puesto' : 'Editar puesto'),
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                RisegTextField(
                  label: 'Código',
                  controller: _codigo,
                  // CÓDIGO, ÁREA Y TIPO sólo se fijan al crear, así que su puerta
                  // es `puedeCrear`.
                  enabled: widget.capacidades.puedeCrear && _esNuevo,
                  errorText: _errorDeCodigo,
                  // LA MISMA AYUDA QUE ÁREAS Y SUCURSALES, de una sola función. De los
                  // tres textos que había, el de aquí era el que llevaba lo más útil
                  // —que después no se podrá cambiar— y por eso sobrevive en el
                  // unificado.
                  helperText: ayudaDelCodigo(
                    esNuevo: _esNuevo,
                    haySugerencia: widget.sePudoCalcularElCodigo,
                    queEs: 'al puesto',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                RisegSelect<String>(
                  label: 'Área',
                  value: _areaId,
                  // CÓDIGO, ÁREA Y TIPO sólo se fijan al crear, así que su puerta
                  // es `puedeCrear`.
                  enabled: widget.capacidades.puedeCrear && _esNuevo,
                  hint: 'Elige un área',
                  errorText: _errorDeArea,
                  helperText: _esNuevo
                      ? 'Sólo áreas activas.'
                      : 'El área no se cambia.',
                  items: [
                    for (final a in widget.areas)
                      RisegSelectItem(value: a.id, label: a.nombre),
                  ],
                  onChanged: (v) => setState(() {
                    _areaId = v;
                    _errorDeArea = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),

                RisegSelect<String>(
                  label: 'Tipo',
                  value: _tipo,
                  // CÓDIGO, ÁREA Y TIPO sólo se fijan al crear, así que su puerta
                  // es `puedeCrear`.
                  enabled: widget.capacidades.puedeCrear && _esNuevo,
                  hint: 'Elige el tipo',
                  errorText: _errorDeTipo,
                  helperText: _esNuevo
                      ? 'Operativo: el personal que cubre los servicios con los '
                            'clientes (elementos, jefes de turno, supervisores). '
                            'Administrativo: el personal de oficina (RH, '
                            'contabilidad, dirección).'
                      : 'El tipo no se cambia.',
                  // CINCO LÍNEAS, PEDIDAS A PROPÓSITO. Son dos definiciones con sus
                  // ejemplos y no caben en las dos de por omisión: con menos se veía
                  // «Operativo: el personal que cubre los servicios con los…» y la
                  // mitad que explica «administrativo» no llegaba nunca.
                  helperMaxLines: 5,
                  items: const [
                    RisegSelectItem(value: 'operativo', label: 'Operativo'),
                    RisegSelectItem(
                      value: 'administrativo',
                      label: 'Administrativo',
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _tipo = v;
                    _errorDeTipo = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),

                RisegTextField(
                  label: 'Nombre',
                  controller: _nombre,
                  // NOMBRE, NIVEL Y DESCRIPCIÓN son datos: «modificar», o «crear»
                  // si el puesto todavía no existe. Nunca «archivar».
                  enabled: _esNuevo
                      ? widget.capacidades.puedeCrear
                      : widget.capacidades.puedeModificar,
                  errorText: _errorDeNombre,
                  helperText: 'Lo que vas a leer en las listas, como Supervisor.',
                ),
                const SizedBox(height: AppSpacing.md),

                // EL NIVEL COMO LISTA DE DIEZ, no como campo numérico: no admite un
                // valor inválido y enseña la escala antes de que el servidor la
                // explique con un error.
                RisegSelect<int>(
                  label: 'Nivel jerárquico',
                  value: _nivel,
                  // NOMBRE, NIVEL Y DESCRIPCIÓN son datos: «modificar», o «crear»
                  // si el puesto todavía no existe. Nunca «archivar».
                  enabled: _esNuevo
                      ? widget.capacidades.puedeCrear
                      : widget.capacidades.puedeModificar,
                  hint: 'Elige el nivel',
                  errorText: _errorDeNivel,
                  helperText: 'Del 1 al 10. El 1 es el más bajo.',
                  items: [
                    for (var n = 1; n <= 10; n++)
                      RisegSelectItem(
                        value: n,
                        // SÓLO LOS EXTREMOS SE ANOTAN. Anotar los diez sería ruido.
                        label: switch (n) {
                          1 => '1 · el más bajo',
                          10 => '10 · el más alto',
                          _ => '$n',
                        },
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _nivel = v;
                    _errorDeNivel = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),

                RisegTextField(
                  label: 'Descripción',
                  controller: _descripcion,
                  // NOMBRE, NIVEL Y DESCRIPCIÓN son datos: «modificar», o «crear»
                  // si el puesto todavía no existe. Nunca «archivar».
                  enabled: _esNuevo
                      ? widget.capacidades.puedeCrear
                      : widget.capacidades.puedeModificar,
                  maxLines: 3,
                  helperText: 'Opcional.',
                ),

                if (!_esNuevo) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Switch(
                        value: _activo,
                        // EL INTERRUPTOR ES «ARCHIVAR», en las dos direcciones. Sin
                        // `onChanged` se pinta apagado y no se mueve: el estado de
                        // un puesto es dato que se consulta.
                        onChanged: widget.capacidades.puedeArchivar
                            ? (v) => setState(() => _activo = v)
                            : null,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _activo
                              ? 'Activo: se puede asignar a una persona.'
                              : 'Inactivo: desaparece de los selectores, y las '
                                    'personas que ya lo tienen asignado no cambian.',
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // LA PREGUNTA QUE TODO EL MUNDO VA A TENER frente a tres campos en
                // gris, contestada donde se ve.
                if (!_esNuevo) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Para cambiar el área o el tipo de un puesto, desactívalo y crea '
                    'otro: su historia laboral ya lo referencia.',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),

                  // LAS DOS FECHAS DEL EXPEDIENTE. Van al final y en letra pequeña: son
                  // dato de referencia, no algo que se edite — y por eso no son campos.
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _fechasDelExpediente(widget.puesto!),
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),

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

                // ELIMINAR, APARTE Y ABAJO. Mismo patrón que las otras tres: no se
                // pulsa por error buscando «Guardar», y pertenece a otra categoría.
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
                    'Sólo se puede eliminar un puesto que nunca se usó. Si alguien lo '
                    'ocupó —aunque ya se haya ido— o tiene vigencias comerciales, '
                    'desactívalo.',
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

      // ÁREA Y TIPO SÓLO SE EXIGEN AL CREAR, que es lo que el servidor exige. Al
      // editar ni se mandan.
      _errorDeArea = _esNuevo && _areaId == null ? 'Elige un área.' : null;
      _errorDeTipo = _esNuevo && _tipo == null ? 'Elige el tipo.' : null;

      // EL NIVEL SE EXIGE AL CREAR. Al editar se permite dejarlo sin poner, porque
      // un puesto viejo puede no tenerlo y corregirle el nombre no debe forzar a
      // inventárselo.
      _errorDeNivel = _esNuevo && _nivel == null ? 'Elige el nivel.' : null;
    });

    if (_errorDeCodigo != null ||
        _errorDeNombre != null ||
        _errorDeArea != null ||
        _errorDeTipo != null ||
        _errorDeNivel != null) {
      return;
    }

    setState(() => _guardando = true);

    // UN REINTENTO SI EL CÓDIGO SUGERIDO CHOCA. Aquí pasa de verdad: `PUE-####` se
    // sugiere desde M3 y nadie lo teclea, así que un choque es casi siempre dos
    // personas creando a la vez.
    final resultado = _esNuevo
        ? await crearConReintentoDeCodigo(
            prefijo: PrefijoDeCodigo.puesto,
            codigoUsado: codigo,
            codigoSugerido: widget.sePudoCalcularElCodigo
                ? widget.codigoSugerido
                : null,
            crear: (c) => widget.repositorio.crear(
              empresaId: widget.empresaId,
              areaId: _areaId!,
              codigo: c,
              nombre: nombre,
              tipo: _tipo!,
              nivel: _nivel!,
              descripcion: _descripcion.text,
            ),
            codigosActuales: () async =>
                (await widget.repositorio.listar(widget.empresaId)).when(
                  ok: (puestos) => Result.ok([for (final p in puestos) p.codigo]),
                  failure: Result.failure,
                ),
          )
        : await widget.repositorio.modificar(
            empresaId: widget.empresaId,
            puestoId: widget.puesto!.id,
            nombre: nombre,
            nivel: _nivel,
            descripcion: _descripcion.text.trim(),
            activo: _activo,
          );

    if (!mounted) return;

    resultado.when(
      ok: (_) {
        RisegFeedback.showSuccess(
          context,
          _esNuevo ? 'Puesto creado.' : 'Puesto actualizado.',
        );
        Navigator.of(context).pop(true);
      },
      failure: (f) => setState(() {
        _guardando = false;

        // EL CHOQUE DE CÓDIGO SE MUESTRA EN EL CAMPO, no en un aviso que se va: es lo
        // único que el usuario puede arreglar sin salir del formulario. Y con el
        // código sugerido pasa de verdad: si alguien tecleó uno a mano con el mismo
        // número, el consecutivo lo propone igual.
        // Y SE MIRA EL CÓDIGO DEL SERVIDOR, no el 409 a secas: desde M3 un
        // `desactivacion_bloqueada` —«3 personas activas tienen este puesto»— también
        // es 409, y no se arregla cambiando nada de este formulario.
        if (f case ApiHttpFailure(codigo: 'code_conflict')) {
          _errorDeCodigo = f.message;
        } else {
          mostrarRechazoDelServidor(context, f.message);
        }
      }),
    );
  }

  /// «Creado el 3/oct/2026 · actualizado el 19/oct/2026», y lo que se pueda decir.
  ///
  /// **Si una fecha no vino, NO se inventa ni se esconde la otra.** Contra un servidor
  /// anterior a que la ruta las expusiera, `createdAt` llega nulo: entonces se dice sólo
  /// la que hay. Y si no hay ninguna, se dice **eso** —no un guion, no una fecha vacía—
  /// porque «no se sabe cuándo» es una respuesta y un espacio en blanco no.
  String _fechasDelExpediente(Puesto puesto) {
    final partes = <String>[
      if (puesto.creadoEn case final f?) 'Creado el ${_fechaCorta(f)}',
      if (puesto.actualizadoEn case final f?) 'actualizado el ${_fechaCorta(f)}',
    ];

    return partes.isEmpty
        ? 'No se sabe cuándo se creó ni cuándo se actualizó.'
        : '${partes.join(' · ')}.';
  }

  /// `3/oct/2026`, **en la zona del navegador**: una fecha en UTC le diría «2/oct» a
  /// quien está en México después de las 18:00, y nadie entendería por qué.
  static String _fechaCorta(DateTime utc) {
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];

    final local = utc.toLocal();

    return '${local.day}/${meses[local.month - 1]}/${local.year}';
  }

  /// Elimina el puesto, con motivo. **Sólo Maestro, y sólo si nunca se usó.**
  ///
  /// El servidor cuenta **todas** las asignaciones de personal, vigentes o cerradas, y
  /// las vigencias comerciales. Por eso un puesto puede desactivarse —nadie activo lo
  /// ocupa— y aun así no poderse borrar: su historia laboral existe y tiene que poder
  /// conservarse.
  Future<void> _eliminar() async {
    final motivo = await pedirMotivoDeEliminacion(
      context,
      queEs: 'el puesto',
      comoSeLlama: '${widget.puesto!.codigo} · ${widget.puesto!.nombre}',
      queSePierde: 'El puesto desaparece de la empresa.',
    );

    if (motivo == null || !mounted) return;

    setState(() => _eliminando = true);

    final resultado = await widget.repositorio.eliminar(
      empresaId: widget.empresaId,
      puestoId: widget.puesto!.id,
      motivo: motivo,
    );

    if (!mounted) return;

    resultado.when(
      ok: (puesto) {
        RisegFeedback.showSuccess(context, 'Se eliminó el puesto ${puesto.nombre}.');
        Navigator.of(context).pop(true);
      },
      failure: (f) {
        setState(() => _eliminando = false);
        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }
}
