import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL, no del catálogo de permisos: esta feature no puede
// importar `PermisoCompany` —hay un guardia que lo impide— y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;
import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/direcciones/campos_de_domicilio.dart';
import '../../../../core/direcciones/direccion.dart';
import '../../../../core/direcciones/seccion_de_domicilio.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/error/rechazo_del_servidor.dart';
import '../../../../core/error/result.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../../../personal/web/datos/empleados_repositorio_http.dart';
import '../../../personal/web/modelos/empleado_elegible.dart';
import '../../../organizacion/web/datos/sucursales_repositorio_http.dart';
import '../../../organizacion/web/modelos/sucursal.dart';
import '../datos/clientes_repositorio_http.dart';
import '../datos/servicios_repositorio_http.dart';
import '../modelos/contacto.dart';
import '../modelos/entidad_fiscal.dart';
import '../modelos/servicio.dart';
import 'insignia_temporal.dart';

/// **Cuanto hay de un servicio, en un solo sitio**: su ficha, sus indicadores, sus datos
/// generales, su domicilio operativo, su supervisor y sus tres vínculos.
///
/// ## Consultar y editar son DOS DIRECCIONES
///
/// `/comercial/servicios/<id>` y `/comercial/servicios/<id>/editar`, igual que el
/// expediente de un cliente y por la misma razón: **consultar no es cambiar**. Así
/// «atrás» devuelve de la edición a la consulta, el enlace de un servicio se puede pegar
/// sin abrir un formulario, y el `onExit` de la ruta de edición es el que pregunta por el
/// trabajo sin guardar (D-56).
///
/// ## Qué entra en «Guardar» y qué NO, que es la decisión de diseño de esta pantalla
///
/// En el formulario viven **sólo los campos que `PATCH /services/{id}` corrige con un
/// motivo**: nombre, tipo y observaciones, más el domicilio operativo por su `PUT`. Todo
/// lo demás —el estatus, el término, el supervisor y los tres vínculos— tiene **su propia
/// ruta y sus propias reglas**, así que son acciones y no campos.
///
/// 🚫 **Y no es una preferencia estética.** Meter el supervisor en el formulario obligaría
/// a pedir un motivo que su ruta no pide, y meter la entidad fiscal obligaría a lo
/// contrario: pedirlo siempre cuando el servidor sólo lo exige al **cambiarla** (R9). Un
/// formulario que junta reglas distintas acaba mintiendo sobre una de ellas.
///
/// ## Guardar son hasta DOS peticiones, y el servidor no las junta
///
/// El servicio va por `PATCH /services/{id}` **con motivo** y el domicilio por
/// `PUT /services/{id}/address` **sin él**. De ahí tres reglas, las mismas que el
/// expediente de un cliente:
///
///  1. **sólo viaja lo que cambió** —el servidor rechaza un `PATCH` que no cambia nada—;
///  2. **si la segunda falla, la primera ya ocurrió**, y se dice qué quedó guardado. No se
///     intenta deshacer: deshacer una corrección es otra corrección, con su motivo;
///  3. **el domicilio operativo se CORRIGE y no se quita**: desde la 0059 no existe
///     servicio sin domicilio, y el servidor no publica un `DELETE`.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo.</b> El completo exporta
/// un componente que lee del disco con `dart:io` y rompería la build web.
class ExpedienteServicioWebScreen extends StatefulWidget {
  const ExpedienteServicioWebScreen({
    required this.repositorio,
    required this.clientes,
    required this.sucursales,
    required this.empleados,
    required this.empresaId,
    required this.servicioId,
    required this.capacidades,
    required this.puedeElegirSupervisor,
    required this.guardia,
    required this.editando,
    required this.alIrADentro,
    required this.alVolver,
    required this.alConocerElNombre,
    this.hoy = DiaDeNegocio.hoy,
    super.key,
  });

  /// **Qué día es hoy, para la insignia «Termina el…».**
  ///
  /// ⚠️ **ENTRA POR EL CONSTRUCTOR** por la misma razón que en el listado: con el reloj
  /// leído adentro, una prueba que fije un término a cincuenta días se rompería sola
  /// cincuenta días después. Y es el **día de México**, nunca `DateTime.now()`.
  final DiaDeNegocio Function() hoy;

  final ServiciosRepositorioHttp repositorio;

  /// El repositorio de **clientes**, por dos cosas que son del cliente y no del servicio:
  /// sus **contactos** y sus **entidades fiscales**, que son lo que los dos selectores de
  /// vínculo ofrecen.
  final ClientesRepositorioHttp clientes;

  /// Las sucursales **propias**, para el vínculo administrativo.
  ///
  /// 🚫 **No es dónde se presta el servicio** —eso es el domicilio operativo—: `Branch` es
  /// destino administrativo y `Service` el operativo, que es la regla fundamental de
  /// Personal vista desde el otro lado.
  final SucursalesRepositorioHttp sucursales;

  /// Los empleados, **sólo para el selector del supervisor**.
  final EmpleadosRepositorioHttp empleados;

  final String empresaId;

  /// **El id de la URL**, y de la URL sale sólo esto: dónde estás. Lo que se puede hacer
  /// sigue saliendo del contexto que confirmó el servidor.
  final String servicioId;

  final CapacidadesDeModulo capacidades;

  /// Si a quien mira se le puede **ofrecer el selector** de supervisor.
  ///
  /// ⚠️ **Se resuelve en el SHELL y llega resuelto**, por decisión del dueño, y la razón
  /// es que son **dos módulos**: ver el supervisor es `clients_services.read` —la ruta es
  /// del servicio—, pero **elegirlo** obliga a listar empleados, y eso es
  /// `personal.read`. Quien tenga Comercial y no Personal **ve** quién responde por el
  /// servicio y no se le ofrece cambiarlo: enseñar el selector sería enseñar una puerta
  /// que responde 403.
  ///
  /// Y **no sustituye a `capacidades`**: para cambiarlo hacen falta las dos cosas,
  /// `clients_services.manage` para escribir el vínculo y esto para poder elegir a quién.
  final bool puedeElegirSupervisor;

  /// D-56 · dónde se registra que hay trabajo sin guardar. **Esta pantalla SÍ lo usa**.
  final GuardiaDeSalida guardia;

  /// Si la dirección dice que se está editando. **No es estado de la pantalla** (D-39).
  final bool editando;

  /// Pide cambiar de modo. `null` vuelve a la consulta, `'editar'` abre la edición.
  ///
  /// **La pantalla pide, no navega:** quien conoce la ruta del apartado es el portón.
  final void Function(String? aDonde) alIrADentro;

  /// Vuelve al listado.
  final VoidCallback alVolver;

  /// Publica cómo se llama el servicio, **para el rastro**. Sale de la fila cargada y
  /// **nunca de la URL**, donde quedaría viejo en cuanto alguien lo renombrara.
  final void Function(String id, String nombre) alConocerElNombre;

  @override
  State<ExpedienteServicioWebScreen> createState() =>
      _ExpedienteServicioWebScreenState();
}

