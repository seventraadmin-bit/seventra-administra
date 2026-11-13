import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL, no del catálogo de permisos. Esta feature no puede
// importar `PermisoCompany` —hay un guardia que lo impide— y no le hace falta: pregunta
// `puedeCrear`, nunca por un literal.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../datos/cache_de_logotipos.dart';
import '../datos/clientes_repositorio_http.dart';
import '../datos/servicios_repositorio_http.dart';
import '../modelos/cliente.dart';
import '../modelos/servicio.dart';
import 'insignia_temporal.dart';

/// La división primaria del listado: **servicio vigente o servicio finalizado**.
///
/// Es un chip y no un filtro más porque el escritorio lo tiene así, y la razón se
/// sostiene: separa lo que se está prestando de lo que ya es historia, antes de cualquier
/// filtro más fino.
///
/// En el escritorio «Finalizados» es **sólo Terminado**, y aquí igual: quién pertenece a
/// cada grupo lo contesta [EstatusDeServicio.esFinalizado] y no una lista escrita aquí.
enum GrupoDeServicios {
  vigentes('Vigentes'),

  /// **Los que tienen término programado dentro de los próximos treinta días.**
  ///
  /// Aprobado por el dueño el 11 de noviembre de 2026, con la insignia «Termina el…». Es
  /// un grupo y no un filtro más porque responde la pregunta con la que alguien abre este
  /// listado un lunes: **qué hay que atender esta semana**.
  ///
  /// ⚠️ **LO FILTRA EL SERVIDOR**, y no es una preferencia: el listado pagina por cursor,
  /// así que acotarlo aquí dejaría «por terminar» reducido a *los que terminan pronto de
  /// los primeros cincuenta por nombre*, escondiendo el resto sin decirlo.
  porTerminar('Por terminar'),

  finalizados('Finalizados');

  const GrupoDeServicios(this.nombre);

  final String nombre;
}

/// El listado de servicios de la empresa — `/comercial/servicios`.
///
/// ## Lo que esta pantalla NO enseña, y no es un olvido
///
/// El escritorio tiene dos columnas más: **Personal** y **Esquema/Turno**. Las dos salen
/// de la cobertura operativa, que es **C5**, y hasta entonces **no existen como columnas**
/// — no salen en cero. Un cero diría que el servicio no tiene gente, que es una respuesta
/// falsa y además plausible, la peor clase.
class ServiciosWebScreen extends StatefulWidget {
  const ServiciosWebScreen({
    required this.repositorio,
    required this.clientes,
    required this.empresaId,
    required this.capacidades,
    required this.alAbrirExpediente,
    required this.alDarDeAlta,
    required this.alAbrirTipos,
    this.clienteInicial,
    this.grupoInicial,
    this.hoy = DiaDeNegocio.hoy,
    super.key,
  });

  /// **Con qué grupo arranca el listado**, o nulo para [GrupoDeServicios.vigentes].
  ///
  /// Llega de la dirección —`?grupo=porTerminar`— y es como entra quien pulsa «Ver todos»
  /// en la campana de avisos: **el listado tiene que enseñar lo mismo que la campana
  /// acaba de avisar**. Si llegara a «Vigentes», la fila avisada estaría ahí dentro pero
  /// revuelta con todas las demás, y el aviso no habría llevado a ninguna parte.
  ///
  /// ⚠️ **Se usa sólo para ARRANCAR**: después mandan los grupos de la pantalla.
  final GrupoDeServicios? grupoInicial;

  /// **Con qué cliente llega ya filtrado el listado**, o nulo.
  ///
  /// Llega de la dirección —`?cliente=…`— y es como entra quien pulsa «Ver en Servicios»
  /// desde el expediente de un cliente. ⚠️ **Se usa sólo para ARRANCAR**: después manda
  /// el selector, así que quitarlo a mano funciona como siempre.
  final String? clienteInicial;

  final ServiciosRepositorioHttp repositorio;

  /// El repositorio de **clientes**, y hace falta por dos cosas concretas:
  ///
  /// 1. **los bytes del logotipo**, que es del cliente y no del servicio, así que su ruta
  ///    es `/clients/{id}/logo/content` — por eso [CacheDeLogotipos] recibe este
  ///    repositorio y no el de servicios;
  /// 2. **las opciones del filtro de cliente**, que son los clientes que **ya tienen
  ///    servicios** (`?withServices=true`), igual que en el escritorio: un filtro que
  ///    ofrece la cartera entera para acotar cuatro servicios no acota nada.
  final ClientesRepositorioHttp clientes;

