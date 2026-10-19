import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../datos/sucursales_repositorio_http.dart';
import '../modelos/codigo_sugerido.dart';
import '../modelos/sucursal.dart';
import '../modelos/tipo_de_sucursal.dart';
import 'eliminar_estructura.dart';
import 'tipos_de_sucursal_web_screen.dart';

/// Sucursales: los destinos **administrativos** de la empresa.
///
/// ## La regla del dominio que más se confunde
///
/// **Sucursal es administrativa; Servicio es operativo.** Dónde está dada de alta una
/// persona no es dónde trabaja, y Personal **nunca** usa Sucursal como sustituto de
/// Servicio. Esta pantalla no lo impone —eso es del servidor— pero tampoco lo sugiere.
///
/// ## Los tipos viven aquí dentro, detrás de un botón
///
/// No son una pestaña: un cliente abre «Sucursales» para ver sus sucursales, y los
/// tipos son el catálogo que las ordena. Darles el mismo peso en la navegación que a
/// la cosa que ordenan sería al revés.
///
/// ## Dos estados que no son el mismo
///
/// **Activa** es si está dada de alta; **operando** es si está abierta hoy. Una
/// sucursal activa puede estar cerrada temporalmente, y una inactiva ya no se usa en
/// absoluto. El servidor los manda por separado y aquí se muestran por separado:
/// derivar uno del otro perdería la mitad del dato.
class SucursalesWebScreen extends StatefulWidget {
  const SucursalesWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.esMaestro,
    this.alCambiarElRastro,
    super.key,
  });

  final SucursalesRepositorioHttp repositorio;
  final String empresaId;

  /// Si quien mira es Maestro de ESTA empresa. **Sólo gobierna si el botón de eliminar
  /// se OFRECE**, nunca si se puede: eso lo decide el servidor. Sale de
  /// `CompanyContext.isMaestro`, que vino de `/context`.
  final bool esMaestro;

  /// Avisa de lo que se abrió **dentro** de esta pantalla, para el rastro.
  ///
  /// Recibe `'Tipos de sucursal'` al entrar al catálogo y `null` al volver. Existe
  /// porque **Tipos de sucursal no es una pestaña** —vive aquí dentro, detrás de un
  /// botón— y el portón, que es quien dibuja el rastro, no se enteraría: se quedaba
  /// diciendo «Organización › Sucursales» estando en el catálogo.
  ///
  /// ⏳ **Lo que lo hará innecesario es el router.** Cuando el `bool` de abajo sea una
  /// ruta hija, el rastro saldrá de la ruta y esta vía de comunicación hacia arriba
  /// desaparecerá.
  final ValueChanged<String?>? alCambiarElRastro;

  @override
  State<SucursalesWebScreen> createState() => _SucursalesWebScreenState();
}

class _SucursalesWebScreenState extends State<SucursalesWebScreen> {
  List<Sucursal>? _sucursales;
  List<TipoDeSucursal>? _tipos;
  Failure? _fallo;
  bool _cargando = true;

  /// **Las inactivas se ocultan por omisión**, y el filtro vive aquí y no en la
  /// petición: pedirle al servidor sólo las activas obligaría a una segunda petición
  /// al encender el interruptor, y a tener dos listas que pueden discrepar.
  bool _mostrarInactivas = false;

  /// ¿Se está viendo el catálogo de tipos en lugar de la lista?
  ///
  /// Un `bool` y no una ruta, porque la web todavía no tiene router. Cuando lo tenga,
  /// esto se convierte en una ruta hija y la pantalla no cambia.
  bool _viendoTipos = false;

  /// Entra o sale del catalogo de tipos, **y avisa del rastro en el mismo acto**.
  ///
  /// Es un solo metodo a proposito: con tres sitios cambiando el `bool` por su
  /// cuenta, uno se olvidaria de avisar y el rastro quedaria mintiendo.
  void _verTipos(bool viendo) {
    setState(() => _viendoTipos = viendo);
    widget.alCambiarElRastro?.call(viendo ? 'Tipos de sucursal' : null);
  }

