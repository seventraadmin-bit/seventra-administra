import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL: esta feature no puede importar el catálogo de
// permisos —hay un guardia que lo impide— y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;

import '../../../../app/shell/se_cierra_al_cambiar_la_direccion.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../datos/sucursales_repositorio_http.dart';
import '../modelos/codigo_sugerido.dart';
import '../modelos/sucursal.dart';
import '../modelos/tipo_de_sucursal.dart';
import 'eliminar_estructura.dart';
import 'expediente_sucursal_web_screen.dart';
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
    required this.repositorioDeExpedientes,
    required this.empresaId,
    required this.esMaestro,
    required this.capacidades,
    required this.puedeEditarExpedientes,
    required this.viendoTipos,
    required this.expedienteDe,
    required this.alVerTipos,
    required this.alVerExpediente,
    required this.guardia,
    this.alConocerElNombre,
    super.key,
  });

  final SucursalesRepositorioHttp repositorio;

  /// El de los expedientes. **Es otro repositorio y no un método más de éste**: el
  /// expediente comparte la forma del domicilio y el control de versión con el de la
  /// empresa, no con el alta de sucursales.
  final ExpedientesRepositorioHttp repositorioDeExpedientes;

  final String empresaId;

  /// Si quien mira es Maestro de ESTA empresa. **Sólo gobierna si el botón de eliminar
  /// se OFRECE**, nunca si se puede: eso lo decide el servidor. Sale de
  /// `CompanyContext.isMaestro`, que vino de `/context`.
  final bool esMaestro;

  /// Qué puede hacer aquí quien mira: crear, modificar, archivar.
  ///
  /// <b>ANTES ERA UN SOLO `puedeEditarExpedientes` QUE GOBERNABA SÓLO EL
  /// EXPEDIENTE.</b> Eso dejó el resto de la pantalla abierta: un usuario con rol
  /// Usuario y CERO permisos veía «Nueva sucursal», «Tipos de sucursal», «Cerrar
  /// temporalmente» y los interruptores, porque ninguno estaba atado a nada.
  ///
  /// Y las acciones **no comparten permiso**: crear es `organizacion.crear`,
  /// renombrar y cerrar temporalmente son `organizacion.modificar`, y el interruptor
  /// es `organizacion.archivar`. Una bandera única los colapsaría otra vez.
  ///
  /// **No es `esMaestro`**: son dos autoridades distintas. Sale de los permisos
  /// efectivos que confirmó el servidor.
  final CapacidadesDeModulo capacidades;

  /// Si se puede editar el EXPEDIENTE de una sucursal, que se abre desde dentro de
  /// esta pantalla.
  ///
  /// **Es otra familia de permisos** —`company.settings.manage`, el del expediente—
  /// y por eso viaja aparte de [capacidades]: quien puede renombrar una sucursal no
  /// necesariamente puede escribir su domicilio fiscal.
  final bool puedeEditarExpedientes;

  /// ¿Se está viendo el catálogo de tipos? **Lo dice la DIRECCIÓN**, no esta pantalla.
  ///
  /// ✅ **ERA LA DEUDA D-39.** Esto era un `bool` de estado local, y como «Tipos de
  /// sucursal» no es una pestaña, el portón no se enteraba de que se había entrado ahí:
  /// la pantalla tenía que **avisar hacia arriba** con un callback para que el rastro no
  /// mintiera. La vía estaba bien escrita —un solo método la tocaba— y lo que estaba mal
  /// era que existiera: quien sabe dónde estás es la dirección.
  final bool viendoTipos;

  /// El id de la sucursal cuyo expediente se está mirando, **de la dirección**, o nulo.
  ///
  /// **SÓLO EL ID.** El nombre no va en la URL —sería estado disfrazado de dirección, y
  /// quedaría viejo en cuanto alguien renombrara la sucursal—: lo aporta
  /// [alConocerElNombre] cuando esta pantalla ya cargó la fila.
  final String? expedienteDe;

  /// Pide abrir o cerrar el catálogo de tipos. **La pantalla no navega: pide.**
  ///
  /// Quien convierte esto en una dirección es el portón, que es el único que conoce la
  /// ruta del apartado. Así esta pantalla sigue sin saber que existe un router.
  final ValueChanged<bool> alVerTipos;

  /// Pide abrir el expediente de una sucursal, o volver a la lista con nulo.
  final ValueChanged<Sucursal?> alVerExpediente;

  /// Dónde se registra que hay trabajo sin guardar (D-56).
  ///
  /// **Esta pantalla no lo usa: lo pasa.** El formulario que puede tener algo que perder
  /// es el expediente de una sucursal, que se abre aquí dentro, y el guardia es uno por
  /// sesión — así que viaja de arriba en lugar de inventarse uno por pantalla.
  final GuardiaDeSalida guardia;

  /// Avisa de **cómo se llama** la sucursal abierta, para el rastro.
  ///
  /// ⚠️ **NO ES LA VÍA QUE D-39 QUITÓ, y la diferencia importa.** Aquella publicaba
  /// *dónde estabas* —navegación—, y mentía si alguien olvidaba mandarla. Ésta publica
  /// *cómo se llama una fila que ya está cargada* —un dato—: si no llega, el rastro
  /// sigue siendo correcto, dice «Expediente», sólo menos específico. No hay nada que
  /// pueda quedarse pegado.
  final void Function(String id, String nombre)? alConocerElNombre;

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

  /// Pide entrar o salir del catálogo de tipos.
  ///
  /// ✅ **ERA UN `setState` Y AHORA ES UNA NAVEGACIÓN** (D-39). Sigue siendo un solo
  /// método a propósito, por la misma razón de antes: con tres sitios pidiéndolo por su
  /// cuenta, uno acabaría haciéndolo de otra forma.
  void _verTipos(bool viendo) => widget.alVerTipos(viendo);

  /// Pide abrir el expediente de una sucursal, o volver a la lista.
  ///
  /// **Y DE PASO DICE CÓMO SE LLAMA**, que es lo que el rastro necesita para decir
  /// «Expediente de Matriz» en lugar de sólo «Expediente». El nombre sale de la fila
  /// que esta pantalla ya tiene cargada, **nunca de la URL**.
  void _verExpediente(Sucursal? sucursal) {
    if (sucursal != null) {
      widget.alConocerElNombre?.call(sucursal.id, sucursal.nombre);
    }

    widget.alVerExpediente(sucursal);
  }

  /// La sucursal del expediente abierto, buscada en la lista por el id de la dirección.
  ///
  /// **Nula mientras la lista carga**, y eso es correcto: el expediente necesita la fila
  /// entera —nombre, tipo, domicilio— y la dirección sólo trae el id. Mientras llega se
  /// ve la lista con su indicador de carga, y el rastro ya dice «Expediente» porque sale
  /// de la dirección.
  ///
  /// **Nula también si el id no está en la lista**, y entonces [_cargar] devuelve a la
  /// lista: pasa con un enlace viejo —la sucursal se eliminó— o con un id escrito a mano.
  Sucursal? get _expedienteDe => widget.expedienteDe == null
      ? null
      : _sucursales?.where((s) => s.id == widget.expedienteDe).firstOrNull;

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

    // UNA DIRECCIÓN QUE NOMBRA UNA SUCURSAL QUE NO ESTÁ DEVUELVE A LA LISTA, y hay que
    // hacerlo aquí porque hasta ahora no se sabía: con la lista a medio traer, un id
    // desconocido y un id que todavía no ha llegado se ven igual.
    //
    // Sin esto, un enlace viejo —la sucursal se eliminó— dejaría la lista en pantalla
    // con el rastro diciendo «Expediente» y la dirección prometiendo algo que no está.
    final pedido = widget.expedienteDe;
    final lista = _sucursales;

    if (pedido != null && lista != null && !lista.any((s) => s.id == pedido)) {
      widget.alVerExpediente(null);
    }
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

    final expediente = _expedienteDe;

    if (expediente != null) {
      return ExpedienteSucursalWebScreen(
        repositorio: widget.repositorioDeExpedientes,
        // LOS DOS REPOSITORIOS: el expediente guarda nombre, tipo, domicilio y
        // horario; cerrar, reabrir, desactivar y eliminar son rutas de la estructura.
        repositorioDeSucursales: widget.repositorio,
        empresaId: widget.empresaId,
        sucursal: expediente,
        // LOS TIPOS, YA FILTRADOS: los activos más el que esta sucursal tenga, aunque
        // esté retirado. Sin esa excepción, guardar el domicilio le quitaría su tipo.
        tipos: [
          for (final t in _tipos ?? const <TipoDeSucursal>[])
            if (t.activo || t.id == expediente.tipoId) t,
        ],
        capacidades: widget.capacidades,
        esMaestro: widget.esMaestro,
        // EL DEL EXPEDIENTE, que es otra familia de permisos.
        puedeEditarExpedientes: widget.puedeEditarExpedientes,
        // D-56 · DONDE EL EXPEDIENTE REGISTRA QUE TIENE ALGO QUE PERDER.
        guardia: widget.guardia,
        // ⚠️ AQUÍ DECÍA «AL VOLVER NO SE RECARGA LA LISTA», con su razón: «el
        // expediente no cambia el nombre, el código, el tipo ni el estado de la
        // sucursal». Dejó de ser verdad el 21 de octubre de 2026, cuando el nombre, el
        // tipo y las tres operaciones de estado se mudaron al expediente. Ahora se
        // recarga, y lo que cambie se refleja en el acto por [alCambiar] sin esperar a
        // volver.
        onVolver: () {
          _verExpediente(null);
          _cargar();
        },
        alCambiar: (sucursal) {
          if (!mounted) return;

          setState(() {
            _sucursales = [
              for (final s in _sucursales ?? const <Sucursal>[])
                if (s.id == sucursal.id) sucursal else s,
            ];
          });

          // Y EL RASTRO, QUE LLEVA EL NOMBRE: sin esto diría el viejo.
          //
          // ⚠️ **AQUÍ NO SE NAVEGA, y antes esto llamaba a `_verExpediente`.** La
          // dirección no cambió —es la misma sucursal, con otro nombre—, y un `go` a la
          // dirección en la que ya estás deja **una entrada duplicada en el historial**:
          // «atrás» no haría nada visible la primera vez.
          widget.alConocerElNombre?.call(sucursal.id, sucursal.nombre);
        },
      );
    }

    if (widget.viendoTipos) {
      return TiposDeSucursalWebScreen(
        repositorio: widget.repositorio,
        empresaId: widget.empresaId,
        esMaestro: widget.esMaestro,
        // D-56 · SIGUE BAJANDO: el panel del catálogo también tiene campos.
        guardia: widget.guardia,
        // LAS MISMAS CAPACIDADES: el catálogo de tipos no tiene permisos propios.
        capacidades: widget.capacidades,
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
                // «NUEVA SUCURSAL» ES CREAR; «TIPOS DE SUCURSAL» ES UNA LISTA que
                // se consulta y que por dentro se administra con los mismos cuatro
                // permisos, así que basta `puedeVer` para entrar.
                ofrecerNueva: widget.capacidades.puedeCrear,
                ofrecerTipos: widget.capacidades.puedeVer,
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
        // EL VACÍO TAMBIÉN OFRECE UN ALTA: misma regla que el encabezado.
        primaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Nueva sucursal',
                icon: Icons.add,
                onPressed: () => _abrirPanel(),
              )
            : null,
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
        // ⚠️ LA FILA ABRE EL EXPEDIENTE, y antes abría un panel lateral con el nombre,
        // el tipo y el estado. Aquí decía que el expediente tenía «su propio botón» y
        // que mover el toque de la fila cambiaría la acción común de sitio — pero eran
        // DOS sitios para editar una sucursal, con dos peticiones para una sola
        // intención. **Ahora hay un solo lugar por sucursal**, y es el expediente.
        onTocar: () => _verExpediente(_visibles[i]),
      ),
    );
  }

  /// Abre el panel del **alta**, y sólo del alta.
  ///
  /// ⚠️ **ESTE PANEL TAMBIÉN EDITABA, y dejó de hacerlo el 21 de octubre de 2026.**
  /// Editar una sucursal vive ahora entero en su expediente: un solo lugar, una sola
  /// transacción. El panel sobrevive porque una sucursal que todavía no existe **no
  /// tiene expediente que abrir** — no es una excepción a la regla, es su límite.
  Future<void> _abrirPanel() async {
    final tipos = [
      for (final t in _tipos ?? const <TipoDeSucursal>[])
        if (t.activo) t,
    ];

    // SIN UN TIPO NO SE PUEDE DAR DE ALTA, y el servidor lo exige. En vez de apagar
    // el botón —que dejaría al usuario sin saber por qué— se abre el camino para
    // resolverlo: es una precondición de DATOS que el cliente conoce, no una
    // suposición sobre la autorización.
    if (tipos.isEmpty) {
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
      builder: (_) => _PanelDeNuevaSucursal(
        tipos: tipos,
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
        // SÓLO `puedeCrear`: aquí ya no hay nada que modificar ni que archivar.
        puedeCrear: widget.capacidades.puedeCrear,
        // SUGERIDO COMO EN EL ESCRITORIO, y nada si la lista no se pudo leer: un
        // SUC-0001 inventado chocaría con el que ya existe.
        codigoSugerido: _sucursales == null
            ? null
            : siguienteCodigo(
                PrefijoDeCodigo.sucursal,
                _sucursales!.map((s) => s.codigo),
              ),
        guardia: widget.guardia,
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
    required this.ofrecerNueva,
    required this.ofrecerTipos,
  });

  final int total;
  final int inactivas;
  final VoidCallback onTipos;
  final VoidCallback? onNueva;

  /// Si el botón de alta **se pinta**. Distinto de pasarlo deshabilitado, que lo
  /// dejaría visible: lo que esta persona no puede hacer no se le enseña.
  final bool ofrecerNueva;

  /// Si el catálogo de tipos se ofrece. Es una LISTA, así que basta poder consultar;
  /// dentro, cada acción vuelve a pedir la suya.
  final bool ofrecerTipos;

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
        if (ofrecerTipos)
          RisegButton(
            label: 'Tipos de sucursal',
            variant: RisegButtonVariant.secondary,
            icon: Icons.category_outlined,
            onPressed: onTipos,
          ),
        if (ofrecerTipos && ofrecerNueva) const SizedBox(width: AppSpacing.sm),
        if (ofrecerNueva)
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
  const _Fila({
    required this.sucursal,
    required this.tipo,
    required this.onTocar,
  });

  final Sucursal sucursal;
  final String? tipo;

  /// Abre el expediente de la sucursal, **que es todo lo que tiene**: nombre, tipo,
  /// domicilio, horario y sus tres operaciones de estado.
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
            // SIN BOTÓN DE EXPEDIENTE: lo abre la fila. Dejarlo sería ofrecer dos
            // caminos al mismo sitio, y uno de los dos parecería llevar a otra parte.
            Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// El panel del alta — y SÓLO del alta
// ===========================================================================

/// Dar de alta una sucursal: código, nombre y tipo.
///
/// ⚠️ **ESTE PANEL TAMBIÉN EDITABA, y era el problema.** Tenía el nombre, el tipo, el
/// interruptor de activa, los botones de cerrar y reabrir y el de eliminar; el
/// domicilio y el horario vivían en otra pantalla. Así que corregir el nombre y la
/// dirección de una sucursal eran **dos peticiones para una sola intención**, y la
/// segunda podía fallar dejando la primera aplicada.
///
/// Desde el 21 de octubre de 2026 editar una sucursal vive entero en su expediente,
/// que es lo que abre el toque de la fila. Lo que queda aquí es el alta, y no es una
/// excepción a «un solo lugar por sucursal»: **una sucursal que todavía no existe no
/// tiene expediente que abrir.**
///
/// Por eso aquí no hay estado ni eliminar: una sucursal nueva nace activa y operando,
/// y lo que no existe no se cierra ni se borra.
class _PanelDeNuevaSucursal extends StatefulWidget {
  const _PanelDeNuevaSucursal({
    required this.tipos,
    required this.empresaId,
    required this.repositorio,
    required this.puedeCrear,
    required this.codigoSugerido,
    required this.guardia,
  });

  /// D-56 · dónde declara que tiene algo que perder.
  final GuardiaDeSalida guardia;

  /// **Sólo los activos.** Al dar de alta no hay ningún tipo propio que conservar, que
  /// era la razón de la excepción del expediente.
  final List<TipoDeSucursal> tipos;

  final String empresaId;
  final SucursalesRepositorioHttp repositorio;

  /// `organizacion.crear`. **Sin él el panel no se abre**, así que esto no apaga
  /// campos: lo lee el botón de guardar, por si alguien pierde el permiso con el panel
  /// abierto.
  final bool puedeCrear;

  /// El código que se propone, o `null` si la lista no se pudo leer: un SUC-0001
  /// inventado chocaría con el que ya existe.
  final String? codigoSugerido;

  @override
  State<_PanelDeNuevaSucursal> createState() => _PanelDeNuevaSucursalState();
}

class _PanelDeNuevaSucursalState extends State<_PanelDeNuevaSucursal>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDeNuevaSucursal>,
        // D-56 · UNA HOJA MODAL NO VIVE EN EL HISTORIAL, así que un cambio de dirección
        // no se la lleva: sin esto se quedaría encima de la pantalla nueva.
        SeCierraAlCambiarLaDireccion<_PanelDeNuevaSucursal> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Con qué se compara para saber si hay algo escrito.
  ///
  /// ⚠️ **LA BASE NO ES «VACÍO»: el panel llega con el código sugerido y, con un solo
  /// tipo, con el tipo ya elegido.** Comparar contra vacío haría que abrir el alta y
  /// cerrarla preguntara por lo que el panel puso solo.
  ///
  /// Son `late final` y perezosos a propósito: el registro lo pone el mixin en el
  /// `super.initState()`, antes de que este estado haya acabado de armarse.
  late final String _codigoInicial = widget.codigoSugerido ?? '';
  late final String? _tipoInicial =
      widget.tipos.length == 1 ? widget.tipos.single.id : null;

  @override
  bool get hayCambiosSinGuardar =>
      _codigo.text.trim() != _codigoInicial.trim() ||
      _nombre.text.trim().isNotEmpty ||
      _tipoId != _tipoInicial;

  /// **Aquí no hay nombre guardado que decir**: la sucursal todavía no existe, y el del
  /// campo sería el de algo que nadie ha creado.
  @override
  String get queSePierde => 'la sucursal que estás dando de alta';

  final _codigo = TextEditingController();
  final _nombre = TextEditingController();

  String? _tipoId;
  bool _guardando = false;
  String? _errorDeCodigo;
  String? _errorDeNombre;
  String? _errorDeTipo;

  @override
  void initState() {
    super.initState();

    // AL CREAR, EL CÓDIGO LLEGA SUGERIDO Y SIGUE SIENDO EDITABLE.
    _codigo.text = widget.codigoSugerido ?? '';

    if (widget.tipos.length == 1) {
      // CON UN SOLO TIPO SE PRESELECCIONA, porque elegir entre uno no es una
      // decisión. Con dos o más no se adivina.
      _tipoId = widget.tipos.single.id;
    }
  }

  @override
  void dispose() {
    // Liberar los controllers no es opcional: en este proyecto ya costó una vez.
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
                const Text('Nueva sucursal', style: AppTypography.heading2),
                const SizedBox(height: AppSpacing.lg),

                RisegTextField(
                  label: 'Código',
                  controller: _codigo,
                  enabled: !_guardando,
                  errorText: _errorDeCodigo,
                  // LA MISMA AYUDA QUE ÁREAS Y PUESTOS, de una sola función.
                  helperText: ayudaDelCodigo(
                    esNuevo: true,
                    haySugerencia: widget.codigoSugerido != null,
                    queEs: 'a la sucursal',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                RisegTextField(
                  label: 'Nombre',
                  controller: _nombre,
                  enabled: !_guardando,
                  errorText: _errorDeNombre,
                  helperText: 'Como Centro o Matriz.',
                ),
                const SizedBox(height: AppSpacing.md),

                RisegSelect<String>(
                  label: 'Tipo de sucursal',
                  value: _tipoId,
                  enabled: !_guardando,
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

                Text(
                  // SE DICE DÓNDE ESTÁ EL RESTO. Quien da de alta una sucursal espera
                  // poder ponerle su dirección, y sin esto buscaría un campo que no
                  // está en esta pantalla.
                  'El domicilio y el horario se capturan en el expediente de la '
                  'sucursal, una vez dada de alta. Nace activa y operando.',
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),

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
                      onPressed: _guardando || !widget.puedeCrear
                          ? null
                          : _guardar,
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
      _errorDeCodigo = codigo.isEmpty ? 'Escribe un código.' : null;
      _errorDeNombre = nombre.isEmpty ? 'Escribe un nombre.' : null;
      // EL TIPO ES OBLIGATORIO AL CREAR, que es lo que el servidor exige.
      _errorDeTipo = _tipoId == null ? 'Elige un tipo.' : null;
    });

    if (_errorDeCodigo != null || _errorDeNombre != null || _errorDeTipo != null) {
      return;
    }

    setState(() => _guardando = true);

    // UN REINTENTO SI EL CÓDIGO SUGERIDO CHOCA. Mismo motivo que en Áreas: la
    // sugerencia la calcula el cliente, así que dos personas creando a la vez reciben
    // el mismo número.
    final resultado = await crearConReintentoDeCodigo(
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
    );

    if (!mounted) return;

    resultado.when(
      ok: (_) {
        RisegFeedback.showSuccess(context, 'Sucursal creada.');
        Navigator.of(context).pop(true);
      },
      failure: (f) => setState(() {
        _guardando = false;

        // SÓLO EL CHOQUE DE CÓDIGO VA AL CAMPO DEL CÓDIGO: es el único error que la
        // persona arregla reescribiendo algo de este formulario.
        if (f case ApiHttpFailure(codigo: 'code_conflict')) {
          _errorDeCodigo = f.message;
        } else {
          mostrarRechazoDelServidor(context, f);
        }
      }),
    );
  }
}