  final String empresaId;

  /// **Qué día es hoy, para la insignia «Termina el…».**
  ///
  /// ⚠️ **ENTRA POR EL CONSTRUCTOR Y NO SE LEE DEL RELOJ ADENTRO.** Con un
  /// `DiaDeNegocio.hoy()` dentro de la pantalla, una prueba que fije un término a
  /// cincuenta días diría «por terminar» cuando la suite se corriera cincuenta días
  /// después: la prueba se rompería sola, sin que nadie cambiara nada.
  ///
  /// Y es [DiaDeNegocio.hoy] —el día de México— y nunca `DateTime.now()`: a las 19:00
  /// locales un `now()` en UTC ya es mañana.
  final DiaDeNegocio Function() hoy;

  /// Qué puede hacer aquí quien mira. **Ofrecerlo no es autorizarlo**: el servidor vuelve
  /// a decidir en cada petición, y esto sólo evita enseñar una puerta que se va a cerrar
  /// en la cara.
  final CapacidadesDeModulo capacidades;

  /// Abre el expediente de un servicio. **La pantalla pide, no navega**: quien conoce la
  /// ruta del apartado es el portón.
  final void Function(String servicioId) alAbrirExpediente;

  /// Abre el alta.
  ///
  /// ⚠️ **ES UNA PÁGINA Y NO UN DIÁLOGO, al contrario que el alta de un cliente**, y es
  /// decisión del dueño: el alta de un cliente son tres campos, y la de un servicio son
  /// **quince** —cinco propios más los diez del domicilio operativo, que el servidor exige
  /// en la misma transacción—. A quince campos, un diálogo en un teléfono no se puede
  /// usar.
  final VoidCallback alDarDeAlta;

  /// Abre el catálogo de tipos de servicio.
  ///
  /// **No es una pestaña, y es una decisión**: los tipos son el catálogo que ordena los
  /// servicios, y no merecen el mismo peso en la navegación que la cosa que ordenan. Vive
  /// aquí detrás de un botón, igual que los tipos de sucursal dentro de Sucursales.
  final VoidCallback alAbrirTipos;

  @override
  State<ServiciosWebScreen> createState() => _ServiciosWebScreenState();
}

class _ServiciosWebScreenState extends State<ServiciosWebScreen> {
  List<ServicioEnLista>? _servicios;
  Failure? _fallo;
  bool _cargando = true;

  /// Dónde se quedó la paginación. Nulo significa **que no hay más**.
  String? _cursor;
  bool _cargandoMas = false;

  /// El fallo de **«Cargar más»**, que no es el de la primera página: con filas ya
  /// pintadas, una página que falla no debe borrarlas y dejar la pantalla de error.
  Failure? _falloDeLaPagina;

  /// La caché de logotipos, compartida por todas las filas.
  ///
  /// ⚠️ **Va por ARCHIVO y el archivo es del CLIENTE**, así que aquí da algo que en el
  /// listado de clientes no hacía falta: **dos servicios del mismo cliente comparten
  /// clave** y los bytes se piden **una sola vez** para los dos. Es gratis y es la razón
  /// por la que esta pantalla no necesitó ninguna caché propia.
  late final CacheDeLogotipos _logotipos = CacheDeLogotipos(
    repositorio: widget.clientes,
    empresaId: widget.empresaId,
  );

  /// El latido del desplazamiento. Las filas se suscriben para volver a preguntarse si
  /// están a la vista; va por `ValueNotifier` y no por `setState` porque un `setState`
  /// aquí repintaría la tabla entera en cada píxel de scroll.
  final ValueNotifier<int> _latidoDelScroll = ValueNotifier<int>(0);

  GrupoDeServicios _grupo = GrupoDeServicios.vigentes;
  EstatusDeServicio? _estatus;
  String? _clienteId;
  String? _tipoId;

  /// Las opciones de los dos selectores. **Nulo es «todavía no llegaron»** y vacío es
  /// «no hay ninguna», que son dos cosas distintas: con vacío el selector se apaga y lo
  /// dice, con nulo todavía no sabe qué ofrecer.
  List<ClienteEnLista>? _clientesConServicios;
  List<TipoDeServicio>? _tiposUsados;

  final _buscador = TextEditingController();

