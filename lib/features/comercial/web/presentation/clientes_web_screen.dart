import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL, no del catálogo de permisos. Esta feature no puede
// importar `PermisoCompany` —hay un guardia que lo impide— y no le hace falta: pregunta
// `puedeCrear`, nunca por un literal.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../app/shell/se_cierra_al_cambiar_la_direccion.dart';
import '../../../../core/archivos/elegir_logotipo.dart';
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/cache_de_logotipos.dart';
import '../datos/clientes_repositorio_http.dart';
import '../modelos/cliente.dart';

/// La división comercial primaria: **relación vigente o relación terminada**.
///
/// Es un chip y no un filtro más porque el escritorio lo tiene así y por una razón que
/// se sostiene: separa la cartera con la que se trabaja de la que ya es historia, antes
/// de cualquier filtro más fino.
///
/// En el escritorio «Finalizados» eran Terminado **o Descartado**; sin Descartado es un
/// solo estatus, y quién pertenece a cada grupo lo contesta
/// [EstatusDeCliente.esFinalizada] y no una lista escrita aquí.
enum GrupoComercial {
  vigentes('Vigentes'),
  finalizados('Finalizados');

  const GrupoComercial(this.nombre);

  final String nombre;
}

/// El filtro de servicios, de tres estados.
///
/// «Con servicios» es **al menos uno activo**, igual que el escritorio: un cliente cuyos
/// servicios están todos suspendidos no está siendo atendido.
enum FiltroDeServicios {
  todos('Todos', null),
  conServicios('Con servicios', true),
  sinServicios('Sin servicios', false);

  const FiltroDeServicios(this.nombre, this.paraElServidor);

  final String nombre;

  /// Lo que viaja en `withServices`. **Nulo es «no filtres por esto»**, no «filtra por
  /// el valor vacío».
  final bool? paraElServidor;
}

/// **Clientes**, en la web. La cartera comercial de la empresa.
///
/// ## Los filtros los aplica el SERVIDOR, con una excepción nombrada
///
/// El escritorio filtra en memoria porque tiene la cartera entera en SQLite; aquí
/// Clientes **no tiene paginación** —deuda conocida del backend— así que filtrar en la
/// pantalla obligaría a traer la cartera completa para enseñar tres filas. El buscador
/// —que mira folio, nombre y observaciones—, el estatus y el filtro de servicios van en
/// la petición.
///
/// ⚠️ **LA EXCEPCIÓN ES EL CHIP «VIGENTES», y es del contrato del servidor:** `status`
/// admite **un** estatus o ninguno, y «Vigentes» son dos —activo y suspendido—. Así que
/// con el chip en Vigentes y el estatus en «Todos» se pide sin filtrar y **la pantalla
/// esconde los finalizados**. Es lo único que se filtra aquí, y lo que trae de más son
/// exactamente las filas terminadas; en cuanto se elige un estatus concreto, vuelve a
/// filtrar el servidor.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo.</b> El completo
/// exporta un componente que lee del disco con `dart:io` y rompería la build web sin
/// que nada en este archivo parezca estar mal. Una prueba de arquitectura lo exige.
class ClientesWebScreen extends StatefulWidget {
  const ClientesWebScreen({
    required this.repositorio,
    required this.empresaId,
    required this.capacidades,
    required this.guardia,
    required this.alAbrirExpediente,
    this.elegirUnLogotipo = elegirLogotipo,
    super.key,
  });

  final ClientesRepositorioHttp repositorio;
  final String empresaId;

  /// Qué puede hacer aquí quien mira.
  ///
  /// ⚠️ **EN CLIENTES LAS TRES ESCRITURAS SON EL MISMO PERMISO** —
  /// `clients_services.manage`— y el objeto se construye así en el shell. No se colapsan
  /// a un solo `bool` a propósito: el día que el catálogo separe «archivar» de
  /// «modificar», el sitio que cambia es la fábrica y no cada botón de esta pantalla.
  ///
  /// **OFRECERLO NO ES AUTORIZARLO.** El servidor vuelve a decidir en cada petición;
  /// esto evita enseñar una puerta que va a cerrarse en la cara.
  final CapacidadesDeModulo capacidades;

  /// Dónde se registra que hay trabajo sin guardar (D-56).
  ///
  /// **Esta pantalla no lo usa: lo pasa** a su panel de alta, que es el que tiene
  /// campos. La regla es permanente: toda pantalla con «Guardar» se registra.
  final GuardiaDeSalida guardia;

  /// Abre el expediente de un cliente.
  ///
  /// **La pantalla pide, no navega:** quien conoce la ruta del apartado es el portón, y
  /// por eso recibe el id y no una dirección. **En la URL va sólo el id** —el nombre
  /// quedaría viejo en cuanto alguien renombrara al cliente—.
  final void Function(String clienteId) alAbrirExpediente;

  /// Cómo se elige el logotipo. **Por omisión, el selector de verdad.**
  ///
  /// Se recibe en vez de llamarse directo por lo que explica [SelectorDeLogotipo]: el
  /// diálogo del sistema no cabe en una prueba de widgets, y lo que hay que fijar es qué
  /// pasa **después** de elegir.
  final SelectorDeLogotipo elegirUnLogotipo;

  @override
  State<ClientesWebScreen> createState() => _ClientesWebScreenState();
}

class _ClientesWebScreenState extends State<ClientesWebScreen> {
  List<ClienteEnLista>? _clientes;
  Failure? _fallo;
  bool _cargando = true;

  /// Dónde se quedó la paginación. Nulo significa **que no hay más** (D-67).
  String? _cursor;
  bool _cargandoMas = false;