class _ExpedienteServicioWebScreenState
    extends State<ExpedienteServicioWebScreen>
    with DeclaraSuTrabajoSinGuardar<ExpedienteServicioWebScreen> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Lo que el servidor devolvió la última vez que esta pantalla y él coincidieron.
  /// **Es la base de la comparación de cambios**, no una copia de cortesía.
  Servicio? _servicio;
  IndicadoresDeServicio? _indicadores;
  Direccion? _domicilioCargado;
  SupervisorDelServicio? _supervisor;

  List<TipoDeServicio> _tipos = const [];
  List<ContactoDeCliente> _contactos = const [];
  List<EntidadFiscal> _entidades = const [];
  List<Sucursal> _sucursales = const [];

  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;

  final _nombre = TextEditingController();
  final _observaciones = TextEditingController();
  final _domicilio = CamposDeDomicilio();

  /// Los de **sólo lectura**.
  ///
  /// ⚠️ **SON CAMPOS DEL ESTADO Y NO SE CREAN EN EL `build`**: un `TextEditingController`
  /// nuevo en cada repintado se queda sin liberar, y aquí hay un repintado por tecla.
  final _folio = TextEditingController();
  final _inicio = TextEditingController();
  final _creado = TextEditingController();
  final _actualizado = TextEditingController();

  String? _tipoId;

  /// La pestaña abierta: **General · Domicilio · Vínculos**.
  ///
  /// ⚠️ **SE MUEVE SOLA CUANDO UN ERROR CAE EN OTRA PESTAÑA**, y sin eso el estilo B
  /// habría estrenado un fallo propio: guardar con la colonia vacía señalaría un campo
  /// **que no está a la vista**, y la pantalla parecería no hacer nada. Lo hace
  /// [_pestanaDeLosErrores].
  int _pestana = 0;

  /// Lo que falta por capturar, **por clave del servidor**, para señalarlo en su cuadro.
  ///
  /// Era un `String? _errorDeNombre` hasta el 11 de noviembre de 2026, y con eso los
  /// campos del domicilio no se podían marcar: el único que podía ponerse en rojo era el
  /// nombre, y los demás se descubrían de uno en uno en el aviso del servidor.
  Map<String, String> _faltantes = const {};

  /// Los nodos de foco, en el orden de la pantalla: con el botón al final, un error
  /// arriba se pintaba donde nadie estaba mirando.
  final _focos = RisegFocosDeFormulario(const [
    'name',
    'address.street',
    'address.exteriorNumber',
    'address.interiorNumber',
    'address.neighborhood',
    'address.municipality',
    'address.city',
    'address.state',
    'address.postalCode',
    'address.country',
    'address.landmarks',
  ]);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _observaciones,
      _folio,
      _inicio,
      _creado,
      _actualizado,
    ]) {
      c.dispose();
    }

    // Los diez del domicilio los libera su juego, que es su dueño.
    _domicilio.dispose();
    // NO ES OPCIONAL: un `FocusNode` sin liberar deja al `FocusManager` con una
    // referencia a un widget desmontado.
    _focos.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ExpedienteServicioWebScreen anterior) {
    super.didUpdateWidget(anterior);

    // ⚠️ **CAMBIAR DE SERVICIO SIN DESMONTAR LA PANTALLA PASA DE VERDAD**: las dos
    // direcciones son la misma ruta con otro `<id>`, así que go_router reutiliza este
    // `State`. Sin esto, el expediente seguiría enseñando el servicio anterior con la URL
    // del nuevo.
    if (anterior.servicioId != widget.servicioId) _cargar();

    // SALIR DE LA EDICIÓN SIN GUARDAR DEVUELVE LO CARGADO. La pregunta la hizo ya el
    // `onExit` de la ruta; si llegó aquí, es que se eligió salir.
    if (anterior.editando && !widget.editando) _volcar();
  }

  // =========================================================================
  // Cargar
  // =========================================================================

  /// Las lecturas de la ficha, **en paralelo**.
  ///
  /// ⚠️ **SÓLO EL SERVICIO PUEDE IMPEDIR PINTAR.** Si fallan los indicadores, los tipos o
  /// cualquiera de las tres listas de los selectores, la ficha sale con lo que hay: un
  /// servicio que no se puede consultar porque su lista de sucursales no bajó sería una
  /// pantalla inútil por un selector.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final servicio = await widget.repositorio.ver(
      empresaId: widget.empresaId,
      servicioId: widget.servicioId,
    );

    if (!mounted) return;

    final ficha = servicio.when<Servicio?>(ok: (s) => s, failure: (_) => null);

    if (ficha == null) {
      setState(() {
        _fallo = servicio.when(ok: (_) => null, failure: (f) => f);
        _cargando = false;
      });

      return;
    }

    // EL NOMBRE PARA EL RASTRO, en cuanto se conoce y de los datos.
    widget.alConocerElNombre(ficha.id, ficha.nombre);

    final resto = await Future.wait([
      widget.repositorio.indicadores(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
      ),
      widget.repositorio.domicilio(
        empresaId: widget.empresaId,
        servicioId: widget.servicioId,
      ),
      widget.repositorio.tipos(widget.empresaId, usados: null),
      widget.clientes.listarContactos(
        empresaId: widget.empresaId,
        clienteId: ficha.clienteId,
      ),
      widget.clientes.listarEntidadesFiscales(
        empresaId: widget.empresaId,
        clienteId: ficha.clienteId,
      ),
      widget.sucursales.listar(widget.empresaId),
      // EL SUPERVISOR SE PIDE SÓLO SI LA FICHA DICE QUE HAY UNO: su ruta responde 404
      // cuando no, y pedirlo igual sería pagar una consulta para que conteste «no hay»
      // algo que la ficha ya dijo.
      if (ficha.supervisorEmpleadoId != null)
        widget.repositorio.supervisor(
          empresaId: widget.empresaId,
          servicioId: widget.servicioId,
        ),
    ]);

    if (!mounted) return;

    setState(() {
      _servicio = ficha;
      _indicadores = resto[0].when<IndicadoresDeServicio?>(
        ok: (v) => v as IndicadoresDeServicio?,
        failure: (_) => null,
      );
      _domicilioCargado = resto[1].when<Direccion?>(
        ok: (v) => v as Direccion?,
        failure: (_) => null,
      );
      _tipos = resto[2].when<List<TipoDeServicio>>(
        ok: (v) => v as List<TipoDeServicio>,
        failure: (_) => const [],
      );
      _contactos = resto[3].when<List<ContactoDeCliente>>(
        ok: (v) => v as List<ContactoDeCliente>,
        failure: (_) => const [],
      );
      _entidades = resto[4].when<List<EntidadFiscal>>(
        ok: (v) => v as List<EntidadFiscal>,
        failure: (_) => const [],
      );
      _sucursales = resto[5].when<List<Sucursal>>(
        ok: (v) => v as List<Sucursal>,
        failure: (_) => const [],
      );
      _supervisor = resto.length > 6
          ? resto[6].when<SupervisorDelServicio?>(
              ok: (v) => v as SupervisorDelServicio?,
              failure: (_) => null,
            )
          : null;
      _cargando = false;
    });

    _volcar();
  }

  /// Vuelca lo cargado en los campos. **Es la base de la comparación**, así que se llama
  /// al cargar y al salir de la edición sin guardar.
  void _volcar() {
    final s = _servicio;
    if (s == null) return;

    // UN VOLCADO ESTRENA FORMULARIO: lo volcado es «lo cargado», así que lo que se
    // hubiera guardado antes deja de contar.
    _yaSeGuardo = false;

    _nombre.text = s.nombre;
    _observaciones.text = s.observaciones ?? '';
    _folio.text = s.codigo;
    _inicio.text = switch (s.inicio) {
      final d? => fechaDeNegocioCorta(d),
      null => '—',
    };
    _creado.text = fechaYHora(s.creadoEn);
    _actualizado.text = fechaYHora(s.actualizadoEn);
    _tipoId = s.tipoId;
    _domicilio.volcar(_domicilioCargado);

    setState(() => _faltantes = const {});
  }

  /// Las observaciones escritas, o nulo si quedaron vacías.
  String? get _observacionesEscritas {
    final texto = _observaciones.text.trim();

    return texto.isEmpty ? null : texto;
  }

  // =========================================================================
  // D-56 · lo que se perdería
  // =========================================================================

  /// Si lo de este formulario **ya se guardó**.
  ///
  /// 🚫 **ES LA FALLA DEL 12 DE NOVIEMBRE DE 2026**, la misma que el expediente de un
  /// cliente: guardar navega, navegar pasa por el `onExit` de la ruta, y el `onExit`
  /// compara el formulario **contra la respuesta del servidor**. Una sola comparación que
  /// no coincida deja la pantalla creyendo que hay trabajo sin guardar **justo después de
  /// guardarlo**, y la pregunta bloquea la vuelta a la consulta.
  ///
  /// ⚠️ **No se arregla afinando comparaciones**: lo que se guardó no es trabajo sin
  /// guardar, lo diga la respuesta como lo diga. Se apaga al volcar.
  bool _yaSeGuardo = false;

  /// ⚠️ **SÓLO EDITANDO.** En consulta no hay nada escrito que perder, y preguntar al
  /// salir de una ficha que nadie tocó enseña a ignorar la pregunta.
  @override
  bool get hayCambiosSinGuardar {
    if (!widget.editando) return false;
    if (_yaSeGuardo) return false;

    final s = _servicio;
    if (s == null) return false;

    return _nombre.text.trim() != s.nombre ||
        _observacionesEscritas != s.observaciones ||
        _tipoId != s.tipoId ||
        !_domicilio.igualA(_domicilioCargado);
  }

  /// **El nombre sale del servicio CARGADO, no del campo**: a quien está renombrando, la
  /// pregunta le hablaría de algo que todavía no existe con ese nombre.
  @override
  String get queSePierde => switch (_servicio) {
    final s? => 'el servicio ${s.codigo} ${s.nombre}',
    null => 'este servicio',
  };

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
          child: _cuerpo(),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el servicio',
        message: f.message,
        primaryAction: RisegButton(
          label: 'Intentar de nuevo',
          onPressed: _cargar,
        ),
        secondaryAction: RisegButton(
          label: 'Volver a Servicios',
          variant: RisegButtonVariant.secondary,
          onPressed: widget.alVolver,
        ),
      );
    }

    final s = _servicio;
    if (s == null) return const SizedBox.shrink();

    // ===================================================================
    // ESTILO B · PESTAÑAS, elegido por el dueño el 11 de noviembre de 2026
    // ===================================================================
    //
    // La cabecera y las pestañas **se quedan fijas** y sólo rueda el contenido: era el
    // segundo problema que el dueño enumeró —«el expediente es una página larga sin
    // jerarquía»—. Con todo apilado, para saber qué servicio se mira y qué se puede
    // hacer con él había que recorrer la página hasta el final.
    //
    // ⚠️ **LAS ACCIONES DE GUARDAR VIVEN EN LA CABECERA**, no al pie. Con pestañas, un
    // botón al final del contenido **sólo existiría en la pestaña abierta**: quien
    // estuviera en Domicilio no vería «Guardar». Arriba está siempre.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Volver(onVolver: widget.alVolver),
        const SizedBox(height: AppSpacing.sm),
        _cabecera(s),
        const SizedBox(height: AppSpacing.md),
        RisegTabs(
          tabs: const [
            RisegTabItem(label: 'General'),
            RisegTabItem(label: 'Domicilio'),
            RisegTabItem(label: 'Vínculos'),
          ],
          selectedIndex: _pestana,
          onChanged: (i) => setState(() => _pestana = i),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: SingleChildScrollView(
            child: switch (_pestana) {
              0 => _pestanaGeneral(s),
              1 => _pestanaDomicilio(),
              _ => _pestanaVinculos(s),
            },
          ),
        ),
      ],
    );
  }

  /// La cabecera: quién es, cómo está, qué se puede hacer y cuánto.
  Widget _cabecera(Servicio s) {
    final estado = s.estado;
    final temporal = insigniaTemporalDe(
      hoy: widget.hoy(),
      estatus: s.estatus,
      condicionTemporal: s.condicionTemporal,
      termino: s.termino,
    );
    final terminado = estado?.esFinalizado ?? false;
    final i = _indicadores;

    return RisegExpedienteHeader(
      titulo: s.nombre,
      subtitulo: s.codigo,
      identidad: RisegIniciales(id: s.id, nombre: s.nombre, lado: 40),
      insignias: [
        if (estado != null)
          RisegStatusBadge(
            label: estado.nombre,
            tone: switch (estado) {
              EstatusDeServicio.activo => RisegStatusTone.success,
              EstatusDeServicio.suspendido => RisegStatusTone.warning,
              EstatusDeServicio.terminado => RisegStatusTone.neutral,
            },
            icon: switch (estado) {
              EstatusDeServicio.activo => Icons.check_circle_outline,
              EstatusDeServicio.suspendido => Icons.pause_circle_outline,
              EstatusDeServicio.terminado => Icons.flag_outlined,
            },
          ),
        if (temporal != null) temporal.pintar(),
      ],
      acciones: [
        if (widget.editando) ...[
          RisegButton(
            label: 'Cancelar',
            variant: RisegButtonVariant.secondary,
            onPressed: _guardando ? null : () => widget.alIrADentro(null),
          ),
          RisegButton(
            label: 'Guardar',
            loading: _guardando,
            onPressed: _guardando ? null : _guardar,
          ),
        ] else if (widget.capacidades.puedeModificar) ...[
          RisegButton(
            label: 'Cambiar estatus',
            variant: RisegButtonVariant.secondary,
            icon: Icons.swap_horiz,
            onPressed: _guardando ? null : _cambiarEstatus,
          ),
          RisegButton(
            label: 'Editar',
            icon: Icons.edit_outlined,
            onPressed: _guardando ? null : () => widget.alIrADentro('editar'),
          ),
        ],
      ],
      cifras: [
        if (i != null)
          RisegCifra(
            'Importe mensual',
            // ⚠️ **AUSENCIA NUNCA ES CERO.** Una lista vacía significa que no hay
            // condiciones comerciales vigentes, y «$0.00» diría que el servicio no vale
            // nada. Son dos cosas distintas y se dicen distinto.
            i.importeMensual.isEmpty
                ? 'Sin condiciones vigentes'
                : i.importeMensual.map((m) => m.enPantalla).join(' · '),
          ),
        if (i != null)
          RisegCifra(
            terminado ? 'Duró' : 'Antigüedad',
            i.antiguedadEnPantalla,
            // EN UN TERMINADO DEJA DE CRECER: se mide hasta su término, porque lo que
            // dice es cuánto duró.
            nota: terminado ? 'Hasta su término.' : null,
          ),
      ],
    );
  }

  /// En qué pestaña cae el primer error, para abrirla antes de pintarlo.
  ///
  /// ⚠️ **SIN ESTO EL ESTILO B ESTRENARÍA UN FALLO PROPIO:** con el domicilio en su
  /// pestaña, guardar con la colonia vacía señalaría un campo que **no está a la vista**,
  /// y la pantalla parecería no hacer nada al pulsar «Guardar».
  int _pestanaDeLosErrores(Map<String, String> faltantes) =>
      faltantes.keys.any((k) => k.startsWith('address.')) ? 1 : 0;

  // =========================================================================
  // Las tres pestañas
  // =========================================================================

  /// **General:** lo que se corrige, lo que sólo se lee, y el término.
  Widget _pestanaGeneral(Servicio s) {
    final editando = widget.editando;
    final puedeEscribir = editando && !_guardando;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegTarjeta(
          // LA LETRA CHICA, UNA VEZ POR SECCIÓN Y NO POR CAMPO: era el cuarto problema
          // del dueño. Y dice la consecuencia para quien captura, no el por qué interno.
          nota: 'El cliente queda fijo: no se puede cambiar.',
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🚫 **EN CONSULTA NO HAY UN SOLO CUADRO.** Era el problema de «la vista se
              // ve casi igual que la edición»: un `RisegTextField` apagado con el dato
              // dentro parece un campo que no te dejan tocar, no un dato.
              if (!editando)
                RisegDatoEnLinea(
                  etiqueta: 'Tipo de servicio',
                  valor: _nombreDelTipo(s),
                )
              else
                RisegCuadricula(
                  celdas: [
                    RisegCelda.media(
                      RisegTextField(
                        label: 'Nombre del servicio',
                        controller: _nombre,
                        focusNode: _focos['name'],
                        enabled: puedeEscribir,
                        errorText: _faltantes['name'],
                      ),
                    ),
                    RisegCelda.media(
                      RisegSelect<String?>(
                        label: 'Tipo de servicio',
                        value: _tipoId,
                        enabled: puedeEscribir,
                        items: [
                          // ⚠️ **EL TIPO ACTUAL SE OFRECE AUNQUE ESTÉ RETIRADO.** Si no,
                          // un servicio con un tipo que la empresa desactivó abriría el
                          // expediente con el selector en blanco, y guardar cualquier otra
                          // corrección le cambiaría el tipo sin que nadie lo pidiera. Un
                          // retirado no se puede ELEGIR; el que ya está, se conserva.
                          for (final t in _tipos)
                            if (t.estaActivo || t.id == s.tipoId)
                              RisegSelectItem(
                                value: t.id,
                                label: t.estaActivo
                                    ? t.nombre
                                    : '${t.nombre} (retirado)',
                              ),
                        ],
                        onChanged: (v) => setState(() => _tipoId = v),
                      ),
                    ),
                    RisegCelda.ancha(
                      RisegTextField(
                        label: 'Observaciones',
                        controller: _observaciones,
                        enabled: puedeEscribir,
                        maxLines: 3,
                      ),
                    ),
                  ],
                ),

              // ⚠️ **LO QUE NUNCA SE EDITA ES UN DATO, NO UN CAMPO APAGADO**, y por eso
              // se lee igual en consulta y en edición: el folio y las tres fechas no
              // cambian desde aquí ni en modo edición, así que pintarlos como cuadros
              // deshabilitados sólo invitaba a intentar escribir en ellos.
              if (editando) const SizedBox(height: AppSpacing.md),
              RisegDatoEnLinea(etiqueta: 'Folio', valor: s.codigo),
              RisegDatoEnLinea(
                etiqueta: 'Fecha de inicio',
                valor: _inicio.text,
                vacioDice: 'Sin fecha de inicio',
              ),
              // D-58 · ES OTRA COSA QUE EL INICIO, y por eso están los dos: una es cuándo
              // empezó a operar el servicio y otra cuándo se capturó la fila.
              RisegDatoEnLinea(
                etiqueta: 'Alta en el sistema',
                valor: _creado.text,
              ),
              RisegDatoEnLinea(
                etiqueta: 'Última actualización',
                valor: _actualizado.text,
              ),
              // LAS OBSERVACIONES AL FINAL, y es lo que la captura enseñó: es el único
              // dato largo, y en medio de la lista parte los renglones cortos en dos
              // bloques que ya no se leen como una columna.
              if (!editando)
                RisegDatoEnLinea(
                  etiqueta: 'Observaciones',
                  valor: s.observaciones,
                  vacioDice: 'Sin observaciones',
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _tarjetaDelTermino(s),
      ],
    );
  }

  /// Cómo se llama el tipo del servicio, con lo que el catálogo trajo.
  ///
  /// **Nunca un identificador en pantalla:** si el catálogo no cargó, se dice que no se
  /// pudo leer en vez de enseñar un UUID, que no le sirve a nadie.
  String _nombreDelTipo(Servicio s) {
    for (final t in _tipos) {
      if (t.id != s.tipoId) continue;

      return t.estaActivo ? t.nombre : '${t.nombre} (retirado)';
    }

    return '';
  }

  /// **Domicilio operativo:** en consulta como texto, en edición los diez campos.
  Widget _pestanaDomicilio() => RisegTarjeta(
    titulo: 'Domicilio operativo',
    // 🚫 **NINGÚN NÚMERO DE MIGRACIÓN EN LA PANTALLA.** Esto decía «desde la 0059 no
    // existe un servicio sin domicilio operativo», y el dueño lo leyó en el ensayo: a
    // quien captura no le dice nada, y lo vigila `textos_sin_jerga_interna_test.dart`.
    nota: widget.editando
        ? 'Dónde se presta el servicio. Se corrige, pero no se puede dejar vacío.'
        : 'Dónde se presta el servicio.',
    hijo: widget.editando
        ? SeccionDeDomicilio(
            // SIN TÍTULO: ya lo pone la tarjeta, y repetirlo lo diría dos veces.
            titulo: '',
            campos: _domicilio,
            habilitado: !_guardando,
            erroresPorCampo: _faltantes,
            focos: _focos,
            descripcion: '',
          )
        : DomicilioEnTexto(direccion: _domicilioCargado),
  );

  /// **Vínculos:** el supervisor y las tres asignaciones.
  ///
  /// ⚠️ **ESTAS CUATRO FILAS SE GUARDAN AL MOMENTO**, cada una por su ruta, así que no
  /// pasan por el «Guardar» del expediente y **se ofrecen igual en consulta**: esconder
  /// sus botones en modo consulta obligaría a entrar a editar para algo que no se edita.
  Widget _pestanaVinculos(Servicio s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _tarjetaDelSupervisor(),
      const SizedBox(height: AppSpacing.md),
      _tarjetaDeLosVinculos(s),
    ],
  );

  /// El término programado, con sus dos botones.
  ///
  /// Vive en **General** y no en una pestaña propia: una fecha no es un asunto, y una
  /// pestaña con un solo renglón es una pestaña que nadie abre.
  Widget _tarjetaDelTermino(Servicio s) {
    final termino = s.termino;
    final terminado = s.estado?.esFinalizado ?? false;
    final puedeCambiar = widget.capacidades.puedeModificar && !_guardando;

    return RisegTarjeta(
      titulo: 'Término',
      nota: terminado
          // EN UN TERMINADO LA FECHA ES UN HECHO, no un plan: no se «programa» algo que
          // ya pasó, así que aquí no se ofrece cambiarla.
          ? 'El servicio ya terminó. Para volver a operarlo, reactívalo desde '
                '«Cambiar estatus».'
          : 'Cuándo deja de operar. Para registrar un término que YA ocurrió se usa '
                '«Cambiar estatus».',
      hijo: RisegDatoEnLinea(
        etiqueta: 'Fecha de término',
        valor: termino == null ? null : 'Termina el ${fechaDeNegocioCorta(termino)}',
        vacioDice: 'Sin fecha de término',
        alFinal: !puedeCambiar || terminado
            ? null
            // ⚠️ **UN SOLO BOTÓN CUANDO YA HAY TÉRMINO**, pedido por el dueño el 11 de
            // noviembre de 2026: «cambia la fecha o la quita **en un paso**». Antes eran
            // dos —«Cambiar» y «Retirar»— y el caso real es uno: el contrato se renovó, y
            // lo que se sabe es la fecha nueva o que ya no hay.
            : RisegButton(
                label: termino == null ? 'Programar' : 'Renovar / extender',
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                icon: termino == null ? null : Icons.event_repeat_outlined,
                onPressed: termino == null
                    ? _programarTermino
                    : _renovarOExtender,
              ),
      ),
    );
  }

  /// Quién RESPONDE por el servicio.
  ///
  /// 🚫 **No es personal asignado al servicio.** La asignación de personal lleva ZONA —lo
  /// dice la 0046—, así que esto nombra a quien responde, no a quien trabaja ahí.
  Widget _tarjetaDelSupervisor() {
    final colors = context.colors;
    final s = _supervisor;
    final puedeEscribir = widget.capacidades.puedeModificar && !_guardando;

    // HACEN FALTA LAS DOS COSAS, y son de dos módulos: escribir el vínculo es de
    // Comercial y elegir a quién obliga a leer Personal.
    final seOfreceElegir = puedeEscribir && widget.puedeElegirSupervisor;

    return RisegTarjeta(
      titulo: 'Supervisor responsable',
      nota: puedeEscribir && !widget.puedeElegirSupervisor
          // SE DICE POR QUÉ NO SE OFRECE, en vez de enseñar un hueco sin explicación.
          ? 'Para elegir un supervisor hace falta permiso de lectura en Personal: '
                'la lista de empleados es de ese módulo.'
          : 'Quién responde por este servicio. Puede ser cualquier empleado activo.',
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RisegDatoEnLinea(
            etiqueta: 'Supervisor',
            valor: s == null
                ? null
                : '${s.nombreCompleto} · empleado ${s.numeroDeEmpleado}',
            vacioDice: 'Sin supervisor asignado',
            alFinal: Wrap(
              spacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // ⚠️ **LA INSIGNIA «BAJA», que es la razón de que esta ruta devuelva
                // `isActive`.** Un supervisor que deja de estar activo NO se desvincula
                // solo —decisión del dueño—, así que la ficha tiene que poder decir que
                // esa persona ya no está en vez de enseñar un nombre que parece vigente.
                if (s != null && !s.estaActivo)
                  const RisegStatusBadge(
                    label: 'Baja',
                    tone: RisegStatusTone.warning,
                    icon: Icons.person_off_outlined,
                  ),
                if (seOfreceElegir)
                  RisegButton(
                    label: s == null ? 'Asignar' : 'Cambiar',
                    variant: RisegButtonVariant.secondary,
                    size: RisegButtonSize.compact,
                    icon: s == null ? Icons.person_add_alt : null,
                    onPressed: _elegirSupervisor,
                  ),
                if (s != null && puedeEscribir)
                  RisegButton(
                    label: 'Quitar',
                    variant: RisegButtonVariant.secondary,
                    size: RisegButtonSize.compact,
                    onPressed: _quitarSupervisor,
                  ),
              ],
            ),
          ),
          if (s != null && !s.estaActivo) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Esta persona ya no está activa en la empresa. El servicio conserva '
              'la referencia —no se borra sola— pero conviene nombrar a otra.',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaDeLosVinculos(Servicio s) => RisegTarjeta(
    titulo: 'Asignaciones',
    // LA LETRA CHICA, UNA VEZ POR TARJETA Y EN UNA LÍNEA. Tenía tres frases —cuándo se
    // guardan, cuándo piden motivo y qué es la sucursal propia—, y el dueño lo marcó el
    // 12 de noviembre de 2026: lo que no cabe en una línea no se lee. Lo que cada fila
    // hace al pulsarla ya lo dice su propio diálogo.
    nota: 'Se guardan al momento, cada una por su lado.',
    hijo: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Vinculo(
          etiqueta: 'Razón social',
          valor: switch (s.entidadFiscalId) {
            final id? =>
              _entidades
                  .where((e) => e.id == id)
                  .map((e) => e.razonSocial)
                  .firstOrNull ??
                  'Asignada',
            null => null,
          },
          puedeCambiar: widget.capacidades.puedeModificar && !_guardando,
          hayDeDonde: _entidades.isNotEmpty,
          vacioDice: 'Este cliente todavía no tiene razones sociales.',
          onCambiar: _cambiarEntidadFiscal,
          onQuitar: s.entidadFiscalId == null ? null : _quitarEntidadFiscal,
        ),
        _Vinculo(
          etiqueta: 'Contacto responsable',
          valor: switch (s.contactoResponsableId) {
            final id? =>
              _contactos
                  .where((c) => c.id == id)
                  .map((c) => c.nombre)
                  .firstOrNull ??
                  'Asignado',
            null => null,
          },
          puedeCambiar: widget.capacidades.puedeModificar && !_guardando,
          hayDeDonde: _contactos.isNotEmpty,
          vacioDice: 'Este cliente todavía no tiene contactos.',
          onCambiar: _cambiarContacto,
          onQuitar: s.contactoResponsableId == null ? null : _quitarContacto,
        ),
        _Vinculo(
          // 🚫 LA FRONTERA, DICHA EN LA PANTALLA: `Branch` es destino administrativo y
          // `Service` el operativo. Dónde se presta es el domicilio de la otra pestaña.
          // La etiqueta se dejó corta a propósito —«Sucursal propia que lo administra»
          // partía en dos renglones la columna de etiquetas— y la frontera se dice en la
          // nota de la tarjeta, que se lee una vez.
          etiqueta: 'Sucursal propia',
          valor: switch (s.sucursalAdministrativaId) {
            final id? =>
              _sucursales
                  .where((b) => b.id == id)
                  .map((b) => b.nombre)
                  .firstOrNull ??
                  'Asignada',
            null => null,
          },
          puedeCambiar: widget.capacidades.puedeModificar && !_guardando,
          hayDeDonde: _sucursales.isNotEmpty,
          vacioDice: 'La empresa todavía no tiene sucursales.',
          onCambiar: _cambiarSucursal,
          onQuitar: s.sucursalAdministrativaId == null ? null : _quitarSucursal,
        ),
      ],
    ),
  );

  // =========================================================================
  // Guardar
  // =========================================================================

  /// Guarda lo que cambió, **y nada más**.
  ///
  /// El motivo se pide **antes** de mandar nada, por lo mismo que el servidor lo valida
  /// primero: no es un campo del formulario, es la condición para corregir.
  Future<void> _guardar() async {
    final s = _servicio;
    if (s == null) return;

    final nombre = _nombre.text.trim();

    final cambioElNombre = nombre != s.nombre;
    final cambioElTipo = _tipoId != null && _tipoId != s.tipoId;
    final cambiaronLasObservaciones = _observacionesEscritas != s.observaciones;

    final cambioElServicio =
        cambioElNombre || cambioElTipo || cambiaronLasObservaciones;
    final cambioElDomicilio = !_domicilio.igualA(_domicilioCargado);

    // ⚠️ **LO QUE FALTA, COMPLETO Y EN SU CAMPO** (11 de noviembre de 2026). Antes sólo
    // se podía señalar el nombre, y los seis campos del domicilio se descubrían de uno en
    // uno: el servidor contesta **el primero que falta y para**.
    //
    // ⚠️ **EL DOMICILIO SE MIRA SÓLO SI CAMBIÓ**, y no es pereza: el que vino del
    // servidor ya pasó por sus reglas, pero una fila vieja —traída del escritorio— podría
    // no cumplirlas, y entonces corregir el NOMBRE se quedaría bloqueado por un código
    // postal que nadie tocó. Lo que se valida es lo que se va a mandar.
    final faltantes = <String, String>{
      if (nombre.isEmpty) 'name': 'Falta el nombre del servicio.',
      if (cambioElDomicilio) ..._domicilio.faltantesSiendoObligatorio,
    };

    if (faltantes.isNotEmpty) {
      setState(() {
        _faltantes = faltantes;
        // ⚠️ **LA PESTAÑA SE MUEVE AL ERROR, y sin esto el estilo B estrenaría un fallo
        // propio:** con el domicilio en su pestaña, señalar la colonia vacía mientras se
        // mira «General» pintaría el error **donde nadie está mirando**, y «Guardar»
        // parecería no hacer nada.
        _pestana = _pestanaDeLosErrores(faltantes);
      });
      _focos.llevarLaVistaAlPrimerError(faltantes);

      return;
    }

    // NADA QUE GUARDAR NO ES UN ERROR: se vuelve a la consulta, que es lo que esa
    // persona quería. Mandar el `PATCH` igual respondería «No hay nada que modificar».
    if (!cambioElServicio && !cambioElDomicilio) {
      widget.alIrADentro(null);

      return;
    }

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Corregir el servicio',
      etiquetaMotivo: 'Motivo de la corrección',
      confirmarLabel: 'Guardar',
      cancelarLabel: 'Seguir editando',
      errorMotivoRequerido:
          'Falta el motivo. Queda en la bitácora y es lo que explica por qué '
          'cambió este dato.',
    );

    if (motivo == null || !mounted) return;

    setState(() {
      _guardando = true;
      _faltantes = const {};
    });

    // ⚠️ **EL SERVICIO PRIMERO Y EL DOMICILIO DESPUÉS**, y el orden importa: si falla el
    // primero no se ha tocado nada, y si falla el segundo lo que quedó guardado es una
    // corrección con su motivo en la auditoría — algo que se puede leer y rehacer.
    var guardadoElServicio = false;

    if (cambioElServicio) {
      final resultado = await widget.repositorio.corregir(
        empresaId: widget.empresaId,
        servicioId: s.id,
        motivo: motivo,
        // CADA CAMPO VIAJA SÓLO SI CAMBIÓ: mandando los tres «porque están ahí», un
        // cambio de nombre arrastraría unas observaciones que nadie tocó — y el evento
        // de la auditoría diría que también cambiaron.
        nombre: cambioElNombre ? nombre : null,
        tipoId: cambioElTipo ? _tipoId : null,
        observaciones: cambiaronLasObservaciones ? _observacionesEscritas : null,
      );

      if (!mounted) return;

      final fallo = resultado.when<Failure?>(
        ok: (actualizado) {
          _servicio = actualizado;
          guardadoElServicio = true;

          return null;
        },
        failure: (f) => f,
      );

      if (fallo != null) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, fallo);

        return;
      }
    }

    if (cambioElDomicilio) {
      final direccion = _domicilio.direccion;

      // VACIARLO NO SE MANDA: el servidor no puede borrarlo —no hay `DELETE` y su `PUT`
      // exige los seis obligatorios— y contestaría «Falta la calle.», que es cierto y no
      // explica qué pasa. Se dice aquí.
      if (direccion == null) {
        setState(() => _guardando = false);

        RisegFeedback.showError(
          context,
          guardadoElServicio
              ? 'Se guardaron los datos del servicio. El domicilio operativo no se '
                    'puede quitar: corrígelo o vuelve a escribirlo como estaba.'
              : 'El domicilio operativo no se puede quitar: corrígelo o vuelve a '
                    'escribirlo como estaba.',
        );

        return;
      }

      final resultado = await widget.repositorio.guardarDomicilio(
        empresaId: widget.empresaId,
        servicioId: s.id,
        domicilio: direccion,
      );

      if (!mounted) return;

      final fallo = resultado.when<Failure?>(
        ok: (d) {
          _domicilioCargado = d;

          return null;
        },
        failure: (f) => f,
      );

      if (fallo != null) {
        setState(() => _guardando = false);

        // SE DICE QUÉ SÍ QUEDÓ GUARDADO. Sin eso, quien lea «Falta la colonia.» pensaría
        // que no se guardó nada y volvería a escribir el nombre. Y no se intenta
        // deshacer: deshacer una corrección es otra corrección, con su motivo.
        RisegFeedback.showError(
          context,
          guardadoElServicio
              ? 'Se guardaron los datos del servicio, pero el domicilio no: '
                    '${MensajesHumanos.deMutacion(fallo)}'
              : MensajesHumanos.deMutacion(fallo),
        );

        return;
      }
    }

    if (!mounted) return;

    // ⚠️ **LA GUARDIA SE APAGA ANTES DE NAVEGAR:** `alIrADentro` pasa por el `onExit` de
    // la ruta, así que apagarla después dejaría salir la pregunta con el formulario ya
    // guardado —y la pantalla se quedaría en la edición—.
    setState(() {
      _guardando = false;
      _yaSeGuardo = true;
    });

    RisegFeedback.showSuccess(context, 'Se guardó el expediente del servicio.');
    widget.alIrADentro(null);
  }

  // =========================================================================
  // El estatus y el término
  // =========================================================================

  Future<void> _cambiarEstatus() async {
    final s = _servicio;
    if (s == null) return;

    final elegido = await showDialog<EstatusDeServicio>(
      context: context,
      builder: (_) => _DialogoDeEstatus(actual: s.estado),
    );

    if (elegido == null || !mounted) return;

    // ⚠️ **TERMINAR EXIGE DECIDIR LA FECHA**, y reactivar un terminado también: el
    // servidor responde `fecha_de_termino_requerida` si no llega. Se pregunta aquí en
    // lugar de dejar que el guardado falle.
    DiaDeNegocio? termino;
    var retirar = false;

    if (elegido == EstatusDeServicio.terminado) {
      final elegida = await _pedirLaFechaDeTermino(
        titulo: 'Terminar el servicio',
        ayuda:
            'Desde cuándo deja de operar. Puede ser hoy o una fecha pasada: lo que '
            'no se admite es programar un término en el futuro desde aquí.',
        propuesta: DiaDeNegocio.hoy().comoFechaLocal,
      );

      if (elegida == null || !mounted) return;
      termino = DiaDeNegocio.deFechaLocal(elegida);
    } else if (s.estado?.esFinalizado ?? false) {
      // REACTIVAR UN TERMINADO DEJA UNA FECHA DE TÉRMINO QUE YA NO APLICA, así que hay
      // que decidir qué pasa con ella. Se retira, que es lo que significa reactivar.
      retirar = s.termino != null;
    }

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Cambiar el estatus a ${elegido.nombre}',
      etiquetaMotivo: 'Motivo del cambio',
      confirmarLabel: 'Cambiar el estatus',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. Queda en la bitácora con el estatus anterior y el nuevo.',
      advertencia: elegido == EstatusDeServicio.terminado
          ? 'Un servicio terminado no se puede suspender después. Para volver a '
                'operarlo hay que reactivarlo.'
          : null,
    );

    if (motivo == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.cambiarEstado(
      empresaId: widget.empresaId,
      servicioId: s.id,
      estatus: elegido,
      motivo: motivo,
      termino: termino,
      retirarTermino: retirar,
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(
          context,
          'El servicio quedó en ${elegido.nombre.toLowerCase()}.',
        );
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  /// **Renovar o extender: mueve la fecha de término, o la quita, en un paso.**
  ///
  /// Pedido por el dueño el 11 de noviembre de 2026. El caso real es uno —el contrato se
  /// renovó— y lo que se sabe es **la fecha nueva** o **que ya no hay fecha**, así que las
  /// dos salidas viven en el mismo diálogo en vez de en dos botones que obligan a decidir
  /// cuál se parece más a lo que pasó.
  ///
  /// 🚫 **NO TOCA PRECIOS, y el diálogo lo dice.** Renovar con precios nuevos es otra
  /// cosa: necesita las condiciones comerciales y el contrato, y está comprometido como
  /// `CP-23`. Un botón llamado «Renovar» que moviera la fecha y dejara los precios viejos
  /// **en silencio** facturaría el periodo nuevo al precio anterior.
  Future<void> _renovarOExtender() async {
    final s = _servicio;
    if (s == null) return;

    final decision = await showDialog<_Renovacion>(
      context: context,
      builder: (_) => _DialogoDeRenovacion(
        actual: s.termino!.comoFechaLocal,
        desde: widget.hoy().comoFechaLocal,
      ),
    );

    if (decision == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = decision.fecha == null
        ? await widget.repositorio.retirarTerminoProgramado(
            empresaId: widget.empresaId,
            servicioId: s.id,
          )
        : await widget.repositorio.programarTermino(
            empresaId: widget.empresaId,
            servicioId: s.id,
            termino: DiaDeNegocio.deFechaLocal(decision.fecha!),
          );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(
          context,
          decision.fecha == null
              ? 'Se quitó la fecha de término.'
              : 'Se movió la fecha de término.',
        );
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<void> _programarTermino() async {
    final s = _servicio;
    if (s == null) return;

    final elegida = await _pedirLaFechaDeTermino(
      titulo: 'Programar el término',
      // ⚠️ LA REGLA, DICHA ANTES DE QUE EL SERVIDOR LA APLIQUE: una fecha pasada se
      // rechaza SIEMPRE aquí, esté el servicio activo o suspendido. Para registrar un
      // término que ya ocurrió está «Terminar», con su fecha.
      ayuda:
          'Hoy o después. Para registrar un término que YA ocurrió, usa «Terminar» '
          'con su fecha: programar es comprometerse a futuro.',
      propuesta: s.termino?.comoFechaLocal ?? DiaDeNegocio.hoy().comoFechaLocal,
      desde: DiaDeNegocio.hoy().comoFechaLocal,
    );

    if (elegida == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.programarTermino(
      empresaId: widget.empresaId,
      servicioId: s.id,
      termino: DiaDeNegocio.deFechaLocal(elegida),
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, 'Se programó el término.');
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<DateTime?> _pedirLaFechaDeTermino({
    required String titulo,
    required String ayuda,
    required DateTime propuesta,
    DateTime? desde,
  }) => showDialog<DateTime>(
    context: context,
    builder: (_) => _DialogoDeFecha(
      titulo: titulo,
      ayuda: ayuda,
      propuesta: propuesta,
      desde: desde,
    ),
  );

  // =========================================================================
  // El supervisor
  // =========================================================================

  Future<void> _elegirSupervisor() async {
    final s = _servicio;
    if (s == null) return;

    final elegido = await showDialog<EmpleadoElegible>(
      context: context,
      builder: (_) => _DialogoDeSupervisor(
        empleados: widget.empleados,
        empresaId: widget.empresaId,
      ),
    );

    if (elegido == null || !mounted) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.asignarSupervisor(
      empresaId: widget.empresaId,
      servicioId: s.id,
      empleadoId: elegido.id,
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          // SE PINTA LO ELEGIDO SIN VOLVER A PREGUNTAR: el empleado venía de una lista
          // de ACTIVOS, así que su insignia es la que acaba de verse en el selector.
          _supervisor = SupervisorDelServicio(
            empleadoId: elegido.id,
            numeroDeEmpleado: elegido.numero,
            nombreCompleto: elegido.nombreCompleto,
            estaActivo: elegido.estaActivo,
          );
          _guardando = false;
        });

        RisegFeedback.showSuccess(
          context,
          '${elegido.nombreCompleto} responde por este servicio.',
        );
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  Future<void> _quitarSupervisor() async {
    final s = _servicio;
    if (s == null) return;

    setState(() => _guardando = true);

    final resultado = await widget.repositorio.quitarSupervisor(
      empresaId: widget.empresaId,
      servicioId: s.id,
    );

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _supervisor = null;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, 'El servicio quedó sin supervisor.');
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  // =========================================================================
  // Los tres vínculos
  // =========================================================================

  Future<void> _cambiarEntidadFiscal() async {
    final s = _servicio;
    if (s == null) return;

    final elegida = await _elegirDeUnaLista(
      titulo: 'Razón social',
      opciones: [
        for (final e in _entidades)
          (valor: e.id, etiqueta: '${e.razonSocial} · ${e.rfc ?? 'sin RFC'}'),
      ],
      actual: s.entidadFiscalId,
    );

    if (elegida == null || !mounted) return;

    // ⚠️ **EL MOTIVO ES CONDICIONAL Y LO DECIDE LA MISMA REGLA QUE EL SERVIDOR (R9):**
    // la PRIMERA asignación no lo pide y cambiarla sí. Preguntarlo siempre pediría algo
    // que el servidor no exige; no preguntarlo nunca fallaría al cambiar.
    String? motivo;

    if (s.entidadFiscalId != null) {
      motivo = await mostrarDialogoMotivo(
        context,
        titulo: 'Cambiar la razón social',
        etiquetaMotivo: 'Motivo del cambio',
        confirmarLabel: 'Cambiar',
        cancelarLabel: 'Cancelar',
        errorMotivoRequerido:
            'Falta el motivo. Cambia a quién se le factura este servicio.',
      );

      if (motivo == null || !mounted) return;
    }

    await _aplicar(
      widget.repositorio.asignarEntidadFiscal(
        empresaId: widget.empresaId,
        servicioId: s.id,
        entidadFiscalId: elegida,
        motivo: motivo,
      ),
      exito: 'Se asignó la razón social.',
    );
  }

  Future<void> _quitarEntidadFiscal() async {
    final s = _servicio;
    if (s == null) return;

    final motivo = await mostrarDialogoMotivo(
      context,
      titulo: 'Quitar la razón social',
      etiquetaMotivo: 'Motivo',
      confirmarLabel: 'Quitar',
      cancelarLabel: 'Cancelar',
      errorMotivoRequerido:
          'Falta el motivo. Quita a quién se le factura este servicio.',
    );

    if (motivo == null || !mounted) return;

    await _aplicar(
      widget.repositorio.quitarEntidadFiscal(
        empresaId: widget.empresaId,
        servicioId: s.id,
        motivo: motivo,
      ),
      exito: 'Se quitó la razón social.',
    );
  }

  Future<void> _cambiarContacto() async {
    final s = _servicio;
    if (s == null) return;

    final elegido = await _elegirDeUnaLista(
      titulo: 'Contacto responsable',
      opciones: [
        for (final c in _contactos) (valor: c.id, etiqueta: c.nombre),
      ],
      actual: s.contactoResponsableId,
    );

    if (elegido == null || !mounted) return;

    await _aplicar(
      widget.repositorio.asignarContactoResponsable(
        empresaId: widget.empresaId,
        servicioId: s.id,
        contactoId: elegido,
      ),
      exito: 'Se asignó el contacto responsable.',
    );
  }

  Future<void> _quitarContacto() async {
    final s = _servicio;
    if (s == null) return;

    await _aplicar(
      widget.repositorio.quitarContactoResponsable(
        empresaId: widget.empresaId,
        servicioId: s.id,
      ),
      exito: 'Se quitó el contacto responsable.',
    );
  }

  Future<void> _cambiarSucursal() async {
    final s = _servicio;
    if (s == null) return;

    final elegida = await _elegirDeUnaLista(
      titulo: 'Sucursal administrativa',
      opciones: [
        // SÓLO LAS ACTIVAS SE OFRECEN, y la que ya está se conserva aunque no lo esté:
        // la misma regla que el tipo de servicio retirado.
        for (final b in _sucursales)
          if (b.activa || b.id == s.sucursalAdministrativaId)
            (
              valor: b.id,
              etiqueta: b.activa ? b.nombre : '${b.nombre} (inactiva)',
            ),
      ],
      actual: s.sucursalAdministrativaId,
    );

    if (elegida == null || !mounted) return;

    await _aplicar(
      widget.repositorio.asignarSucursalAdministrativa(
        empresaId: widget.empresaId,
        servicioId: s.id,
        sucursalId: elegida,
      ),
      exito: 'Se asignó la sucursal administrativa.',
    );
  }

  Future<void> _quitarSucursal() async {
    final s = _servicio;
    if (s == null) return;

    await _aplicar(
      widget.repositorio.quitarSucursalAdministrativa(
        empresaId: widget.empresaId,
        servicioId: s.id,
      ),
      exito: 'Se quitó la sucursal administrativa.',
    );
  }

  /// Un diálogo que elige **uno** de una lista, o nulo si se cancela.
  Future<String?> _elegirDeUnaLista({
    required String titulo,
    required List<({String valor, String etiqueta})> opciones,
    required String? actual,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        _DialogoDeLista(titulo: titulo, opciones: opciones, actual: actual),
  );

  /// Manda una mutación del servicio y refleja lo que devolvió. **Las seis rutas de
  /// vínculo devuelven el servicio entero**, así que su lectura también es una.
  Future<void> _aplicar(
    Future<Result<Servicio>> peticion, {
    required String exito,
  }) async {
    setState(() => _guardando = true);

    final resultado = await peticion;

    if (!mounted) return;

    resultado.when(
      ok: (actualizado) {
        setState(() {
          _servicio = actualizado;
          _guardando = false;
        });

        RisegFeedback.showSuccess(context, exito);
      },
      failure: (f) {
        setState(() => _guardando = false);
        mostrarRechazoDelServidor(context, f);
      },
    );
  }
}

// ===========================================================================
// Las piezas de la ficha
// ===========================================================================

class _Volver extends StatelessWidget {
  const _Volver({required this.onVolver});

  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onVolver,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back, size: 18, color: colors.textMuted),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Servicios',
              style: AppTypography.body.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una fila de vínculo: qué está asignado y los dos botones.
///
/// ⚠️ **NO LLEVA SU PROPIA LETRA CHICA**, y es una de las cuatro cosas que el dueño pidió
/// arreglar el 11 de noviembre de 2026: había una nota debajo de cada una de las tres
/// filas, y tres notas seguidas no se leen. Lo que explica las tres va **una vez** en la
/// tarjeta que las contiene. Lo único que sigue aquí es [vacioDice], que **no es ayuda**:
/// es la razón por la que esta fila no tiene botón.
class _Vinculo extends StatelessWidget {
  const _Vinculo({
    required this.etiqueta,
    required this.valor,
    required this.puedeCambiar,
    required this.hayDeDonde,
    required this.vacioDice,
    required this.onCambiar,
    required this.onQuitar,
  });

  final String etiqueta;

  /// Lo asignado, o nulo si no hay nada.
  final String? valor;

  final bool puedeCambiar;

  /// Si hay de dónde elegir. **Sin opciones no se ofrece el botón**: abriría una lista
  /// vacía, que parece un error del producto y no la consecuencia de que el cliente
  /// todavía no tenga contactos.
  final bool hayDeDonde;

  final String vacioDice;
  final VoidCallback onCambiar;
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RisegDatoEnLinea(
          etiqueta: etiqueta,
          valor: valor,
          vacioDice: 'Sin asignar',
          alFinal: !puedeCambiar
              ? null
              : Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    if (hayDeDonde)
                      RisegButton(
                        label: valor == null ? 'Asignar' : 'Cambiar',
                        variant: RisegButtonVariant.secondary,
                        size: RisegButtonSize.compact,
                        onPressed: onCambiar,
                      ),
                    if (onQuitar != null)
                      RisegButton(
                        label: 'Quitar',
                        variant: RisegButtonVariant.secondary,
                        size: RisegButtonSize.compact,
                        onPressed: onQuitar,
                      ),
                  ],
                ),
        ),
        // SÓLO CUANDO NO HAY DE DÓNDE ELEGIR, y entonces no es letra chica: es la razón
        // por la que esta fila no tiene botón. Sin ella, el hueco parecería un defecto.
        if (!hayDeDonde)
          Padding(
            padding: const EdgeInsets.only(left: 210, bottom: AppSpacing.xs),
            child: Text(
              vacioDice,
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// Los diálogos
// ===========================================================================

class _DialogoDeEstatus extends StatelessWidget {
  const _DialogoDeEstatus({required this.actual});

  final EstatusDeServicio? actual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final terminado = actual?.esFinalizado ?? false;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: const Text('Cambiar el estatus', style: AppTypography.heading2),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in EstatusDeServicio.values)
            // 🚫 **TERMINADO → SUSPENDIDO ESTÁ PROHIBIDO** y el servidor responde 409.
            // La celda prohibida no se ofrece: un botón que siempre falla es peor que
            // su ausencia, y aquí además confundiría «suspender» con «reactivar».
            if (e != actual && !(terminado && e == EstatusDeServicio.suspendido))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  terminado && e == EstatusDeServicio.activo
                      ? 'Reactivar'
                      : e.nombre,
                ),
                subtitle: Text(
                  switch (e) {
                    EstatusDeServicio.activo when terminado =>
                      'Vuelve a operar y se retira su fecha de término.',
                    EstatusDeServicio.activo => 'Vuelve a operar.',
                    EstatusDeServicio.suspendido =>
                      'Deja de operar temporalmente. Se puede reactivar.',
                    EstatusDeServicio.terminado =>
                      'Deja de operar. Pide la fecha desde cuándo.',
                  },
                  style: AppTypography.caption.copyWith(color: colors.textMuted),
                ),
                onTap: () => Navigator.of(context).pop(e),
              ),
        ],
      ),
      actions: [
        RisegButton(
          label: 'Cancelar',
          variant: RisegButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _DialogoDeFecha extends StatefulWidget {
  const _DialogoDeFecha({
    required this.titulo,
    required this.ayuda,
    required this.propuesta,
    this.desde,
  });

  final String titulo;
  final String ayuda;
  final DateTime propuesta;

  /// La primera fecha admitida. **Programar un término no acepta el pasado**, y el
  /// selector lo impone en lugar de dejar que el servidor conteste 422.
  final DateTime? desde;

  @override
  State<_DialogoDeFecha> createState() => _DialogoDeFechaState();
}

class _DialogoDeFechaState extends State<_DialogoDeFecha> {
  late DateTime? _fecha = widget.propuesta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: Text(widget.titulo, style: AppTypography.heading2),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: 'Fecha',
              value: _fecha,
              firstDate: widget.desde,
              helperText: widget.ayuda,
              onChanged: (v) => setState(() => _fecha = v),
            ),
          ],
        ),
      ),
      actions: [
        RisegButton(
          label: 'Cancelar',
          variant: RisegButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RisegButton(
          label: 'Confirmar',
          onPressed: _fecha == null
              ? null
              : () => Navigator.of(context).pop(_fecha),
        ),
      ],
    );
  }
}