  /// ⚠️ **EL BUSCADOR VA AL SERVIDOR, ASÍ QUE NO PUEDE PEDIR POR TECLA.** Escribir
  /// «Sportium» serían ocho peticiones, y las respuestas pueden llegar desordenadas: la de
  /// «Spo» después de la de «Sportium» dejaría la lista enseñando una búsqueda que ya nadie
  /// está haciendo.
  Timer? _esperaDelBuscador;

  /// Cuál es la petición vigente. **Una respuesta de una generación vieja se descarta**,
  /// en vez de pintarse encima de la nueva.
  int _generacion = 0;

  @override
  void initState() {
    super.initState();

    // EL FILTRO CON EL QUE SE LLEGA, si la dirección traía uno. Se pone ANTES de cargar
    // para que la primera petición ya salga acotada: ponerlo después traería la lista
    // entera y la sustituiría, que se ve como un parpadeo y cuesta una página.
    _clienteId = widget.clienteInicial;
    _grupo = widget.grupoInicial ?? _grupo;

    _cargar();
    _cargarOpcionesDeFiltro();
  }

  @override
  void dispose() {
    // LIBERAR EL CONTROLLER NO ES OPCIONAL, y en este proyecto ya costó una vez.
    _buscador.dispose();
    // Y EL TEMPORIZADOR TAMPOCO: uno vivo dispararía un `setState` sobre un `State`
    // desmontado medio segundo después de salir de la pantalla.
    _esperaDelBuscador?.cancel();
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
  /// el de la búsqueda anterior después de cambiar el texto, el cliente o el tipo saltaría
  /// filas sin avisar. Todo lo que llama a `_cargar` empieza de cero **por construcción**,
  /// porque el cursor no se pasa.
  Future<void> _cargar() async {
    final mia = ++_generacion;

    setState(() {
      _cargando = true;
      _fallo = null;
      _falloDeLaPagina = null;
    });

    final resultado = await widget.repositorio.listar(
      widget.empresaId,
      clienteId: _clienteId,
      tipoId: _tipoId,
      estatus: _estatusParaElServidor,
      porTerminarEnDias: _diasParaElServidor,
      texto: _buscador.text,
    );

    if (!mounted || mia != _generacion) return;

    resultado.when(
      ok: (pagina) => setState(() {
        _servicios = pagina.servicios;
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
  /// mientras esta petición viaja, su respuesta **se descarta** en lugar de pegar las filas
  /// de la búsqueda vieja debajo de la nueva.
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
      clienteId: _clienteId,
      tipoId: _tipoId,
      estatus: _estatusParaElServidor,
      porTerminarEnDias: _diasParaElServidor,
      texto: _buscador.text,
      cursor: cursor,
    );

    if (!mounted || mia != _generacion) return;

    resultado.when(
      ok: (pagina) => setState(() {
        _servicios = [...?_servicios, ...pagina.servicios];
        _cursor = pagina.cursorSiguiente;
        _cargandoMas = false;
      }),
      // LO QUE YA ESTABA NO SE BORRA: una página que falla no convierte una lista con
      // filas en una pantalla de error. Se avisa debajo y el cursor se conserva.
      failure: (f) => setState(() {
        _falloDeLaPagina = f;
        _cargandoMas = false;
      }),
    );
  }

  /// Las opciones de los dos selectores, **acotadas como en el escritorio**.
  ///
  /// ## Por qué estas dos listas y no «todos»
  ///
  /// El inventario pide el filtro de cliente con **sólo los clientes que ya tienen
  /// servicios** y el de tipo con **sólo los tipos usados**: un selector que ofrece
  /// treinta tipos para acotar cuatro servicios no acota nada.
  ///
  /// ⚠️ **Y el de tipos NO es la misma lista que la del alta**, que ofrece los **activos**.
  /// Filtrar mira hacia atrás —qué hay— y dar de alta mira hacia adelante —qué se puede
  /// elegir—: un tipo retirado y usado sale aquí y no en el alta.
  ///
  /// ## Un fallo aquí NO rompe la pantalla
  ///
  /// Si los selectores no llegan, el listado se sigue viendo y se puede buscar por texto:
  /// lo que se pierde son dos filtros, no la pestaña. Por eso no toca [_fallo].
  Future<void> _cargarOpcionesDeFiltro() async {
    final conServicios = await widget.clientes.listar(
      widget.empresaId,
      conServicios: true,
      // EL TECHO DEL SERVIDOR, a propósito: un selector es una lista completa o no sirve
      // para filtrar, así que se pide todo lo que la ruta permite de una vez. Con más de
      // doscientos clientes con servicios habrá que cambiar el selector por un buscador,
      // y entonces esta línea es donde se nota.
      limite: 200,
    );

    final usados = await widget.repositorio.tipos(
      widget.empresaId,
      usados: true,
    );

    if (!mounted) return;

    setState(() {
      conServicios.when(
        ok: (p) => _clientesConServicios = p.clientes,
        // VACÍO Y NO NULO al fallar: nulo significaría «todavía no llegaron» y el selector
        // seguiría pareciendo que va a cargar. Vacío lo apaga y lo dice.
        failure: (_) => _clientesConServicios = const [],
      );

      usados.when(
        ok: (t) => _tiposUsados = t,
        failure: (_) => _tiposUsados = const [],
      );
    });
  }

  /// Qué estatus viaja en la petición.
  ///
  /// Con el chip en **Finalizados** y sin estatus elegido viaja `terminated`: el grupo es
  /// exactamente un estatus, así que el servidor puede filtrarlo. Con el chip en
  /// **Vigentes** y sin estatus elegido no viaja ninguno, porque son dos — y ésa es la
  /// única exclusión que hace la pantalla.
  EstatusDeServicio? get _estatusParaElServidor =>
      _estatus ??
      (_grupo == GrupoDeServicios.finalizados
          ? EstatusDeServicio.terminado
          : null);

  /// Cuántos días viajan como ventana de «por terminar», o **nulo si no es ese grupo**.
  ///
  /// El umbral es **el mismo que decide la insignia** —`diasParaEstarPorTerminar`—, y eso
  /// es lo que impide que el chip y la insignia digan cosas distintas: una fila sin
  /// insignia dentro del grupo sería un servicio que el filtro dice que termina pronto y
  /// la fila no.
  int? get _diasParaElServidor =>
      _grupo == GrupoDeServicios.porTerminar ? diasParaEstarPorTerminar : null;

  void _buscar(String _) {
    _esperaDelBuscador?.cancel();
    _esperaDelBuscador = Timer(const Duration(milliseconds: 350), _cargar);
  }

  void _cambiarGrupo(GrupoDeServicios grupo) {
    if (grupo == _grupo) return;

    setState(() => _grupo = grupo);
    _cargar();
  }

  bool get _hayFiltros =>
      _buscador.text.trim().isNotEmpty ||
      _estatus != null ||
      _clienteId != null ||
      _tipoId != null;

  void _limpiarFiltros() {
    _esperaDelBuscador?.cancel();

    setState(() {
      _buscador.clear();
      _estatus = null;
      _clienteId = null;
      _tipoId = null;
    });

    _cargar();
  }

  /// Las filas que se pintan.
  ///
  /// Lo único que se decide aquí es el chip, y sólo cuando el servidor no pudo: ver
  /// [_estatusParaElServidor].
  List<ServicioEnLista> get _visibles {
    final todos = _servicios ?? const <ServicioEnLista>[];

    if (_estatus != null) return todos;

    // «POR TERMINAR» LO ACOTÓ EL SERVIDOR, y volver a filtrar aquí sería peor que
    // redundante: la pantalla no sabe qué día es para el servidor, así que un servicio
    // justo en el límite podría caerse de la lista que el propio servidor incluyó.
    if (_grupo == GrupoDeServicios.porTerminar) return todos;

    return todos.where((s) {
      final finalizado = s.estado?.esFinalizado ?? false;

      // UN ESTATUS DESCONOCIDO CUENTA COMO VIGENTE, no como finalizado: de los dos errores
      // posibles, enseñar una fila de más en Vigentes se ve y se corrige; esconderla en
      // los dos grupos la haría desaparecer de la pantalla.
      return (_grupo == GrupoDeServicios.finalizados) == finalizado;
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
                title: 'Servicios',
                description:
                    'Operación comercial: cliente, ubicación y estatus de cada servicio.',
                // SIN PERMISO NO HAY BOTÓN, y no es lo mismo que un botón apagado: lo que
                // esta persona no puede hacer no se le enseña.
                primaryAction: widget.capacidades.puedeCrear
                    ? RisegButton(
                        label: 'Nuevo servicio',
                        icon: Icons.add,
                        onPressed: _cargando ? null : widget.alDarDeAlta,
                      )
                    : null,
                // EL CATÁLOGO SÍ SE OFRECE A QUIEN SÓLO LEE, y no es una inconsistencia:
                // consultar los tipos es `clients_services.read`, el mismo permiso con el
                // que se está viendo esta lista. La pantalla de tipos esconde sus propios
                // botones de escritura.
                secondaryAction: RisegButton(
                  label: 'Tipos de servicio',
                  variant: RisegButtonVariant.secondary,
                  icon: Icons.category_outlined,
                  onPressed: widget.alAbrirTipos,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _Chips(grupo: _grupo, alElegir: _cambiarGrupo),
              const SizedBox(height: AppSpacing.sm),
              _Filtros(
                buscador: _buscador,
                estatus: _estatus,
                clienteId: _clienteId,
                tipoId: _tipoId,
                clientes: _clientesConServicios,
                tipos: _tiposUsados,
                hayFiltros: _hayFiltros,
                onBuscar: _buscar,
                onEstatus: (v) {
                  setState(() => _estatus = v);
                  _cargar();
                },
                onCliente: (v) {
                  setState(() => _clienteId = v);
                  _cargar();
                },
                onTipo: (v) {
                  setState(() => _tipoId = v);
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
    if (_fallo case final f? when _servicios == null) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los servicios',
        message: f.message,
        primaryAction: RisegButton(
          label: 'Intentar de nuevo',
          onPressed: _cargar,
        ),
      );
    }

    return Column(
      children: [
        // ⚠️ EL DETECTOR VA AQUÍ Y NO DENTRO DE LA TABLA, y es lo que permite cargar sólo
        // los logotipos visibles **sin tocar `RisegTableBase`**: las notificaciones de
        // desplazamiento BURBUJEAN hacia arriba, así que la pantalla las oye sin que el
        // componente compartido —que usan también Personal, Áreas y Sucursales— tenga que
        // exponer su `ScrollController`.
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
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

    // ESTILO B · LA TABLA VA EN TARJETA Y CADA FILA LLEVA SU FRANJA: en un listado largo
    // lo primero que se busca es **cuál está mal**, y la franja lo dice sin leer. No
    // sustituye a la insignia —un estado dicho sólo con color no lo dice para quien no
    // distingue esos colores—: la acompaña.
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
    return RisegTableBase<ServicioEnLista>(
      loading: _cargando,
      rows: _visibles,
      hoverColor: colors.accentSoftBg,
      rowVerticalPadding: AppSpacing.sm + AppSpacing.xxs,
      onRowTap: (s) => widget.alAbrirExpediente(s.id),
      franjaDeLaFila: (s) => switch (s.estado) {
        EstatusDeServicio.activo => colors.success,
        EstatusDeServicio.suspendido => colors.warning,
        EstatusDeServicio.terminado => colors.borderSubtle,
        null => colors.borderSubtle,
      },
      emptyState: _vacio(),
      columns: [
        RisegColumn<ServicioEnLista>(
          label: 'Servicio',
          cellBuilder: _celdaDeServicio,
        ),
        RisegColumn<ServicioEnLista>(
          label: 'Ubicación',
          cellBuilder: (s) => Text(
            s.ubicacion ?? 'No registrada',
            style: s.ubicacion == null
                ? AppTypography.body.copyWith(color: colors.textMuted)
                : null,
          ),
        ),
        RisegColumn<ServicioEnLista>(
          label: 'Estatus',
          // 210 Y NO 140: debajo del estatus cabe ahora la insignia temporal, y
          // «Terminó el 12/nov/2026» no entra en 140 — un texto que no entra se corta y
          // deja una fecha a medias, que es peor que no decir nada.
          width: 210,
          cellBuilder: (s) => _Insignias(servicio: s, hoy: widget.hoy()),
        ),
      ],
    );
  }

  /// La celda del servicio: **el logotipo del cliente o sus iniciales**, el nombre del
  /// servicio, y debajo **el nombre del cliente y el folio**.
  ///
  /// Es la columna del escritorio tal cual, y el orden importa: el nombre del servicio es
  /// lo que se busca con la vista, y el del cliente es lo que lo sitúa.
  Widget _celdaDeServicio(ServicioEnLista s) {
    final colors = context.colors;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            width: 34,
            height: 34,
            child: _AvatarDelCliente(
              servicio: s,
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
                s.nombre,
                style: AppTypography.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                // EL CLIENTE Y EL FOLIO EN UNA LÍNEA, con un separador que no es una coma:
                // los nombres comerciales llevan comas —«Ríos, S.A. de C.V.»— y dos
                // comas seguidas no se leen.
                '${s.clienteNombreComercial} · ${s.codigo}',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    if (!_hayFiltros && _grupo == GrupoDeServicios.vigentes) {
      return RisegEmptyState(
        icon: Icons.design_services_outlined,
        title: 'Todavía no hay servicios',
        message:
            'Un servicio es lo que se le presta a un cliente en un lugar concreto '
            '—vigilancia en un club—. Un cliente con cuatro sedes tiene cuatro '
            'servicios, cada uno con su propio domicilio.',
        primaryAction: widget.capacidades.puedeCrear
            ? RisegButton(
                label: 'Nuevo servicio',
                icon: Icons.add,
                onPressed: widget.alDarDeAlta,
              )
            : null,
      );
    }

    // ⚠️ **EL VACÍO DE «POR TERMINAR» ES UNA BUENA NOTICIA, y se dice como tal:** «ningún
    // servicio coincide» invitaría a buscar qué filtro está mal puesto cuando la respuesta
    // es que no hay nada que atender.
    if (!_hayFiltros && _grupo == GrupoDeServicios.porTerminar) {
      return const RisegEmptyState(
        icon: Icons.event_available_outlined,
        title: 'Nada por terminar',
        message:
            'Ningún servicio tiene término programado en los próximos 30 días.',
      );
    }

    return RisegEmptyState(
      icon: Icons.search_off_outlined,
      title: _hayFiltros
          ? 'Ningún servicio coincide'
          : 'Ningún servicio finalizado',
      message: _hayFiltros
          ? 'Prueba con otro texto o quita los filtros. El buscador mira el folio, el '
                'nombre, el cliente, el tipo y las observaciones.'
          : 'Ningún servicio ha terminado.',
    );
  }
}

// ===========================================================================
// El avatar de la fila: el logotipo DEL CLIENTE si está a la vista
// ===========================================================================

/// El logotipo del cliente en el listado de servicios, **pedido sólo cuando la fila está a
/// la vista** (CP-20, condiciones 2 y 3).
///
/// ## Es el mismo mecanismo que en Clientes, y la caché lo aprovecha mejor
///
/// `RisegTableBase` **no virtualiza**: construye las filas de la página de golpe. Si el
/// avatar pidiera su logotipo en `initState`, abrir la pestaña dispararía una petición por
/// fila aunque sólo se vean doce.
///
/// ⚠️ **Aquí el logotipo es del CLIENTE, no del servicio**, y eso da algo gratis: cuatro
/// servicios del mismo cliente comparten `fileId`, así que la caché pide los bytes **una
/// vez** y las cuatro filas los pintan. En el listado de clientes cada fila era un archivo
/// distinto.
///
/// ## Lo que se pinta mientras tanto
///
/// Las **iniciales del cliente**, que son también lo que se pinta cuando no tiene
/// logotipo: una sola respuesta para los dos casos, así que la fila no salta de tamaño ni
/// parpadea en blanco.
class _AvatarDelCliente extends StatefulWidget {
  const _AvatarDelCliente({
    required this.servicio,
    required this.logotipos,
    required this.latidoDelScroll,
    required this.lado,
  });

  final ServicioEnLista servicio;
  final CacheDeLogotipos logotipos;
  final ValueNotifier<int> latidoDelScroll;
  final double lado;

  @override
  State<_AvatarDelCliente> createState() => _AvatarDelClienteState();
}

class _AvatarDelClienteState extends State<_AvatarDelCliente> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();

    widget.latidoDelScroll.addListener(_revisar);
    // LA PRIMERA REVISIÓN VA DESPUÉS DEL PRIMER FOTOGRAMA, no aquí: en `initState` este
    // widget todavía no tiene `RenderBox`, así que no hay geometría que comparar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisar());
  }

  @override
  void didUpdateWidget(_AvatarDelCliente anterior) {
    super.didUpdateWidget(anterior);

    if (anterior.latidoDelScroll != widget.latidoDelScroll) {
      anterior.latidoDelScroll.removeListener(_revisar);
      widget.latidoDelScroll.addListener(_revisar);
    }

    // ⚠️ LA FILA SE REUSA PARA OTRO SERVICIO al cambiar de página o de filtro —Flutter
    // reutiliza el elemento—, así que los bytes del anterior tienen que soltarse o se
    // pintaría el logotipo de otro cliente. Se compara por ARCHIVO: si el cliente
    // reemplazó su logotipo, el id cambia y esto también lo detecta.
    if (anterior.servicio.clienteLogotipoFileId !=
        widget.servicio.clienteLogotipoFileId) {
      _bytes = widget.logotipos.enMemoria(
        widget.servicio.clienteLogotipoFileId ?? '',
      );

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

    final fileId = widget.servicio.clienteLogotipoFileId;
    if (fileId == null) return;

    final yaEnMemoria = widget.logotipos.enMemoria(fileId);
    if (yaEnMemoria != null) {
      if (_bytes == null) setState(() => _bytes = yaEnMemoria);
      return;
    }

    if (widget.logotipos.yaSePidio(fileId) || !_estaALaVista()) return;

    widget.logotipos
        .pedir(clienteId: widget.servicio.clienteId, fileId: fileId)
        .then((bytes) {
          // `mounted` otra vez: entre pedir y responder, la persona pudo cambiar de
          // pantalla o de filtro. Y se comprueba que la fila siga siendo de ESTE archivo.
          if (!mounted || bytes == null) return;
          if (widget.servicio.clienteLogotipoFileId != fileId) return;

          setState(() => _bytes = bytes);
        });
  }

  /// Si el rectángulo de esta fila corta el del `Scrollable` que la contiene.
  ///
  /// Sin `Scrollable` alrededor se responde **que sí**: lo que no se puede medir no se
  /// esconde, porque el coste de enseñarlo de más es una petición y el de esconderlo es
  /// una fila sin logotipo.
  bool _estaALaVista() {
    final miCaja = context.findRenderObject();
    if (miCaja is! RenderBox || !miCaja.hasSize) return false;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return true;

    final cajaDelScroll = scrollable.context.findRenderObject();
    if (cajaDelScroll is! RenderBox || !cajaDelScroll.hasSize) return true;

    final mio = miCaja.localToGlobal(Offset.zero) & miCaja.size;
    final visible =
        cajaDelScroll.localToGlobal(Offset.zero) & cajaDelScroll.size;

    // MEDIA PANTALLA DE MARGEN ARRIBA Y ABAJO: la fila que viene ya tiene su logotipo
    // cuando asoma, y el margen sigue siendo pequeño frente a la página. Con una pantalla
    // entera, una página de cincuenta filas cabría casi completa en la banda y «sólo las
    // visibles» dejaría de significar nada.
    return mio.overlaps(visible.inflate(visible.height / 2));
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    if (bytes == null) {
      // EL COLOR SALE DEL ID DEL CLIENTE Y NO DEL DEL SERVICIO, y es deliberado: los
      // cuatro servicios de Sportium se reconocen de un vistazo por compartir color.
      // Con el id del servicio, cuatro filas del mismo cliente tendrían cuatro colores.
      return RisegIniciales(
        id: widget.servicio.clienteId,
        nombre: widget.servicio.clienteNombreComercial,
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
      key: ValueKey<String?>(widget.servicio.clienteLogotipoFileId),
      errorBuilder: (_, _, _) => RisegIniciales(
        id: widget.servicio.clienteId,
        nombre: widget.servicio.clienteNombreComercial,
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
/// claro que **lo que se ve no es todo**.
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
    // SIN MÁS PÁGINAS Y SIN FALLO NO HAY PIE. Un «no hay más» permanente sería ruido, y
    // con una sola página no aporta nada.
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
                // creería que la lista se acaba donde se acabó la última página buena.
                'No se pudieron cargar más servicios: ${f.message}',
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
                cuantas == 1
                    ? '1 servicio a la vista'
                    : '$cuantas servicios a la vista',
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

  final GrupoDeServicios grupo;
  final ValueChanged<GrupoDeServicios> alElegir;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    children: [
      for (final g in GrupoDeServicios.values)
        ChoiceChip(
          label: Text(g.nombre),
          selected: grupo == g,
          // `onSelected` RECIBE EL BOOLEANO Y SE IGNORA: estos chips son exclusivos, así
          // que pulsar el que ya está puesto no lo apaga.
          onSelected: (_) => alElegir(g),
        ),
    ],
  );
}

/// Los cuatro filtros: buscador, cliente, tipo y estatus.
///
/// ⚠️ **Los dos selectores de lista se apagan cuando no hay nada que ofrecer**, y las dos
/// razones son distintas: [clientes] nulo es «todavía no llegaron» y vacío es «ningún
/// cliente tiene servicios todavía». Un selector encendido y vacío parece roto.
class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.buscador,
    required this.estatus,
    required this.clienteId,
    required this.tipoId,
    required this.clientes,
    required this.tipos,
    required this.hayFiltros,
    required this.onBuscar,
    required this.onEstatus,
    required this.onCliente,
    required this.onTipo,
    required this.onLimpiar,
  });

  final TextEditingController buscador;
  final EstatusDeServicio? estatus;
  final String? clienteId;
  final String? tipoId;
  final List<ClienteEnLista>? clientes;
  final List<TipoDeServicio>? tipos;
  final bool hayFiltros;
  final ValueChanged<String> onBuscar;
  final ValueChanged<EstatusDeServicio?> onEstatus;
  final ValueChanged<String?> onCliente;
  final ValueChanged<String?> onTipo;
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    final conServicios = clientes ?? const <ClienteEnLista>[];
    final usados = tipos ?? const <TipoDeServicio>[];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: RisegSearchField(
            hint: 'Folio, nombre, cliente, tipo u observaciones',
            controller: buscador,
            onChanged: onBuscar,
          ),
        ),
        SizedBox(
          width: 220,
          child: RisegSelect<String?>(
            label: 'Cliente',
            value: clienteId,
            items: [
              const RisegSelectItem(value: null, label: 'Todos los clientes'),
              for (final c in conServicios)
                RisegSelectItem(
                  value: c.cliente.id,
                  label: c.cliente.nombreComercial,
                ),
            ],
            onChanged: conServicios.isEmpty ? null : onCliente,
          ),
        ),
        SizedBox(
          width: 200,
          child: RisegSelect<String?>(
            label: 'Tipo',
            value: tipoId,
            items: [
              const RisegSelectItem(value: null, label: 'Todos los tipos'),
              for (final t in usados)
                RisegSelectItem(value: t.id, label: t.nombre),
            ],
            onChanged: usados.isEmpty ? null : onTipo,
          ),
        ),
        SizedBox(
          width: 190,
          child: RisegSelect<EstatusDeServicio?>(
            label: 'Estatus',
            value: estatus,
            items: [
              const RisegSelectItem(value: null, label: 'Todos los estatus'),
              for (final e in EstatusDeServicio.values)
                RisegSelectItem(value: e, label: e.nombre),
            ],
            onChanged: onEstatus,
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
}

/// El estatus de la fila **y debajo su eje temporal**, cuando hay algo que decir.
///
/// ⚠️ **SON DOS EJES Y NO SE MEZCLAN**, y ésa es la falla del 11 de noviembre de 2026: el
/// estatus dice qué se decidió —activo, suspendido, terminado— y el temporal dónde cae hoy
/// respecto de sus fechas. Quién habla en el segundo lo decide
/// `insignia_temporal.dart`, que es el mismo sitio del que lo saca el expediente: en un
/// terminado dice **cuándo terminó** en vez de «Vigente».
class _Insignias extends StatelessWidget {
  const _Insignias({required this.servicio, required this.hoy});

  final ServicioEnLista servicio;
  final DiaDeNegocio hoy;

  @override
  Widget build(BuildContext context) {
    final temporal = insigniaTemporalDe(
      hoy: hoy,
      estatus: servicio.estatus,
      condicionTemporal: servicio.condicionTemporal,
      termino: servicio.termino,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _InsigniaDeEstatus(servicio: servicio),
        if (temporal != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          temporal.pintar(),
        ],
      ],
    );
  }
}

/// La insignia de estatus.
///
/// ⚠️ **UN ESTATUS QUE ESTA BUILD NO CONOCE SE ENSEÑA TAL CUAL**, con tono neutro, en vez
/// de caer en «Activo» por omisión. Un `_ => activo` pintaría como activo un servicio que
/// no lo está, que es la clase de error que nadie va a notar.
class _InsigniaDeEstatus extends StatelessWidget {
  const _InsigniaDeEstatus({required this.servicio});

  final ServicioEnLista servicio;

  @override
  Widget build(BuildContext context) => switch (servicio.estado) {
    EstatusDeServicio.activo => const RisegStatusBadge(
      label: 'Activo',
      tone: RisegStatusTone.success,
      icon: Icons.check_circle_outline,
    ),
    EstatusDeServicio.suspendido => const RisegStatusBadge(
      label: 'Suspendido',
      tone: RisegStatusTone.warning,
      icon: Icons.pause_circle_outline,
    ),
    EstatusDeServicio.terminado => const RisegStatusBadge(
      label: 'Terminado',
      tone: RisegStatusTone.neutral,
      icon: Icons.do_not_disturb_on_outlined,
    ),
    null => RisegStatusBadge(
      label: servicio.estatus,
      tone: RisegStatusTone.neutral,
      icon: Icons.help_outline,
    ),
  };
}