  /// El fallo de **«Cargar más»**, que no es el de la primera página: con filas ya
  /// pintadas, una página que falla no debe borrarlas y dejar la pantalla de error. Se
  /// avisa debajo de la tabla y lo que había se queda.
  Failure? _falloDeLaPagina;

  /// La caché de logotipos, compartida por todas las filas (**CP-20**). Se crea una vez y
  /// **no se tira al recargar**: cambiar un filtro no cambia los logotipos.
  late final CacheDeLogotipos _logotipos = CacheDeLogotipos(
    repositorio: widget.repositorio,
    empresaId: widget.empresaId,
  );

  /// El latido del desplazamiento.
  ///
  /// Las filas se suscriben a esto para volver a preguntarse **si están a la vista**. Va
  /// por un `ValueNotifier` y no por un `setState` de la pantalla porque un `setState`
  /// aquí reconstruiría la tabla entera en cada píxel de scroll; así sólo se reevalúan los
  /// avatares, que es lo único que depende de la posición.
  final ValueNotifier<int> _latidoDelScroll = ValueNotifier<int>(0);

  GrupoComercial _grupo = GrupoComercial.vigentes;
  EstatusDeCliente? _estatus;
  FiltroDeServicios _servicios = FiltroDeServicios.todos;

  final _buscador = TextEditingController();

  /// ⚠️ **EL BUSCADOR VA AL SERVIDOR, ASÍ QUE NO PUEDE PEDIR POR TECLA.** Escribir
  /// «Sportium» serían ocho peticiones, y las respuestas pueden llegar desordenadas: la
  /// de «Spo» después de la de «Sportium» dejaría la lista enseñando el resultado de una
  /// búsqueda que ya nadie está haciendo.
  ///
  /// Con el temporizador se pide una vez, cuando la persona deja de escribir. Y
  /// [_generacion] cierra el resto del hueco: si dos peticiones se cruzan de todas
  /// formas, sólo la última manda.
  Timer? _esperaDelBuscador;