/// Lo que se decidió en el diálogo de renovación: **una fecha nueva, o ninguna**.
///
/// Es una clase y no un `DateTime?` porque **nulo ya significa «canceló»** en el
/// resultado de un diálogo: sin esto, «quitar la fecha» y «me arrepentí» llegarían como
/// el mismo valor y la pantalla no podría distinguirlos.
@immutable
class _Renovacion {
  const _Renovacion(this.fecha);

  /// La fecha nueva, o **nulo para quitar el término**.
  final DateTime? fecha;
}

/// **Renovar o extender: mover la fecha de término, o quitarla, en un paso.**
///
/// 🚫 **NO TOCA PRECIOS Y LO DICE.** Renovar con precios nuevos necesita las condiciones
/// comerciales y el contrato —está comprometido como `CP-23`—, y un diálogo llamado
/// «Renovar» que moviera la fecha dejando los precios viejos **en silencio** facturaría
/// el periodo nuevo al precio anterior.
class _DialogoDeRenovacion extends StatefulWidget {
  const _DialogoDeRenovacion({required this.actual, required this.desde});

  final DateTime actual;

  /// La primera fecha admitida: **hoy**. Mover un término al pasado lo rechaza el
  /// servidor con un 422, así que el selector no lo ofrece.
  final DateTime desde;

