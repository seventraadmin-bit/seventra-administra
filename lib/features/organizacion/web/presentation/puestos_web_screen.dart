import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../datos/areas_repositorio_http.dart';
import '../datos/puestos_repositorio_http.dart';
import '../modelos/area.dart';
import '../modelos/puesto.dart';

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
    this.alIrAAreas,
    super.key,
  });

  final PuestosRepositorioHttp repositorio;

  /// El de áreas, **que ya existía**: las áreas tienen su propia pestaña y aquí sólo
  /// se leen, para el selector y para poner su nombre en la lista.
  final AreasRepositorioHttp repositorioDeAreas;

  final String empresaId;

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
        primaryAction: RisegButton(
          label: 'Nuevo puesto',
          icon: Icons.add,
          onPressed: () => _abrirPanel(),
        ),
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
  });

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
  });

  final Puesto? puesto;
  final List<Area> areas;
  final String codigoSugerido;
  final bool sePudoCalcularElCodigo;
  final String empresaId;
  final PuestosRepositorioHttp repositorio;

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
                  _esNuevo ? 'Nuevo puesto' : 'Editar puesto',
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                RisegTextField(
                  label: 'Código',
                  controller: _codigo,
                  enabled: _esNuevo,
                  errorText: _errorDeCodigo,
                  helperText: _esNuevo
                      ? (widget.sePudoCalcularElCodigo
                            ? 'Se sugiere automáticamente. No se podrá cambiar.'
                            : 'Escríbelo: no se pudieron leer los puestos para '
                                  'sugerirlo. No se podrá cambiar.')
                      : 'El código no se cambia.',
                ),
                const SizedBox(height: AppSpacing.md),

                RisegSelect<String>(
                  label: 'Área',
                  value: _areaId,
                  enabled: _esNuevo,
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
                  enabled: _esNuevo,
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
                  maxLines: 3,
                  helperText: 'Opcional.',
                ),

                if (!_esNuevo) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Switch(
                        value: _activo,
                        onChanged: (v) => setState(() => _activo = v),
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
                ],

                const SizedBox(height: AppSpacing.xl),
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

    final resultado = _esNuevo
        ? await widget.repositorio.crear(
            empresaId: widget.empresaId,
            areaId: _areaId!,
            codigo: codigo,
            nombre: nombre,
            tipo: _tipo!,
            nivel: _nivel!,
            descripcion: _descripcion.text,
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
        if (f case ApiHttpFailure(statusCode: 409)) {
          _errorDeCodigo = f.message;
        } else {
          RisegFeedback.showError(context, f.message);
        }
      }),
    );
  }
}