  /// Cuál es la petición vigente. **Una respuesta de una generación vieja se descarta**,
  /// en vez de pintarse encima de la nueva.
  int _generacion = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    // LIBERAR EL CONTROLLER NO ES OPCIONAL, y en este proyecto ya costó una vez.
    // `Future.delayed(300ms)` para «esperar la animación» está PROHIBIDO.
    _buscador.dispose();
    // Y EL TEMPORIZADOR TAMPOCO: uno vivo dispararía un `setState` sobre un `State`
    // desmontado medio segundo después de salir de la pantalla.
    _esperaDelBuscador?.cancel();
    // EL NOTIFICADOR ES UN `ChangeNotifier` y se libera por la misma razón que el
    // controller: sus oyentes son las filas, y una fila desmontada que siga suscrita es
    // una fuga que nadie ve hasta que la pantalla se abre cien veces.
    _latidoDelScroll.dispose();
    super.dispose();
  }

  // =========================================================================
  // Pedir
  // =========================================================================

  /// Pide **la primera página** y tira lo que hubiera.
  ///
  /// ⚠️ **EL CURSOR SE DESCARTA AQUÍ, y es lo que hace correcta la paginación con
  /// filtros.** Un cursor es la posición *dentro de un resultado concreto*: seguir usando
  /// el de la búsqueda anterior después de cambiar el texto saltaría filas sin avisar.
  /// Todo lo que llama a `_cargar` —filtros, chips, buscador, «Intentar de nuevo»—
  /// empieza de cero por construcción, porque el cursor no se pasa.
  Future<void> _cargar() async {
    final mia = ++_generacion;

    setState(() {
      _cargando = true;
      _fallo = null;
      _falloDeLaPagina = null;
    });

    final resultado = await widget.repositorio.listar(
      widget.empresaId,
      estatus: _estatusParaElServidor,
      texto: _buscador.text,
      conServicios: _servicios.paraElServidor,
    );

    if (!mounted || mia != _generacion) return;

    resultado.when(
      ok: (pagina) => setState(() {
        _clientes = pagina.clientes;
        _cursor = pagina.cursorSiguiente;
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  /// Pide **la siguiente página** y la añade al final.
  ///
  /// Comparte [_generacion] con `_cargar` a propósito: si alguien cambia un filtro
  /// mientras esta petición viaja, su respuesta **se descarta** en lugar de pegar las
  /// filas de la búsqueda vieja debajo de la nueva.
  Future<void> _cargarMas() async {
    final cursor = _cursor;
    if (cursor == null || _cargandoMas) return;

    final mia = _generacion;

    setState(() {
      _cargandoMas = true;
      _falloDeLaPagina = null;
    });

    final resultado = await widget.repositorio.listar(
      widget.empresaId,
      estatus: _estatusParaElServidor,
      texto: _buscador.text,
      conServicios: _servicios.paraElServidor,
      cursor: cursor,
    );

    if (!mounted || mia != _generacion) return;

    resultado.when(
      ok: (pagina) => setState(() {
        _clientes = [...?_clientes, ...pagina.clientes];
        _cursor = pagina.cursorSiguiente;
        _cargandoMas = false;
      }),
      // LO QUE YA ESTABA NO SE BORRA: una página que falla no convierte una lista con
      // filas en una pantalla de error. Se avisa debajo y el cursor se conserva, así que
      // «Cargar más» se puede volver a pulsar.
      failure: (f) => setState(() {
        _falloDeLaPagina = f;
        _cargandoMas = false;
      }),
    );
  }

  /// Qué estatus viaja en la petición.
  ///
  /// Con el chip en **Finalizados** y sin estatus elegido, viaja `terminated`: el grupo
  /// es exactamente un estatus, así que el servidor puede filtrarlo. Con el chip en
  /// **Vigentes** y sin estatus elegido no viaja ninguno, porque son dos — y ésa es la
  /// única exclusión que hace la pantalla.
  EstatusDeCliente? get _estatusParaElServidor =>
      _estatus ??
      (_grupo == GrupoComercial.finalizados ? EstatusDeCliente.terminado : null);

  void _buscar(String _) {
    _esperaDelBuscador?.cancel();
    _esperaDelBuscador = Timer(const Duration(milliseconds: 350), _cargar);
  }

  void _cambiarGrupo(GrupoComercial grupo) {
    if (grupo == _grupo) return;

    setState(() => _grupo = grupo);
    _cargar();
  }

  bool get _hayFiltros =>
      _buscador.text.trim().isNotEmpty ||
      _estatus != null ||
      _servicios != FiltroDeServicios.todos;

  void _limpiarFiltros() {
    _esperaDelBuscador?.cancel();

    setState(() {
      _buscador.clear();
      _estatus = null;
      _servicios = FiltroDeServicios.todos;
    });

    _cargar();
  }

  /// Las filas que se pintan.
  ///
  /// Lo único que se decide aquí es el chip, y sólo cuando el servidor no pudo: ver
  /// [_estatusParaElServidor].
  List<ClienteEnLista> get _visibles {
    final todos = _clientes ?? const <ClienteEnLista>[];

    if (_estatus != null) return todos;

    return todos.where((c) {
      final finalizada = c.cliente.estado?.esFinalizada ?? false;

      // UN ESTATUS DESCONOCIDO CUENTA COMO VIGENTE, no como finalizado: de los dos
      // errores posibles, enseñar una fila de más en Vigentes se ve y se corrige;
      // esconderla en los dos grupos la haría desaparecer de la pantalla.
      return (_grupo == GrupoComercial.finalizados) == finalizada;
    }).toList();
  }

  // =========================================================================
  // Pintar
  // =========================================================================

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
              RisegSectionHeader(
                title: 'Clientes',
                description: 'Cartera comercial de la empresa.',
                // SIN PERMISO NO HAY BOTÓN, y no es lo mismo que un botón apagado: lo
                // que esta persona no puede hacer no se le enseña.
                primaryAction: widget.capacidades.puedeCrear
                    ? RisegButton(
                        label: 'Nuevo cliente',
                        icon: Icons.add,
                        onPressed: _cargando ? null : _abrirPanelDeAlta,
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              _Chips(grupo: _grupo, alElegir: _cambiarGrupo),
              const SizedBox(height: AppSpacing.sm),
              _Filtros(
                buscador: _buscador,
                estatus: _estatus,
                servicios: _servicios,
                hayFiltros: _hayFiltros,
                onBuscar: _buscar,
                onEstatus: (v) {
                  setState(() => _estatus = v);
                  _cargar();
                },
                onServicios: (v) {
                  setState(() => _servicios = v);
                  _cargar();
                },
                onLimpiar: _limpiarFiltros,
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
    if (_fallo case final f? when _clientes == null) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los clientes',
        message: f.message,
        primaryAction: RisegButton(label: 'Intentar de nuevo', onPressed: _cargar),
      );
    }

    return Column(
      children: [
        // ⚠️ EL DETECTOR VA AQUÍ Y NO DENTRO DE LA TABLA, y es lo que permite cargar sólo
        // los logotipos visibles **sin tocar `RisegTableBase`**: las notificaciones de
        // desplazamiento BURBUJEAN hacia arriba, así que la pantalla las oye sin que el
        // componente compartido —que lo usan también Personal, Áreas y Sucursales— tenga
        // que exponer su `ScrollController`.
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              // SIN `setState`: sólo se despiertan los avatares, que son lo único que
              // depende de la posición. Un `setState` aquí repintaría la tabla entera en
              // cada píxel.
              _latidoDelScroll.value++;
              return false;
            },
            child: _tabla(),
          ),
        ),
        _PieDeLaPaginacion(
          hayMas: _cursor != null,
          cargando: _cargandoMas,
          fallo: _falloDeLaPagina,
          cuantas: _visibles.length,
          alCargarMas: _cargarMas,
        ),
      ],
    );
  }

  Widget _tabla() {
    final colors = context.colors;

    // ESTILO B · LA TABLA VA EN TARJETA Y CADA FILA LLEVA SU FRANJA. La franja no
    // sustituye a la insignia: la acompaña, porque un estado dicho sólo con color no lo
    // dice para quien no distingue esos colores.
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: AppRadius.lgRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: _tablaDesnuda(colors),
    );
  }

  Widget _tablaDesnuda(AppColorScheme colors) {
    return RisegTableBase<ClienteEnLista>(
      loading: _cargando,
      rows: _visibles,
      hoverColor: colors.accentSoftBg,
      rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
      franjaDeLaFila: (c) => switch (c.cliente.estado) {
        EstatusDeCliente.activo => colors.success,
        EstatusDeCliente.suspendido => colors.warning,
        EstatusDeCliente.terminado => colors.borderSubtle,
        null => colors.borderSubtle,
      },
      // CLIC EN LA FILA ABRE EL EXPEDIENTE, igual que en el escritorio. Hasta la entrega
      // anterior iba nulo a propósito —el expediente no existía, y `RisegTableBase`
      // documenta que sin `onRowTap` las filas no fingen ser botón—.
      onRowTap: (c) => widget.alAbrirExpediente(c.cliente.id),
      emptyState: _vacio(),
      columns: [
        RisegColumn<ClienteEnLista>(
          label: 'Nombre comercial',
          cellBuilder: _celdaDeNombre,
        ),
        RisegColumn<ClienteEnLista>(
          label: 'Servicios',
          width: 120,
          // SÓLO LOS ACTIVOS, igual que el escritorio. Y el cero se dice: aquí no es
          // ausencia de dato —el servidor contó— sino un cliente sin servicios activos.
          cellBuilder: (c) => Text(
            c.serviciosActivos == 1 ? '1 servicio' : '${c.serviciosActivos} servicios',
          ),
        ),
        RisegColumn<ClienteEnLista>(
          label: 'Ubicación',
          cellBuilder: (c) => Text(
            c.ubicacion ?? 'No registrada',
            style: c.ubicacion == null
                ? AppTypography.body.copyWith(color: colors.textMuted)
                : null,
          ),
        ),
        RisegColumn<ClienteEnLista>(
          label: 'Estatus',
          width: 140,
          cellBuilder: (c) => _InsigniaDeEstatus(cliente: c.cliente),
        ),
      ],
    );
  }

  /// La celda del nombre: **el logotipo o las iniciales, el nombre, y el folio debajo**.
  ///
  /// El logotipo entra con **CP-20**, y las iniciales **no se tiraron**: son el respaldo
  /// cuando el cliente no tiene logotipo **y mientras el suyo carga**, que es lo que hace
  /// que la fila nunca se vea vacía ni salte de tamaño.
  Widget _celdaDeNombre(ClienteEnLista c) {
    final colors = context.colors;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            width: 34,
            height: 34,
            child: _AvatarDeCliente(
              cliente: c,
              logotipos: _logotipos,
              latidoDelScroll: _latidoDelScroll,
              lado: 34,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.cliente.nombreComercial,
                style: AppTypography.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              // EL FOLIO, PEQUEÑO Y EN GRIS. Lo reconoce quien trabaja con el cliente,
              // pero no es lo que busca con la vista.
              Text(
                c.cliente.codigo,
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// El vacío, que son **dos mensajes distintos** y confundirlos haría pensar que no hay
  /// nada capturado.
  Widget _vacio() {
    // VACÍO DE VERDAD: no hay ni un cliente, y no hay ningún filtro puesto. El texto
    // explica qué es un cliente, porque quien abre esto por primera vez puede no saber
    // que la razón social no vive aquí.
    if (!_hayFiltros && _grupo == GrupoComercial.vigentes) {
      return RisegEmptyState(
        icon: Icons.handshake_outlined,
        title: 'Todavía no hay clientes',
        message:
            'Un cliente es la marca con la que trabajas —«Sportium»—. Su razón '
            'social y su RFC van en sus entidades fiscales, y puede tener varias.',
        primaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Nuevo cliente',
                icon: Icons.add,
                onPressed: _abrirPanelDeAlta,
              )
            : null,
      );
    }

    // VACÍO POR FILTRO. Y el chip cuenta como filtro: «Finalizados» sin ninguno es una
    // buena noticia, no una lista que falta.
    return RisegEmptyState(
      icon: Icons.search_off_outlined,
      title: _hayFiltros ? 'Ningún cliente coincide' : 'Ningún cliente finalizado',
      message: _hayFiltros
          ? 'Prueba con otro texto o quita los filtros. El buscador mira el folio, el '
                'nombre comercial y las observaciones.'
          : 'Ninguna relación comercial ha terminado.',
    );
  }

  // =========================================================================
  // El alta
  // =========================================================================

  Future<void> _abrirPanelDeAlta() async {
    final creado = await showModalBottomSheet<_ClienteDadoDeAlta>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PanelDeAltaDeCliente(
        empresaId: widget.empresaId,
        repositorio: widget.repositorio,
        guardia: widget.guardia,
        elegirUnLogotipo: widget.elegirUnLogotipo,
      ),
    );

    if (creado == null || !mounted) return;

    // SE DICE QUÉ SE CREÓ, CON SU FOLIO. El folio lo asignó el servidor y es la
    // referencia con la que esa persona va a hablar del cliente; «Cliente creado» a
    // secas la obligaría a buscarlo en la lista para enterarse.
    //
    // ⚠️ **UN SOLO MENSAJE, Y ESO COSTÓ UN ARREGLO.** Al principio el panel anunciaba el
    // fallo del logotipo y el listado anunciaba el alta: dos avisos seguidos, y el
    // segundo **tapaba al primero** —un `SnackBar` nuevo reemplaza al que está puesto—,
    // así que el único aviso que la persona llegaba a leer era el que decía que todo
    // había ido bien. Lo midió la prueba del logotipo que falla.
    final fallo = creado.falloDelLogotipo;
    final nombre = '${creado.cliente.codigo} · ${creado.cliente.nombreComercial}';

    if (fallo == null) {
      RisegFeedback.showSuccess(context, 'Se creó el cliente $nombre.');
    } else {
      RisegFeedback.showError(
        context,
        'Se creó el cliente $nombre, pero no se pudo subir el logotipo: $fallo',
      );
    }

    // Y SE ABRE SU EXPEDIENTE, igual que en el escritorio: quien acaba de dar de alta un
    // cliente va a capturar sus contactos y su domicilio, no a mirar la lista. El
    // listado se vuelve a pedir solo al volver, porque la dirección lo monta de nuevo.
    widget.alAbrirExpediente(creado.cliente.id);
  }
}