  @override
  State<_DialogoDeRenovacion> createState() => _DialogoDeRenovacionState();
}

class _DialogoDeRenovacionState extends State<_DialogoDeRenovacion> {
  late DateTime? _fecha = widget.actual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: const Text('Renovar / extender', style: AppTypography.heading2),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RisegDateField(
              label: 'Nueva fecha de término',
              value: _fecha,
              firstDate: widget.desde,
              helperText: 'Hoy o después.',
              onChanged: (v) => setState(() => _fecha = v),
            ),
            const SizedBox(height: AppSpacing.md),
            // LO QUE ESTO NO HACE, DICHO AQUÍ: mover la fecha no renegocia nada.
            Text(
              'Mueve la fecha de término. No cambia los precios ni las condiciones '
              'comerciales del servicio.',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        RisegButton(
          label: 'Cancelar',
          variant: RisegButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        // LA OTRA SALIDA DEL MISMO PASO: el contrato se renovó sin fecha de fin.
        RisegButton(
          label: 'Quitar la fecha',
          variant: RisegButtonVariant.secondary,
          onPressed: () =>
              Navigator.of(context).pop(const _Renovacion(null)),
        ),
        RisegButton(
          label: 'Guardar',
          onPressed: _fecha == null
              ? null
              : () => Navigator.of(context).pop(_Renovacion(_fecha)),
        ),
      ],
    );
  }
}