  final _buscador = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    // LAS DOS A LA VEZ: el selector de tipos del formulario necesita el catálogo, y
    // en serie la pantalla tardaría el doble en pintar algo.
    final (sucursales, tipos) = await (
      widget.repositorio.listar(widget.empresaId),
      widget.repositorio.listarTipos(widget.empresaId),
    ).wait;

    if (!mounted) return;

    setState(() {
      _cargando = false;

      sucursales.when(
        ok: (s) => _sucursales = s,
        failure: (f) => _fallo = f,
      );

      // EL CATÁLOGO NO MANDA SOBRE LA PANTALLA. Si falla, la lista sigue siendo útil
      // y lo que no se podrá es dar de alta — y eso se dice al intentarlo.
      tipos.when(ok: (t) => _tipos = t, failure: (_) => _tipos = null);
    });
  }

  /// Filtrado por estado y por el buscador, en ese orden. **El buscador mira nombre Y
  /// código**: quien escribe «cen» puede estar buscando «Centro» o el código `CEN`.
  List<Sucursal> get _visibles {
    final todas = _sucursales ?? const <Sucursal>[];
    final texto = _buscador.text.trim().toLowerCase();

    return todas.where((s) {
      if (!_mostrarInactivas && !s.activa) return false;
      if (texto.isEmpty) return true;

      return s.nombre.toLowerCase().contains(texto) ||
          s.codigo.toLowerCase().contains(texto);
    }).toList();
  }

  int get _inactivas => (_sucursales ?? const <Sucursal>[]).where((s) => !s.activa).length;

  /// El nombre del tipo de una sucursal, o `null` si no tiene o no se pudo leer el
  /// catálogo. **Nunca el identificador**: un UUID en una lista no le dice nada a
  /// nadie.
  String? _nombreDelTipo(String? tipoId) {
    if (tipoId == null) return null;

    for (final t in _tipos ?? const <TipoDeSucursal>[]) {
      if (t.id == tipoId) return t.nombre;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_viendoTipos) {
      return TiposDeSucursalWebScreen(
        repositorio: widget.repositorio,
        empresaId: widget.empresaId,
        esMaestro: widget.esMaestro,
        // AL VOLVER SE RECARGA, porque el catálogo pudo cambiar y la lista muestra
        // nombres de tipo: sin recargar, una sucursal seguiría diciendo el nombre
        // viejo o un hueco.
        onVolver: () {
          _verTipos(false);
          _cargar();
        },
      );
    }

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Encabezado(
                total: _sucursales?.length ?? 0,
                inactivas: _inactivas,
                onTipos: () => _verTipos(true),
                onNueva: _cargando ? null : () => _abrirPanel(),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: RisegSearchField(
                      hint: 'Buscar por nombre o código',
                      controller: _buscador,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  // EL INTERRUPTOR SÓLO APARECE SI HAY ALGO QUE MOSTRAR.
                  if (_inactivas > 0) ...[
                    const SizedBox(width: AppSpacing.md),
                    Row(
                      children: [
                        Switch(
                          value: _mostrarInactivas,
                          onChanged: (v) => setState(() => _mostrarInactivas = v),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Mostrar inactivas',
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
        title: 'No se pudieron cargar las sucursales',
        message: f.message,
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    if ((_sucursales ?? const <Sucursal>[]).isEmpty) {
      // EL VACÍO EXPLICA QUÉ ES UNA SUCURSAL, porque quien abre esto por primera vez
      // puede no saber en qué se diferencia de un servicio.
      return RisegEmptyState(
        icon: Icons.store_outlined,
        title: 'Todavía no hay sucursales',
        message:
            'Una sucursal es un destino administrativo: donde das de alta a tu gente '
            'y donde se lleva su papeleo. No es donde opera —eso es el servicio—.',
        primaryAction: RisegButton(
          label: 'Nueva sucursal',
          icon: Icons.add,
          onPressed: () => _abrirPanel(),
        ),
      );
    }

    // VACÍO POR FILTRO: hay sucursales, pero ninguna encaja. Es un mensaje DISTINTO, y
    // confundirlos haría pensar que no hay nada capturado.
    if (_visibles.isEmpty) {
      return RisegEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Ninguna sucursal coincide',
        message: _buscador.text.trim().isEmpty
            ? 'Todas las sucursales están inactivas. Enciende «Mostrar inactivas» '
                  'para verlas.'
            : 'Ninguna sucursal se llama o se codifica como '
                  '«${_buscador.text.trim()}».',
      );
    }

    return ListView.separated(
      itemCount: _visibles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _Fila(
        sucursal: _visibles[i],
        tipo: _nombreDelTipo(_visibles[i].tipoId),
        onTocar: () => _abrirPanel(sucursal: _visibles[i]),
      ),
    );
  }

  Future<void> _abrirPanel({Sucursal? sucursal}) async {
    final tipos = (_tipos ?? const <TipoDeSucursal>[])
        .where((t) => t.activo || t.id == sucursal?.tipoId)
        .toList();

    // SIN UN TIPO NO SE PUEDE DAR DE ALTA, y el servidor lo exige. En vez de apagar
    // el botón —que dejaría al usuario sin saber por qué— se abre el camino para
    // resolverlo: es una precondición de DATOS que el cliente conoce, no una
    // suposición sobre la autorización.
    if (sucursal == null && tipos.isEmpty) {
      final irATipos = await RisegDialog.showConfirmation(
        context: context,
        title: 'Primero hace falta un tipo de sucursal',
        message:
            'Dar de alta una sucursal pide su tipo —oficina, bodega—, y todavía no '
            'hay ninguno activo. Puedes agregar los recomendados de una vez.',
        confirmLabel: 'Ver tipos de sucursal',
        cancelLabel: 'Ahora no',
      );

      if ((irATipos ?? false) && mounted) _verTipos(true);
      return;
    }

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeSucursal(
        sucursal: sucursal,
        tipos: tipos,
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
        esMaestro: widget.esMaestro,
        // SUGERIDO COMO EN EL ESCRITORIO, y nada si la lista no se pudo leer: un
        // SUC-0001 inventado chocaría con el que ya existe.
        codigoSugerido: _sucursales == null
            ? null
            : siguienteCodigo(
                PrefijoDeCodigo.sucursal,
                _sucursales!.map((s) => s.codigo),
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
    required this.onTipos,
    required this.onNueva,
  });

  final int total;
  final int inactivas;
  final VoidCallback onTipos;
  final VoidCallback? onNueva;

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
              const Text('Sucursales', style: AppTypography.heading1),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _resumen(),
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        // LOS TIPOS, SECUNDARIOS Y A LA IZQUIERDA del principal: son el catálogo que
        // ordena la lista, no la acción que se viene a hacer.
        RisegButton(
          label: 'Tipos de sucursal',
          variant: RisegButtonVariant.secondary,
          icon: Icons.category_outlined,
          onPressed: onTipos,
        ),
        const SizedBox(width: AppSpacing.sm),
        RisegButton(label: 'Nueva sucursal', icon: Icons.add, onPressed: onNueva),
      ],
    );
  }

  /// **Un cero no se anuncia.** «3 sucursales» a secas cuando ninguna está inactiva.
  String _resumen() {
    final cuantas = total == 1 ? '1 sucursal' : '$total sucursales';

    if (inactivas == 0) return cuantas;

    return '$cuantas · ${inactivas == 1 ? '1 inactiva' : '$inactivas inactivas'}';
  }
}

// ===========================================================================
// Una fila
// ===========================================================================

class _Fila extends StatelessWidget {
  const _Fila({required this.sucursal, required this.tipo, required this.onTocar});

  final Sucursal sucursal;
  final String? tipo;
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
                  Text(sucursal.nombre, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    // SIN TIPO SE DICE «sin tipo», no se calla: la columna es
                    // opcional por historia, y un hueco parecería un fallo de carga.
                    tipo == null
                        ? '${sucursal.codigo} · sin tipo'
                        : '${sucursal.codigo} · $tipo',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),

            // CERRADA TEMPORALMENTE SE AVISA APARTE DE INACTIVA, porque no son lo
            // mismo: una está de baja y la otra sólo cerrada hoy.
            if (sucursal.estadoOperativo != 'operando') ...[
              const RisegStatusBadge(
                label: 'Cerrada',
                tone: RisegStatusTone.warning,
                icon: Icons.door_front_door_outlined,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],

            RisegStatusBadge(
              label: sucursal.activa ? 'Activa' : 'Inactiva',
              tone: sucursal.activa
                  ? RisegStatusTone.success
                  : RisegStatusTone.neutral,
              icon: sucursal.activa
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

class _PanelDeSucursal extends StatefulWidget {
  const _PanelDeSucursal({
    required this.sucursal,
    required this.tipos,
    required this.empresaId,
    required this.repositorio,
    required this.esMaestro,
    required this.codigoSugerido,
  });

  final Sucursal? sucursal;
  final List<TipoDeSucursal> tipos;
  final String empresaId;
  final SucursalesRepositorioHttp repositorio;
  final bool esMaestro;

  /// El código que se propone para una sucursal nueva, o `null` si no se pudo calcular.
  final String? codigoSugerido;

  @override
  State<_PanelDeSucursal> createState() => _PanelDeSucursalState();
}

class _PanelDeSucursalState extends State<_PanelDeSucursal> {
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();

  String? _tipoId;
  bool _activa = true;
  bool _cerrada = false;
  bool _guardando = false;
  bool _cambiandoOperativo = false;
  bool _eliminando = false;
  String? _errorDeCodigo;
  String? _errorDeNombre;
  String? _errorDeTipo;

  bool get _esNueva => widget.sucursal == null;

  @override
  void initState() {
    super.initState();

    if (widget.sucursal case final s?) {
      _codigo.text = s.codigo;
      _nombre.text = s.nombre;
      _tipoId = s.tipoId;
      _activa = s.activa;
      _cerrada = s.estadoOperativo != 'operando';
    } else {
      // AL CREAR, EL CÓDIGO LLEGA SUGERIDO Y SIGUE SIENDO EDITABLE.
      _codigo.text = widget.codigoSugerido ?? '';

      if (widget.tipos.length == 1) {
        // CON UN SOLO TIPO SE PRESELECCIONA, porque elegir entre uno no es una
        // decisión. Con dos o más no se adivina.
        _tipoId = widget.tipos.single.id;
      }
    }
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _esNueva ? 'Nueva sucursal' : 'Editar sucursal',
                  style: AppTypography.heading2,
                ),
                const SizedBox(height: AppSpacing.lg),

                RisegTextField(
                  label: 'Código',
                  controller: _codigo,
                  enabled: _esNueva,
                  errorText: _errorDeCodigo,
                  // LA MISMA AYUDA QUE ÁREAS Y PUESTOS, de una sola función. El texto
                  // anterior —«Corto y en mayúsculas, como CEN»— era de antes de que
                  // existiera la sugerencia, así que describía un campo vacío que ya
                  // llegaba lleno.
                  helperText: ayudaDelCodigo(
                    esNuevo: _esNueva,
                    haySugerencia: widget.codigoSugerido != null,
                    queEs: 'a la sucursal',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                RisegTextField(
                  label: 'Nombre',
                  controller: _nombre,
                  errorText: _errorDeNombre,
                  helperText: 'Como Centro o Matriz.',
                ),
                const SizedBox(height: AppSpacing.md),

                RisegSelect<String>(
                  label: 'Tipo de sucursal',
                  value: _tipoId,
                  errorText: _errorDeTipo,
                  hint: 'Elige un tipo',
                  items: [
                    for (final t in widget.tipos)
                      RisegSelectItem(value: t.id, label: t.nombre),
                  ],
                  onChanged: (v) => setState(() {
                    _tipoId = v;
                    _errorDeTipo = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),

                if (!_esNueva) ...[
                  // CERRAR Y REABRIR SON UNA ACCIÓN, NO UN INTERRUPTOR, y el cambio
                  // es deliberado: aquí había un `Switch` dentro del formulario, que
                  // es exactamente lo que el producto de escritorio se niega a hacer
                  // —«nunca un campo silencioso del formulario de edición»—.
                  //
                  // El servidor lo impone además de la pantalla: `operationalStatus`
                  // salió del `PATCH` y sólo se cambia por sus dos rutas. Así que
                  // esto no es estilo: es el único camino que existe.
                  //
                  // Y SE APLICA DE INMEDIATO, sin esperar a «Guardar». Es otra
                  // operación, con su propia confirmación y su propio evento de
                  // auditoría; mezclarla con el guardado haría que cerrar una
                  // sucursal dependiera de que alguien no pulse «Cancelar» después.
                  Row(
                    children: [
                      RisegStatusBadge(
                        label: _cerrada ? 'Cerrada temporalmente' : 'Operando',
                        tone: _cerrada
                            ? RisegStatusTone.warning
                            : RisegStatusTone.success,
                        icon: _cerrada
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      RisegButton(
                        label: _cerrada ? 'Reabrir' : 'Cerrar temporalmente',
                        variant: RisegButtonVariant.secondary,
                        size: RisegButtonSize.compact,
                        loading: _cambiandoOperativo,
                        onPressed: _guardando || _cambiandoOperativo || _eliminando
                            ? null
                            : _cambiarEstadoOperativo,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _cerrada
                        ? 'Cerrada hoy, pero sigue dada de alta: puede volver a '
                              'abrir. Alguien tiene que reabrirla.'
                        : 'Abierta hoy. Cerrar temporalmente no la da de baja.',
                    style: AppTypography.caption.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Switch(
                        value: _activa,
                        onChanged: (v) => setState(() => _activa = v),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _activa
                              ? 'Activa: se puede usar en el sistema.'
                              : 'Inactiva: ya no se usa. No es lo mismo que cerrada '
                                    'temporalmente.',
                          style: AppTypography.caption.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // ELIMINAR VA APARTE Y ABAJO, separado por una línea de Guardar y
                // Cancelar: no se pulsa por error, y pertenece a otra categoría.
                if (!_esNueva && widget.esMaestro) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RisegButton(
                      label: 'Eliminar definitivamente',
                      variant: RisegButtonVariant.danger,
                      icon: Icons.delete_outline,
                      size: RisegButtonSize.compact,
                      loading: _eliminando,
                      onPressed: _guardando || _eliminando || _cambiandoOperativo
                          ? null
                          : _eliminar,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Sólo se puede eliminar una sucursal que nunca se usó. Si tiene '
                    'personal o servicios, ciérrala y desactívala.',
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
      _errorDeCodigo = _esNueva && codigo.isEmpty ? 'Escribe un código.' : null;
      _errorDeNombre = nombre.isEmpty ? 'Escribe un nombre.' : null;
      // EL TIPO SÓLO ES OBLIGATORIO AL CREAR, que es lo que el servidor exige. Al
      // editar se puede dejar el que tenía.
      _errorDeTipo = _esNueva && _tipoId == null ? 'Elige un tipo.' : null;
    });

    if (_errorDeCodigo != null || _errorDeNombre != null || _errorDeTipo != null) {
      return;
    }

    setState(() => _guardando = true);

    // UN REINTENTO SI EL CÓDIGO SUGERIDO CHOCA. Mismo motivo que en Áreas: la
    // sugerencia la calcula el cliente, así que dos personas creando a la vez reciben
    // el mismo número.
    final resultado = _esNueva
        ? await crearConReintentoDeCodigo(
            prefijo: PrefijoDeCodigo.sucursal,
            codigoUsado: codigo,
            codigoSugerido: widget.codigoSugerido,
            crear: (c) => widget.repositorio.crear(
              empresaId: widget.empresaId,
              codigo: c,
              nombre: nombre,
              tipoId: _tipoId!,
            ),
            codigosActuales: () async =>
                (await widget.repositorio.listar(widget.empresaId)).when(
                  ok: (sucursales) =>
                      Result.ok([for (final s in sucursales) s.codigo]),
                  failure: Result.failure,
                ),
          )
        : await widget.repositorio.modificar(
            empresaId: widget.empresaId,
            sucursalId: widget.sucursal!.id,
            nombre: nombre,
            tipoId: _tipoId,
            activa: _activa,
          );

    if (!mounted) return;

    resultado.when(
      ok: (_) {
        RisegFeedback.showSuccess(
          context,
          _esNueva ? 'Sucursal creada.' : 'Sucursal actualizada.',
        );
        Navigator.of(context).pop(true);
      },
      failure: (f) => setState(() {
        _guardando = false;

        // SÓLO EL CHOQUE DE CÓDIGO VA AL CAMPO DEL CÓDIGO. Un
        // `desactivacion_bloqueada` —«la sucursal sigue operando» o «1 persona activa
        // asignada»— no se arregla reescribiendo nada del formulario, así que ponerlo
        // ahí mandaría a la persona a cambiar un código que está bien.
        if (f case ApiHttpFailure(codigo: 'code_conflict')) {
          _errorDeCodigo = f.message;
        } else {
          mostrarRechazoDelServidor(context, f.message);
        }
      }),
    );
  }

  /// Cierra temporalmente o reabre, **con confirmación y de inmediato**.
  ///
  /// La confirmación no es ceremonia: cerrar una sucursal la saca de la operación del
  /// día, y reabrirla es una decisión que alguien tiene que tomar a mano. El producto de
  /// escritorio también confirma.
  Future<void> _cambiarEstadoOperativo() async {
    final cerrando = !_cerrada;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: cerrando ? 'Cerrar temporalmente' : 'Reabrir sucursal',
      message: cerrando
          ? '${widget.sucursal!.nombre} dejará de aparecer como abierta. '
                'Sigue dada de alta y alguien tendrá que reabrirla.'
          : '${widget.sucursal!.nombre} volverá a aparecer como abierta hoy.',
      confirmLabel: cerrando ? 'Cerrar temporalmente' : 'Reabrir',
      cancelLabel: 'Cancelar',
    );

    if (!(confirmado ?? false) || !mounted) return;

    setState(() => _cambiandoOperativo = true);

    final resultado = cerrando
        ? await widget.repositorio.cerrarTemporalmente(
            empresaId: widget.empresaId,
            sucursalId: widget.sucursal!.id,
          )
        : await widget.repositorio.reabrir(
            empresaId: widget.empresaId,
            sucursalId: widget.sucursal!.id,
          );

    if (!mounted) return;

    resultado.when(
      ok: (sucursal) {
        setState(() {
          _cambiandoOperativo = false;
          // SE LEE DEL SERVIDOR, no se asume. Si el servidor hubiera decidido otra
          // cosa —y la ruta es idempotente, así que puede devolver la fila sin
          // cambiar—, la pantalla contaría una historia falsa.
          _cerrada = sucursal.estadoOperativo != 'operando';
        });

        RisegFeedback.showSuccess(
          context,
          cerrando
              ? 'Se cerró temporalmente ${sucursal.nombre}.'
              : 'Se reabrió ${sucursal.nombre}.',
        );
      },
      failure: (f) {
        setState(() => _cambiandoOperativo = false);

        // AQUÍ CAE «no se puede reabrir una sucursal inactiva». El botón no se esconde
        // por eso: esconderlo dejaría a la persona sin saber qué le falta.
        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }

  /// Elimina la sucursal, con motivo. **Sólo Maestro, y sólo si nunca se usó.**
  Future<void> _eliminar() async {
    final motivo = await pedirMotivoDeEliminacion(
      context,
      queEs: 'la sucursal',
      comoSeLlama: '${widget.sucursal!.codigo} · ${widget.sucursal!.nombre}',
      queSePierde: 'La sucursal desaparece de la empresa.',
    );

    if (motivo == null || !mounted) return;

    setState(() => _eliminando = true);

    final resultado = await widget.repositorio.eliminar(
      empresaId: widget.empresaId,
      sucursalId: widget.sucursal!.id,
      motivo: motivo,
    );

    if (!mounted) return;

    resultado.when(
      ok: (sucursal) {
        RisegFeedback.showSuccess(
          context,
          'Se eliminó la sucursal ${sucursal.nombre}.',
        );
        Navigator.of(context).pop(true);
      },
      failure: (f) {
        setState(() => _eliminando = false);
        mostrarRechazoDelServidor(context, f.message);
      },
    );
  }
}