// ===========================================================================
// El avatar de la fila: logotipo si está a la vista, iniciales mientras no
// ===========================================================================

/// El logotipo del cliente en el listado, **pedido sólo cuando la fila está a la vista**
/// (CP-20, condiciones 2 y 3).
///
/// ## Por qué «a la vista» y no «al construirse»
///
/// `RisegTableBase` **no virtualiza**: construye las filas de la página de golpe. Si el
/// avatar pidiera su logotipo en `initState`, abrir la pestaña dispararía **una petición
/// por fila de la página** —cincuenta— aunque sólo se vean doce. Con «Cargar más» pulsado
/// varias veces serían cientos, que es exactamente lo que CP-20 prohíbe.
///
/// ## Cómo se sabe si está a la vista, sin tocar el componente compartido
///
/// Se compara el rectángulo de **este** widget con el del `Scrollable` que lo contiene.
/// Los dos salen de `RenderBox`, así que **no se supone ninguna altura de fila**: una fila
/// más alta o un diseño distinto siguen midiéndose bien. Y no hace falta que
/// `RisegTableBase` exponga su `ScrollController` —la pantalla oye las notificaciones de
/// desplazamiento, que burbujean— así que **el componente que comparten Personal, Áreas y
/// Sucursales no se toca**.
///
/// ## Lo que se pinta mientras tanto
///
/// Las **iniciales**, que son también lo que se pinta cuando el cliente no tiene logotipo.
/// Una sola respuesta para los dos casos: la fila no salta de tamaño ni parpadea en blanco.
class _AvatarDeCliente extends StatefulWidget {
  const _AvatarDeCliente({
    required this.cliente,
    required this.logotipos,
    required this.latidoDelScroll,
    required this.lado,
  });