/// Elige **uno** de una lista corta.
class _DialogoDeLista extends StatefulWidget {
  const _DialogoDeLista({
    required this.titulo,
    required this.opciones,
    required this.actual,
  });

  final String titulo;
  final List<({String valor, String etiqueta})> opciones;
  final String? actual;

  @override
  State<_DialogoDeLista> createState() => _DialogoDeListaState();
}

class _DialogoDeListaState extends State<_DialogoDeLista> {
  /// Lo marcado **todavía no es lo elegido**: se confirma con «Asignar».
  late String? _marcada = widget.actual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: Text(widget.titulo, style: AppTypography.heading2),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final o in widget.opciones)
              RisegOpcion(
                titulo: o.etiqueta,
                marcada: o.valor == _marcada,
                alPulsar: () => setState(() => _marcada = o.valor),
              ),
          ],
        ),
      ),
      actions: [
        RisegButton(
          label: 'Cancelar',
          variant: RisegButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        // ⚠️ **ELEGIR NO ES DECIDIR, y antes lo era:** un clic en la fila asignaba y
        // cerraba. El dueño lo pidió el 12 de noviembre de 2026 — la fila marca y el
        // botón decide, así que se puede mirar sin comprometerse.
        RisegButton(
          label: 'Asignar',
          // SIN NADA MARCADO, APAGADO: un botón que no hace nada al pulsarlo enseña que
          // los botones no hacen nada.
          onPressed: _marcada == null || _marcada == widget.actual
              ? null
              : () => Navigator.of(context).pop(_marcada),
        ),
      ],
    );
  }
}