  final ClienteEnLista cliente;
  final CacheDeLogotipos logotipos;
  final ValueNotifier<int> latidoDelScroll;
  final double lado;

  @override
  State<_AvatarDeCliente> createState() => _AvatarDeClienteState();
}

class _AvatarDeClienteState extends State<_AvatarDeCliente> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();

    widget.latidoDelScroll.addListener(_revisar);
    // LA PRIMERA REVISIÓN VA DESPUÉS DEL PRIMER FOTOGRAMA, no aquí: en `initState` este
    // widget todavía no tiene `RenderBox`, así que no hay geometría que comparar y la
    // pregunta «¿estoy a la vista?» no se puede contestar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisar());
  }

  @override
  void didUpdateWidget(_AvatarDeCliente anterior) {
    super.didUpdateWidget(anterior);

    if (anterior.latidoDelScroll != widget.latidoDelScroll) {
      anterior.latidoDelScroll.removeListener(_revisar);
      widget.latidoDelScroll.addListener(_revisar);
    }

    // ⚠️ LA FILA SE REUSA PARA OTRO CLIENTE al cambiar de página o de filtro —Flutter
    // reutiliza el elemento—, así que los bytes del anterior tienen que soltarse o se
    // pintaría el logotipo de otro cliente. Se compara por ARCHIVO: si el cliente
    // reemplazó su logotipo, el id cambia y esto también lo detecta.
    if (anterior.cliente.logotipoFileId != widget.cliente.logotipoFileId) {
      _bytes = widget.logotipos.enMemoria(widget.cliente.logotipoFileId ?? '');
      WidgetsBinding.instance.addPostFrameCallback((_) => _revisar());
    }
  }

  @override
  void dispose() {
    widget.latidoDelScroll.removeListener(_revisar);
    super.dispose();
  }

  void _revisar() {
    if (!mounted) return;

    final fileId = widget.cliente.logotipoFileId;
    if (fileId == null) return;

    final yaEnMemoria = widget.logotipos.enMemoria(fileId);
    if (yaEnMemoria != null) {
      if (_bytes == null) setState(() => _bytes = yaEnMemoria);
      return;
    }

    if (widget.logotipos.yaSePidio(fileId) || !_estaALaVista()) return;

    widget.logotipos
        .pedir(clienteId: widget.cliente.cliente.id, fileId: fileId)
        .then((bytes) {
          // `mounted` otra vez: entre pedir y responder, la persona pudo cambiar de
          // pantalla o de filtro. Y se comprueba que la fila siga siendo de ESTE archivo.
          if (!mounted || bytes == null) return;
          if (widget.cliente.logotipoFileId != fileId) return;

          setState(() => _bytes = bytes);
        });
  }

  /// Si el rectángulo de esta fila corta el del `Scrollable` que la contiene.
  ///
  /// Sin `Scrollable` alrededor —una prueba que monte la celda suelta, por ejemplo— se
  /// responde **que sí**: lo que no se puede medir no se esconde, porque el coste de
  /// enseñarlo de más es una petición y el de esconderlo es una fila sin logotipo.
  bool _estaALaVista() {
    final miCaja = context.findRenderObject();
    if (miCaja is! RenderBox || !miCaja.hasSize) return false;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return true;

    final cajaDelScroll = scrollable.context.findRenderObject();
    if (cajaDelScroll is! RenderBox || !cajaDelScroll.hasSize) return true;

    final mio = miCaja.localToGlobal(Offset.zero) & miCaja.size;
    final visible = cajaDelScroll.localToGlobal(Offset.zero) & cajaDelScroll.size;

    // MEDIA PANTALLA DE MARGEN ARRIBA Y ABAJO: la fila que viene ya tiene su logotipo
    // cuando asoma —en vez de aparecer con iniciales y cambiar a destiempo— y el margen
    // sigue siendo pequeño frente a la página. Con una pantalla entera de margen, una
    // página de cincuenta filas cabría casi completa en la banda y «sólo las visibles»
    // dejaría de significar nada.
    return mio.overlaps(visible.inflate(visible.height / 2));
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    if (bytes == null) {
      // EL COLOR SALE DEL ID Y NO DEL NOMBRE: renombrar un cliente no le cambia el color
      // que lo vuelve reconocible de un vistazo.
      return RisegIniciales(
        id: widget.cliente.cliente.id,
        nombre: widget.cliente.cliente.nombreComercial,
        lado: widget.lado,
      );
    }

    return Image.memory(
      bytes,
      width: widget.lado,
      height: widget.lado,
      fit: BoxFit.cover,
      // LA `key` SALE DEL ARCHIVO, y es la trampa 3 de IF-5: sin ella, `Image.memory` deja
      // la imagen vieja pegada al reemplazar el logotipo y parece que no se guardó.
      key: ValueKey<String?>(widget.cliente.logotipoFileId),
      // Si los bytes no se pueden decodificar, las iniciales. Un hueco roto en la fila
      // sería peor que el respaldo que ya existe.
      errorBuilder: (_, _, _) => RisegIniciales(
        id: widget.cliente.cliente.id,
        nombre: widget.cliente.cliente.nombreComercial,
        lado: widget.lado,
      ),
    );
  }
}