/// Elige al supervisor **buscando en el servidor**.
///
/// ⚠️ **No se filtra en la pantalla.** `GET /employees` pagina por cursor, así que filtrar
/// una página no es filtrar la plantilla: una empresa con trescientos empleados traería
/// los primeros cincuenta y «buscar» entre ellos encontraría a quien cupo, no a quien se
/// busca. El texto va al servidor.
class _DialogoDeSupervisor extends StatefulWidget {
  const _DialogoDeSupervisor({
    required this.empleados,
    required this.empresaId,
  });

  final EmpleadosRepositorioHttp empleados;
  final String empresaId;

  @override
  State<_DialogoDeSupervisor> createState() => _DialogoDeSupervisorState();
}

class _DialogoDeSupervisorState extends State<_DialogoDeSupervisor> {
  final _buscador = TextEditingController();

  /// Quién está marcado. **Todavía no es el supervisor**: eso lo decide «Asignar».
  EmpleadoElegible? _marcado;

  List<EmpleadoElegible>? _empleados;
  Failure? _fallo;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.empleados.activos(
      widget.empresaId,
      texto: _buscador.text,
    );

    if (!mounted) return;

    resultado.when(
      ok: (e) => setState(() {
        _empleados = e;
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

    return AlertDialog(
      backgroundColor: colors.surfaceSunken,
      title: const Text('Elegir supervisor', style: AppTypography.heading2),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: RisegTextField(
                    label: 'Buscar',
                    controller: _buscador,
                    helperText: 'Por nombre o número de empleado.',
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                RisegButton(
                  label: 'Buscar',
                  variant: RisegButtonVariant.secondary,
                  size: RisegButtonSize.compact,
                  onPressed: _cargando ? null : _buscar,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _cuerpo()),
          ],
        ),
      ),
      actions: [
        RisegButton(
          label: 'Cancelar',
          variant: RisegButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RisegButton(
          label: 'Asignar',
          onPressed: _marcado == null
              ? null
              : () => Navigator.of(context).pop(_marcado),
        ),
      ],
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_fallo case final f?) {
      return RisegEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los empleados',
        message: f.message,
        primaryAction: RisegButton(
          label: 'Intentar de nuevo',
          onPressed: _buscar,
        ),
      );
    }

    final empleados = _empleados ?? const <EmpleadoElegible>[];

    if (empleados.isEmpty) {
      // SE DISTINGUE «NO HAY NINGUNO» DE «LA BÚSQUEDA NO ENCONTRÓ», porque son dos
      // problemas distintos y se arreglan distinto.
      return RisegEmptyState(
        icon: Icons.people_outline,
        title: _buscador.text.trim().isEmpty
            ? 'No hay empleados activos'
            : 'Nadie coincide con esa búsqueda',
        message: _buscador.text.trim().isEmpty
            ? 'Sólo un empleado activo puede responder por un servicio, y «activo» '
                  'se deriva de un periodo laboral abierto.'
            : 'Prueba con otra parte del nombre o con el número de empleado.',
      );
    }

    // EL MISMO PATRÓN QUE LA OTRA LISTA: la fila marca y «Asignar» decide.
    return ListView.builder(
      itemCount: empleados.length,
      itemBuilder: (_, i) => RisegOpcion(
        titulo: empleados[i].nombreCompleto,
        subtitulo: 'Empleado ${empleados[i].numero}',
        marcada: empleados[i].id == _marcado?.id,
        alPulsar: () => setState(() => _marcado = empleados[i]),
      ),
    );
  }
}