// ===========================================================================
// El pie de la paginación
// ===========================================================================

/// «Cargar más», la cuenta de lo que se ve, y el aviso si una página falla.
///
/// **No es scroll infinito, y es deliberado:** la tabla ya vive dentro de un
/// `SingleChildScrollView` horizontal, y encadenar dos gestos de desplazamiento en la
/// misma zona hace que el navegador decida cuál gana. Un botón explícito también deja
/// claro que **lo que se ve no es todo**, que es la pregunta que de verdad se hace quien
/// busca un cliente y no lo encuentra.
class _PieDeLaPaginacion extends StatelessWidget {
  const _PieDeLaPaginacion({
    required this.hayMas,
    required this.cargando,
    required this.fallo,
    required this.cuantas,
    required this.alCargarMas,
  });

  final bool hayMas;
  final bool cargando;
  final Failure? fallo;
  final int cuantas;
  final VoidCallback alCargarMas;

  @override
  Widget build(BuildContext context) {
    // SIN MÁS PÁGINAS Y SIN FALLO NO HAY PIE. Un «no hay más» permanente sería ruido en la
    // pantalla que más se mira, y con una sola página no aporta nada.
    if (!hayMas && fallo == null) return const SizedBox.shrink();

    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fallo case final f?)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                // LO QUE HABÍA SIGUE EN PANTALLA, y el aviso lo dice: si no, la persona
                // creería que la cartera se acaba donde se acabó la última página buena.
                'No se pudieron cargar más clientes: ${f.message}',
                style: AppTypography.caption.copyWith(color: colors.error),
              ),
            ),
          Row(
            children: [
              RisegButton(
                label: cargando ? 'Cargando…' : 'Cargar más',
                variant: RisegButtonVariant.secondary,
                onPressed: cargando || !hayMas ? null : alCargarMas,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                cuantas == 1 ? '1 cliente a la vista' : '$cuantas clientes a la vista',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Chips y filtros
// ===========================================================================

class _Chips extends StatelessWidget {
  const _Chips({required this.grupo, required this.alElegir});

  final GrupoComercial grupo;
  final ValueChanged<GrupoComercial> alElegir;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    children: [
      for (final g in GrupoComercial.values)
        ChoiceChip(
          label: Text(g.nombre),
          selected: grupo == g,
          // `onSelected` RECIBE EL BOOLEANO Y SE IGNORA: estos chips son exclusivos, así
          // que pulsar el que ya está puesto no lo apaga —no hay un tercer estado— y la
          // pantalla ya descarta el caso.
          onSelected: (_) => alElegir(g),
        ),
    ],
  );
}

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.buscador,
    required this.estatus,
    required this.servicios,
    required this.hayFiltros,
    required this.onBuscar,
    required this.onEstatus,
    required this.onServicios,
    required this.onLimpiar,
  });

  final TextEditingController buscador;
  final EstatusDeCliente? estatus;
  final FiltroDeServicios servicios;
  final bool hayFiltros;
  final ValueChanged<String> onBuscar;
  final ValueChanged<EstatusDeCliente?> onEstatus;
  final ValueChanged<FiltroDeServicios> onServicios;
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 260,
        child: RisegSearchField(
          hint: 'Folio, nombre u observaciones',
          controller: buscador,
          onChanged: onBuscar,
        ),
      ),
      SizedBox(
        width: 190,
        child: RisegSelect<EstatusDeCliente?>(
          label: 'Estatus',
          value: estatus,
          items: [
            const RisegSelectItem(value: null, label: 'Todos los estatus'),
            for (final e in EstatusDeCliente.values)
              RisegSelectItem(value: e, label: e.nombre),
          ],
          onChanged: onEstatus,
        ),
      ),
      SizedBox(
        width: 190,
        child: RisegSelect<FiltroDeServicios>(
          label: 'Servicios',
          value: servicios,
          items: [
            for (final f in FiltroDeServicios.values)
              RisegSelectItem(value: f, label: f.nombre),
          ],
          onChanged: (v) => onServicios(v ?? FiltroDeServicios.todos),
        ),
      ),
      RisegButton(
        label: 'Limpiar filtros',
        variant: RisegButtonVariant.ghost,
        // APAGADO CUANDO NO HAY NADA QUE LIMPIAR: un botón que no hace nada al pulsarlo
        // enseña que los botones no hacen nada.
        onPressed: hayFiltros ? onLimpiar : null,
      ),
    ],
  );
}

/// La insignia de estatus.
///
/// ⚠️ **UN ESTATUS QUE ESTA BUILD NO CONOCE SE ENSEÑA TAL CUAL**, con tono neutro, en vez
/// de caer en «Activo» por omisión. Un `_ => activo` pintaría como activo a un cliente
/// que no lo está, que es la clase de error que nadie va a notar.
class _InsigniaDeEstatus extends StatelessWidget {
  const _InsigniaDeEstatus({required this.cliente});

  final Cliente cliente;

  @override
  Widget build(BuildContext context) => switch (cliente.estado) {
    EstatusDeCliente.activo => const RisegStatusBadge(
      label: 'Activo',
      tone: RisegStatusTone.success,
      icon: Icons.check_circle_outline,
    ),
    EstatusDeCliente.suspendido => const RisegStatusBadge(
      label: 'Suspendido',
      tone: RisegStatusTone.warning,
      icon: Icons.pause_circle_outline,
    ),
    EstatusDeCliente.terminado => const RisegStatusBadge(
      label: 'Terminado',
      tone: RisegStatusTone.neutral,
      icon: Icons.do_not_disturb_on_outlined,
    ),
    null => RisegStatusBadge(
      label: cliente.estatus,
      tone: RisegStatusTone.neutral,
      icon: Icons.help_outline,
    ),
  };
}

// ===========================================================================
// El panel de alta
// ===========================================================================

/// Lo que el panel de alta devuelve: **el cliente creado y, si lo hubo, el fallo del
/// logotipo**.
///
/// ## Por qué el fallo sube y no se anuncia dentro del panel
///
/// Porque el alta son dos peticiones y el panel se cierra entre el aviso y el siguiente.
/// Anunciándolo dentro, el mensaje del listado —«se creó el cliente»— **tapaba al del
/// fallo**: un `SnackBar` nuevo reemplaza al que está puesto, así que lo único que la
/// persona llegaba a leer era que todo había ido bien.
///
/// Con el fallo aquí, quien tiene los dos datos compone **una sola frase** que dice las
/// dos cosas: el cliente está creado y lo que falta es el logotipo.
class _ClienteDadoDeAlta {
  const _ClienteDadoDeAlta(this.cliente, this.falloDelLogotipo);

  final Cliente cliente;

  /// El motivo por el que el logotipo no subió, **o nulo si subió o no se eligió
  /// ninguno**. No se distinguen los dos casos sin fallo porque la persona no puede
  /// hacer nada distinto en uno y en otro.
  final String? falloDelLogotipo;
}

/// Dar de alta un cliente.
///
/// ## Tres diferencias con el escritorio, las tres a favor
///
/// 1. **Pide la fecha de inicio.** El servidor la exige y se niega a rellenarla con la
///    fecha de captura —«convertiría una laguna en un hecho falso que después nadie
///    distingue del real»—. Se propone el día de hoy **del negocio** y se puede cambiar:
///    dar de alta a alguien que ya era cliente no empieza hoy.
/// 2. **El logotipo se sube después del alta**, igual que en el escritorio, y **si falla,
///    el cliente queda creado**. La pantalla lo dice en vez de callarlo: callarlo dejaría
///    a alguien creyendo que tiene que volver a crearlo.
/// 3. **El error dice qué pasó.** En el escritorio cualquier fallo —nombre vacío, falta
///    de permiso, error de red— sale como «No se pudo crear el Cliente. Intenta de
///    nuevo.». Aquí lo traduce un solo sitio.
///
/// **El alta no pide motivo**, y eso es del contrato: el motivo es para corregir, no para
/// crear.
class _PanelDeAltaDeCliente extends StatefulWidget {
  const _PanelDeAltaDeCliente({
    required this.empresaId,
    required this.repositorio,
    required this.guardia,
    required this.elegirUnLogotipo,
  });

  final String empresaId;
  final ClientesRepositorioHttp repositorio;
  final SelectorDeLogotipo elegirUnLogotipo;

  /// D-56 · dónde declara que tiene algo que perder.
  final GuardiaDeSalida guardia;

  @override
  State<_PanelDeAltaDeCliente> createState() => _PanelDeAltaDeClienteState();
}

class _PanelDeAltaDeClienteState extends State<_PanelDeAltaDeCliente>
    with
        DeclaraSuTrabajoSinGuardar<_PanelDeAltaDeCliente>,
        // D-56 · UNA HOJA MODAL NO VIVE EN EL HISTORIAL, así que un cambio de dirección
        // no se la lleva: sin esto se quedaría encima de la pantalla nueva.
        SeCierraAlCambiarLaDireccion<_PanelDeAltaDeCliente> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Con qué se compara para saber si hay algo escrito.
  ///
  /// ⚠️ **LA FECHA NACE PUESTA, ASÍ QUE LA BASE NO ES «VACÍO».** El panel abre con el día
  /// de hoy en el selector; comparar contra nulo haría que **abrir el alta y cerrarla
  /// preguntara** por una fecha que el panel escribió solo.
  ///
  /// Es `late final` y perezosa a propósito: el registro en el guardia lo pone el mixin
  /// en el `super.initState()`, antes de que este estado haya acabado de armarse.
  late final DiaDeNegocio _inicioInicial = DiaDeNegocio.hoy();

  @override
  bool get hayCambiosSinGuardar =>
      _nombre.text.trim().isNotEmpty ||
      _observaciones.text.trim().isNotEmpty ||
      _inicio != _inicioInicial ||
      _logotipo != null;

  /// **No nombra al cliente**, porque todavía no hay ninguno al que nombrar. El nombre
  /// del campo tampoco sirve: puede estar a medio escribir, y preguntar por «el cliente
  /// Sportiu» hablaría de algo que no existe.
  @override
  String get queSePierde => 'el cliente que estás dando de alta';

  final _nombre = TextEditingController();
  final _observaciones = TextEditingController();

  late DiaDeNegocio _inicio = _inicioInicial;

  LogotipoElegido? _logotipo;

  bool _guardando = false;

  /// **El error va EN EL CAMPO**, no en una barra roja arriba.
  String? _errorDeNombre;

  @override
  void dispose() {
    _nombre.dispose();
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
                const Text('Nuevo cliente', style: AppTypography.heading2),
                const SizedBox(height: AppSpacing.lg),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RisegTextField(
                          label: 'Nombre comercial',
                          controller: _nombre,
                          enabled: !_guardando,
                          errorText: _errorDeNombre,
                          autofocus: true,
                          // SE DICE QUÉ ES Y QUÉ NO ES, en una línea: quien llega del
                          // escritorio espera escribir aquí la razón social. El estilo B
                          // acorta la letra chica, no la quita donde dice algo que no se
                          // puede adivinar — y éste es uno de esos casos.
                          helperText: 'La marca, no la razón social.',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegDateField(
                          label: 'Inicio de la relación',
                          value: _inicio.comoFechaLocal,
                          enabled: !_guardando,
                          helperText: 'Si ya era cliente antes, cámbiala.',
                          // ⚠️ EL SELECTOR DEVUELVE LA MEDIANOCHE LOCAL DEL DÍA QUE SE
                          // TOCÓ, así que se leen sus campos y no se convierte de reloj:
                          // un `toUtc()` aquí movería el día al anterior.
                          onChanged: (v) => setState(
                            () => _inicio = DiaDeNegocio.deFechaLocal(v),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        RisegTextField(
                          label: 'Observaciones',
                          controller: _observaciones,
                          enabled: !_guardando,
                          maxLines: 3,
                          // EL BUSCADOR MIRA AQUÍ, y eso no se puede adivinar.
                          helperText: 'El buscador del listado también mira aquí.',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        _Logotipo(
                          elegido: _logotipo,
                          habilitado: !_guardando,
                          alElegir: _elegirLogotipo,
                          alQuitar: () => setState(() => _logotipo = null),
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
                            : () => Navigator.of(context).pop(),
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

  Future<void> _elegirLogotipo() async {
    final elegido = await widget.elegirUnLogotipo(
      context,
      donde: 'la ficha del cliente',
      // NO SE AVISA DE NINGÚN REEMPLAZO: el cliente todavía no existe, así que no hay
      // logotipo anterior que éste pueda pisar.
    );

    if (elegido == null || !mounted) return;

    setState(() => _logotipo = elegido);
  }

  /// Crea el cliente y, si se eligió, sube su logotipo.
  ///
  /// ⚠️ **SON DOS PETICIONES Y EL ORDEN IMPORTA:** el logotipo cuelga de un cliente que
  /// tiene que existir. Si la segunda falla, **la primera ya ocurrió** y el panel se
  /// cierra diciéndolo: el cliente está creado y lo que falta es el logotipo. Deshacer el
  /// alta sería peor —borraría un cliente que la persona quería— y callarlo la dejaría
  /// creyendo que tiene que volver a crearlo.
  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();

    setState(
      () => _errorDeNombre = nombre.isEmpty ? 'Falta el nombre comercial.' : null,
    );

    if (_errorDeNombre != null) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.crear(
      empresaId: widget.empresaId,
      nombreComercial: nombre,
      inicio: _inicio,
      // VACÍO SE MANDA COMO NULO, no como cadena vacía: el servidor guarda lo que
      // llega, y unas observaciones de cero caracteres no son unas observaciones.
      observaciones: _observaciones.text.trim().isEmpty
          ? null
          : _observaciones.text.trim(),
    );

    if (!mounted) return;

    await resultado.when(
      failure: (f) async {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
      ok: (cliente) async {
        final logotipo = _logotipo;
        String? falloDelLogotipo;

        if (logotipo != null) {
          final subido = await widget.repositorio.subirLogotipo(
            empresaId: widget.empresaId,
            clienteId: cliente.id,
            nombreDeArchivo: logotipo.nombre,
            bytes: logotipo.bytes,
          );

          if (!mounted) return;

          // EL FALLO SE LLEVA ARRIBA Y NO SE ANUNCIA AQUÍ: ver [_ClienteDadoDeAlta].
          // Y SE USA `MensajesHumanos` a través del mismo sitio que todo lo demás,
          // porque un 402 de suscripción restringida tiene que decir lo que dice
          // siempre.
          falloDelLogotipo = subido.when(
            ok: (_) => null,
            failure: MensajesHumanos.deMutacion,
          );
        }

        // SE DEVUELVE EL CLIENTE Y NO UN `true`: quien lo recibe nombra el folio que el
        // servidor acaba de asignar, y en la subetapa siguiente abre su expediente.
        Navigator.of(
          context,
        ).pop(_ClienteDadoDeAlta(cliente, falloDelLogotipo));
      },
    );
  }
}

/// El logotipo del alta: elegir, ver y quitar. **Opcional**.
class _Logotipo extends StatelessWidget {
  const _Logotipo({
    required this.elegido,
    required this.habilitado,
    required this.alElegir,
    required this.alQuitar,
  });

  final LogotipoElegido? elegido;
  final bool habilitado;
  final VoidCallback alElegir;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Logotipo', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Opcional. PNG o JPEG, hasta 5 MB. Se sube después de crear el cliente.',
          style: AppTypography.caption.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),

        if (elegido case final l?)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: colors.borderSubtle),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: _Miniatura(bytes: l.bytes),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l.nombre,
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Quitar el logotipo',
                icon: const Icon(Icons.delete_outline),
                onPressed: habilitado ? alQuitar : null,
              ),
            ],
          )
        else
          RisegButton(
            label: 'Elegir logotipo',
            icon: Icons.image_outlined,
            variant: RisegButtonVariant.secondary,
            size: RisegButtonSize.compact,
            onPressed: habilitado ? alElegir : null,
          ),
      ],
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Image.memory(
      bytes,
      fit: BoxFit.contain,
      // UN ARCHIVO QUE PASÓ LA FIRMA PERO NO SE PUEDE DECODIFICAR —un PNG truncado— no
      // revienta el panel: se dice con un ícono.
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    ),
  );
}
