import 'package:flutter/material.dart';

// LAS CAPACIDADES VIENEN DEL SHELL: esta feature no puede importar el catálogo de
// permisos —hay un guardia que lo impide— y no le hace falta.
import '../../../../app/shell/apartados_web.dart' show CapacidadesDeModulo;

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/expedientes_repositorio_http.dart';
import '../datos/sucursales_repositorio_http.dart';
import '../modelos/choque_de_expediente.dart';
import '../modelos/expediente.dart';
import '../modelos/sucursal.dart';
import '../modelos/tipo_de_sucursal.dart';
import 'dialogo_de_choque.dart';
import 'eliminar_estructura.dart';

/// **Cuanto hay de una sucursal, en un solo sitio**: nombre, tipo, domicilio, horario y
/// las tres operaciones que cambian su estado.
///
/// ## Por qué desapareció el panel
///
/// Hasta el 21 de octubre de 2026 una sucursal se editaba en **dos** sitios: un panel
/// lateral con el nombre, el tipo y el estado, y esta pantalla con el domicilio y el
/// horario. Eran dos peticiones para una sola intención —corregir el nombre y la
/// dirección—, y la segunda podía fallar dejando la primera aplicada. Ahora el toque
/// de la fila abre esto y no hay otro lugar: **nombre y tipo se guardan en la misma
/// transacción que el domicilio y el horario**, que es como el producto de escritorio
/// trata un expediente —«reúne todos los errores antes de fallar»—.
///
/// El panel sobrevive **sólo para el alta**, y no es una excepción: una sucursal que
/// todavía no existe no tiene expediente que abrir.
///
/// ## Dos familias de permisos en la misma pantalla, y cada campo con el suyo
///
/// **Nombre y tipo** son la estructura de la organización: `organizacion.modificar`.
/// **Domicilio y horario** son la configuración de la empresa:
/// `company.settings.manage`. No se juntan en «puede editar» porque no son lo mismo:
/// quien ordena el organigrama no administra necesariamente los datos fiscales de la
/// empresa.
///
/// En pantalla se aplica la regla de siempre —**lo que no puedes hacer no se
/// muestra**— en su versión de sólo lectura: los campos sin permiso se ven, con una
/// nota que dice **qué permiso falta**. Verlos no es un descuido: el expediente se
/// consulta mucho más de lo que se edita, y esconder la dirección a quien puede
/// renombrar la sucursal le quitaría el dato sin motivo. El servidor contesta 403 por
/// campo si alguien lo llama directamente.
///
/// ## El horario puede más que el del escritorio, a propósito
///
/// ## El horario puede más que el del escritorio, a propósito
///
/// Allá el horario son **siete filas fijas con un tramo cada una**, así que una
/// oficina que abre 9–14 y 16–20 no caía en el modelo. Aquí cada día admite **los
/// tramos que haga falta**, y el solape **lo impide el motor** —no un `if` de esta
/// pantalla— con una exclusión sobre la semana canónica.
///
/// **Un día cerrado es la AUSENCIA de tramos**, nunca un tramo con ceros. Por eso el
/// interruptor de «Abierto» no guarda nada por sí mismo: apagarlo quita los tramos del
/// día, y eso es exactamente lo que «cerrado» significa.
///
/// ## El 24:00 y por qué no se puede elegir «00:00» como cierre
///
/// `TimeOfDay` no puede valer 24:00, y el servidor **rechaza** un cierre de 0 con un
/// mensaje que nombra el 24:00. Así que cuando alguien elige las 00:00 como hora de
/// cierre, se guarda como 1440 —medianoche— y se muestra «24:00». No es una suposición
/// cómoda: un tramo de 22:00 a 00:00 son dos horas, y «hasta las 00:00 de pasado
/// mañana» no significa nada. La conversión vive en [TramoDeHorario.nuevo], en un solo
/// sitio.
///
/// <b>Importa `design_system_web.dart`, NUNCA el barrel completo</b>, que arrastra
/// `dart:io` y rompe la build web.
class ExpedienteSucursalWebScreen extends StatefulWidget {
  const ExpedienteSucursalWebScreen({
    required this.repositorio,
    required this.repositorioDeSucursales,
    required this.empresaId,
    required this.sucursal,
    required this.tipos,
    required this.capacidades,
    required this.esMaestro,
    required this.puedeEditarExpedientes,
    required this.onVolver,
    required this.guardia,
    this.alCambiar,
    super.key,
  });

  final ExpedientesRepositorioHttp repositorio;

  /// El de la estructura. **Hacen falta los dos** y no es un descuido: el nombre, el
  /// tipo, el domicilio y el horario se guardan por el expediente, pero cerrar,
  /// reabrir, desactivar y eliminar son **operaciones** de la estructura, cada una con
  /// su ruta, su confirmación y su evento de auditoría.
  final SucursalesRepositorioHttp repositorioDeSucursales;

  final String empresaId;

  /// La fila de la lista. **De aquí salen los dos estados que el expediente no
  /// trae** —si está activa y si está operando—, que son los que gobiernan las
  /// acciones del encabezado. El `PUT` del expediente no los devuelve porque no los
  /// cambia.
  final Sucursal sucursal;

  /// El catálogo, para el selector de tipo. **Ya filtrado por quien abre**: se
  /// ofrecen los activos más el que la sucursal tenga, aunque esté retirado — perder
  /// su tipo actual al guardar otra cosa sería un dato borrado por accidente.
  final List<TipoDeSucursal> tipos;

  /// Las cuatro de la estructura: gobiernan **nombre y tipo** y las tres acciones del
  /// encabezado.
  final CapacidadesDeModulo capacidades;

  /// Para eliminar hacen falta **las dos cosas**: el rol y además `archivar`, igual
  /// que en el servidor.
  final bool esMaestro;

  /// `company.settings.manage`: gobierna **domicilio y horario**, y nada más.
  final bool puedeEditarExpedientes;

  /// Cómo volver a la lista. **Lo decide quien abrió esta pantalla**, igual que en el
  /// catálogo de tipos: la pantalla pide y el portón convierte la petición en una
  /// dirección.
  final VoidCallback onVolver;

  /// Dónde se registra que hay trabajo sin guardar (D-56).
  ///
  /// **Se recibe y no se crea**: es uno por sesión y lo reparte el portón. Es lo que
  /// permite que la pregunta la hagan los tres sitios que pueden tirar lo escrito sin
  /// pasar por aquí — el `onExit` de la ruta, el menú de empresas de la barra y el aviso
  /// del navegador antes de recargar.
  final GuardiaDeSalida guardia;

  /// Avisa de que algo que la lista muestra cambió: el nombre, el tipo o un estado.
  ///
  /// **ANTES NO EXISTÍA Y EL COMENTARIO DECÍA QUE NO HACÍA FALTA**: «el expediente no
  /// cambia el nombre, el código, el tipo ni el estado de la sucursal». Dejó de ser
  /// verdad el día que el nombre y el tipo se mudaron aquí, y sin este aviso la lista
  /// seguiría enseñando el nombre viejo después de guardar.
  final ValueChanged<Sucursal>? alCambiar;

  @override
  State<ExpedienteSucursalWebScreen> createState() =>
      _ExpedienteSucursalWebScreenState();
}

class _ExpedienteSucursalWebScreenState
    extends State<ExpedienteSucursalWebScreen> {
  ExpedienteDeSucursal? _expediente;
  Failure? _fallo;
  bool _cargando = true;
  bool _guardando = false;
  bool _cambiandoOperativo = false;
  bool _cambiandoActiva = false;
  bool _eliminando = false;
  Map<String, String> _erroresDeCampo = const {};
  String? _errorDeNombre;

  /// Los dos estados que el expediente no trae. **Se inician de la fila que abrió la
  /// pantalla y después los dice el servidor**, nunca esta pantalla: las rutas son
  /// idempotentes y pueden devolver la fila sin cambiar, así que suponer el resultado
  /// contaría una historia falsa.
  late bool _cerrada;
  late bool _activa;

  /// El tipo que se está editando.
  String? _tipoId;

  /// El horario que se está editando. **Copia propia**, no la del expediente: así
  /// cancelar es cerrar, y nada de lo escrito se cuela al modelo cargado.
  List<TramoDeHorario> _horario = [];

  /// Los nodos de foco, **en el orden del formulario y con la clave del servidor**.
  ///
  /// El tipo de sucursal no está: es un selector y no se enfoca, así que a él se llega
  /// por su sección.
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

  /// Las dos secciones que **no se pueden enfocar**: el tipo es un selector y el
  /// horario son siete filas de interruptores. A ellas se llega por su sitio, no por
  /// el foco.
  final _claveDeDatos = GlobalKey();
  final _claveDelHorario = GlobalKey();

  final _nombre = TextEditingController();
  final _calle = TextEditingController();
  final _exterior = TextEditingController();
  final _interior = TextEditingController();
  final _colonia = TextEditingController();
  final _municipio = TextEditingController();
  final _ciudad = TextEditingController();
  final _estado = TextEditingController();
  final _cp = TextEditingController();
  final _pais = TextEditingController();
  final _referencias = TextEditingController();

  /// **SÓLO LOS DEL DOMICILIO**, y el nombre no está aquí a propósito: de esta lista
  /// sale [_hayAlgoDeDomicilio], y meter el nombre haría que una sucursal con nombre
  /// y sin dirección pareciera tener un domicilio a medio llenar.
  List<TextEditingController> get _todos => [
    _calle, _exterior, _interior, _colonia, _municipio,
    _ciudad, _estado, _cp, _pais, _referencias,
  ];

  String get _sucursalId => widget.sucursal.id;

  /// Si se pueden tocar **nombre y tipo**: la estructura.
  bool get _puedeEditarEstructura => widget.capacidades.puedeModificar;

  /// Si hay alguna operación en vuelo. Mientras la haya, nada más se pulsa: son
  /// cuatro caminos que escriben sobre la misma fila.
  bool get _ocupado =>
      _guardando || _cambiandoOperativo || _cambiandoActiva || _eliminando;

  @override
  void initState() {
    super.initState();

    _cerrada = widget.sucursal.estadoOperativo != 'operando';
    _activa = widget.sucursal.activa;

    // D-56 · SE REGISTRA AL MONTARSE Y SE LIBERA AL DESMONTARSE, como un controller.
    //
    // Lo que se registra es **un método de este estado**, no el `bool` de dentro: el
    // guardia guarda la pregunta y no la respuesta, porque el formulario se ensucia
    // minutos después de montarse.
    widget.guardia.registrar(
      _hayCambiosSinGuardar,
      queSePierde: _queSePierde,
    );

    _cargar();
  }

  @override
  void dispose() {
    // ⚠️ Y SE LIBERA CON LA MISMA FUNCIÓN con la que se registró, que es lo que
    // `GuardiaDeSalida` exige: en Flutter el `initState` de la pantalla siguiente corre
    // ANTES del `dispose` de ésta, así que soltar «el que haya» dejaría a la nueva sin
    // protección y en silencio.
    widget.guardia.liberar(_hayCambiosSinGuardar);

    // Liberar los controllers no es opcional: en este proyecto ya costó una vez.
    for (final c in [_nombre, ..._todos]) {
      c.dispose();
    }

    // Y LOS NODOS DE FOCO TAMPOCO: un `FocusNode` sin liberar deja al
    // `FocusManager` con una referencia a un widget desmontado.
    _focos.dispose();

    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final resultado = await widget.repositorio.leerDeSucursal(
      empresaId: widget.empresaId,
      sucursalId: _sucursalId,
    );

    if (!mounted) return;

    resultado.when(
      ok: (e) => setState(() {
        _volcar(e);
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = f;
        _cargando = false;
      }),
    );
  }

  /// Pone el expediente en el formulario. **Un solo sitio para los cuatro bloques**:
  /// cargar, guardar y resolver un choque acaban aquí, y repartirlo era cómo uno de
  /// los tres se olvidaba del nombre.
  ///
  /// El expediente que queda en `_expediente` es también **la base del choque**: lo
  /// que había la última vez que esta pantalla y el servidor coincidieron.
  void _volcar(ExpedienteDeSucursal e) {
    _expediente = e;
    _nombre.text = e.nombre;
    _tipoId = e.tipoId;
    _horario = [...e.horario];
    _volcarDomicilio(e.direccion);
    _erroresDeCampo = const {};
    _errorDeNombre = null;
  }

  void _volcarDomicilio(Direccion? d) {
    _calle.text = d?.calle ?? '';
    _exterior.text = d?.numeroExterior ?? '';
    _interior.text = d?.numeroInterior ?? '';
    _colonia.text = d?.colonia ?? '';
    _municipio.text = d?.municipio ?? '';
    _ciudad.text = d?.ciudad ?? '';
    _estado.text = d?.estado ?? '';
    _cp.text = d?.codigoPostal ?? '';
    _pais.text = d?.pais ?? '';
    _referencias.text = d?.referencias ?? '';
  }

  // =========================================================================
  // El horario
  // =========================================================================

  List<TramoDeHorario> _tramosDe(int dia) =>
      [for (final t in _horario) if (t.dia == dia) t]
        ..sort((a, b) => a.inicio.compareTo(b.inicio));

  /// Enciende un día: le pone **un** tramo de 9 a 18, que es el que casi siempre es.
  ///
  /// Apagarlo **quita todos** sus tramos, porque cerrado es la ausencia de tramos.
  void _cambiarDia(int dia, {required bool abierto}) {
    setState(() {
      _horario = [for (final t in _horario) if (t.dia != dia) t];

      if (abierto) {
        _horario.add(
          TramoDeHorario.nuevo(dia: dia, inicio: 9 * 60, fin: 18 * 60),
        );
      }
    });
  }

  void _agregarTramo(int dia) {
    final existentes = _tramosDe(dia);

    // EL TRAMO NUEVO EMPIEZA DONDE TERMINÓ EL ÚLTIMO, no a las 9 otra vez: así el
    // caso común —abrir, cerrar a comer, reabrir— no nace solapado, que es el único
    // estado que el motor va a rechazar.
    final desde = existentes.isEmpty
        ? 9 * 60
        : existentes.last.fin == 1440
              ? 1440
              : existentes.last.fin;

    setState(() {
      _horario.add(
        TramoDeHorario.nuevo(
          dia: dia,
          inicio: desde >= 1440 ? 0 : desde,
          fin: desde >= 1440 || desde + 120 > 1440 ? 1440 : desde + 120,
        ),
      );
    });
  }

  void _quitarTramo(TramoDeHorario tramo) {
    setState(() => _horario.remove(tramo));
  }

  void _cambiarHora(
    TramoDeHorario tramo, {
    int? inicio,
    int? fin,
  }) {
    final indice = _horario.indexOf(tramo);
    if (indice < 0) return;

    setState(() {
      _horario[indice] = TramoDeHorario.nuevo(
        dia: tramo.dia,
        inicio: inicio ?? tramo.inicio,
        fin: fin ?? tramo.fin,
      );
    });
  }

  // =========================================================================
  // Lo que se perdería al salir (D-56)
  // =========================================================================

  /// ¿Hay algo escrito que se perdería al salir?
  ///
  /// ## Por qué esto no existía, y por qué hacía falta
  ///
  /// ⚠️ **ESTA PANTALLA ERA UN FORMULARIO SIN DETECCIÓN DE CAMBIOS.** Tenía su
  /// `_compararCon`, pero ése compara **versiones del servidor** para resolver el choque
  /// de M3: responde «¿qué tocó el otro?», no «¿qué escribí yo?». Así que lo escrito aquí
  /// se perdía sin preguntar por los cuatro caminos de D-56 —**incluido cambiar de
  /// empresa**, que ya preguntaba desde E1-B para la pantalla de Empresa y aquí no tenía
  /// a quién preguntar—.
  ///
  /// ## Cómo se compara, y por qué así
  ///
  /// **Contra el expediente cargado y no contra un «se tocó algo»**: escribir una letra y
  /// borrarla no es un cambio, y preguntar por eso enseña a contestar el diálogo sin
  /// leerlo. Es la misma regla que ya usa el expediente de la empresa.
  ///
  /// **El domicilio y el horario se comparan por su FORMA FINAL**, la misma que se
  /// mandaría: comparar campo a campo repetiría aquí las reglas de «vacío del todo es
  /// nulo» y de «el fin 0 es 1440», y las dos copias acabarían discrepando.
  ///
  /// **El horario se ordena antes de comparar**, y es deliberado: en una semana el orden
  /// de los tramos no significa nada —el motor impone la exclusión sobre la semana
  /// canónica—, así que quitar un tramo y volver a ponerlo igual en otra posición no es un
  /// cambio que haya que defender.
  ///
  /// **Lo que NO cuenta:** los estados de la cabecera —cerrada, activa— no son del
  /// formulario. Cada uno es una operación que se aplica al pulsarla, con su propia
  /// confirmación, así que nunca están pendientes de guardar.
  /// ⚠️ **ES UN MÉTODO Y NO UN `get`, y la diferencia la exige el guardia.** `liberar`
  /// compara por identidad la función que se le dio, y Dart garantiza que **dos
  /// referencias al mismo método del mismo objeto son iguales** — dos lambdas `() => …`
  /// no lo son. Con una lambda, el `dispose` no soltaría nada y el registro quedaría
  /// pegado: cada navegación preguntaría por un formulario que ya no existe.
  bool _hayCambiosSinGuardar() {
    final e = _expediente;
    if (e == null) return false;

    if (_nombre.text.trim() != e.nombre) return true;
    if (_tipoId != e.tipoId) return true;

    final direccion = _direccionDelFormulario();
    if ((direccion?.aJson().toString()) != (e.direccion?.aJson().toString())) {
      return true;
    }

    return _horarioComparable(_horario) != _horarioComparable(e.horario);
  }

  /// El horario en una forma que se puede comparar: lo que se mandaría, **ordenado**.
  String _horarioComparable(List<TramoDeHorario> tramos) =>
      (tramos.map((t) => t.aJson().toString()).toList()..sort()).join('|');

  /// Cómo se llama lo que se perdería, para la pregunta del router.
  ///
  /// **El nombre GUARDADO y no el del formulario**: si alguien está renombrando la
  /// sucursal, preguntarle por el nombre a medio escribir sería nombrarle algo que
  /// todavía no existe.
  String _queSePierde() =>
      'el expediente de la sucursal '
      '${_expediente?.nombre ?? widget.sucursal.nombre}';

  // =========================================================================
  // Guardar
  // =========================================================================

  bool get _hayAlgoDeDomicilio => _todos.any((c) => c.text.trim().isNotEmpty);

  Direccion? _direccionDelFormulario() {
    if (!_hayAlgoDeDomicilio) return null;

    String? opcional(TextEditingController c) {
      final t = c.text.trim();

      return t.isEmpty ? null : t;
    }

    return Direccion(
      calle: _calle.text.trim(),
      numeroExterior: _exterior.text.trim(),
      colonia: _colonia.text.trim(),
      municipio: _municipio.text.trim(),
      estado: _estado.text.trim(),
      codigoPostal: _cp.text.trim(),
      numeroInterior: opcional(_interior),
      ciudad: opcional(_ciudad),
      pais: opcional(_pais),
      referencias: opcional(_referencias),
    );
  }

  /// Cuántas veces se ha reintentado **sin preguntar** en este guardado.
  ///
  /// Un choque que se resuelve solo —cada uno tocó campos distintos— se reintenta sin
  /// molestar a nadie, y eso abre la puerta a dar vueltas si alguien guarda sin parar.
  /// Tres intentos y después el aviso de siempre: es un tope, no una regla de negocio.
  int _reintentos = 0;

  Future<void> _guardar() async {
    final expediente = _expediente;
    if (expediente == null) return;

    final nombre = _nombre.text.trim();

    // EL NOMBRE VACÍO SE PARA AQUÍ, igual que en el panel de alta: el servidor
    // también lo rechaza, pero con el nombre en blanco no hace falta ir a preguntarlo.
    if (_puedeEditarEstructura && nombre.isEmpty) {
      setState(() => _errorDeNombre = 'Escribe un nombre.');
      // Y SE LLEVA LA VISTA, igual que con un error del servidor: el nombre está
      // arriba y el botón abajo, así que el aviso sin desplazamiento no se vería.
      _llevarLaVistaAlPrimerError();

      return;
    }

    setState(() {
      _guardando = true;
      _erroresDeCampo = const {};
      _errorDeNombre = null;
    });

    final resultado = await widget.repositorio.guardarDeSucursal(
      empresaId: widget.empresaId,
      sucursalId: _sucursalId,
      // La versión que se leyó al abrir. No se vuelve a pedir antes de guardar:
      // hacerlo leería justo el valor que acaba de cambiar la otra persona.
      version: expediente.version,
      // NULOS SI NO HAY PERMISO, QUE ES «NO LOS TOQUES». No se mandan los valores
      // cargados «porque no cambian»: el servidor compara contra la fila, y mandar
      // algo que no se puede cambiar es pedir un 403 por un campo que nadie tocó.
      nombre: _puedeEditarEstructura ? nombre : null,
      tipoId: _puedeEditarEstructura ? _tipoId : null,
      // EL DOMICILIO Y EL HORARIO SE MANDAN SIEMPRE, también sin permiso, y no es una
      // contradicción: van con el valor cargado, así que **no cambian nada** y el
      // servidor sólo exige `company.settings.manage` si cambian de verdad. Omitirlos
      // no es una opción: en este `PUT` un domicilio ausente significa «bórralo».
      direccion: _direccionDelFormulario(),
      horario: _horario,
    );

    if (!mounted) return;

    await resultado.when(
      ok: (e) async {
        setState(() {
          _volcar(e);
          _guardando = false;
          _reintentos = 0;
        });

        // LA LISTA SE ENTERA DEL NOMBRE Y DEL TIPO NUEVOS. Sin esto seguiría
        // enseñando los viejos hasta que alguien recargara la pantalla.
        widget.alCambiar?.call(
          widget.sucursal.copiaCon(nombre: e.nombre, tipoId: e.tipoId),
        );

        RisegFeedback.showSuccess(context, 'Expediente de la sucursal guardado.');
      },
      failure: (f) async {
        setState(() => _guardando = false);

        if (ExpedientesRepositorioHttp.esDesactualizado(f)) {
          await _resolverElChoque(f);

          return;
        }

        // EL SOLAPE LO DICE EL MOTOR Y SE MUESTRA TAL CUAL. La pantalla no lo
        // adelanta con una comprobación propia: serían dos reglas para un mismo
        // hecho, y la de aquí se quedaría atrás el día que la del motor cambie.
        if (f case ApiHttpFailure(codigo: 'horario_se_solapa')) {
          mostrarRechazoDelServidor(context, f);

          return;
        }

        // EL TIPO RETIRADO VA AL SELECTOR, no a un diálogo. El servidor lo manda como
        // un 422 con su propio código —no como un error de campo— porque es una regla
        // de catálogo y no de formato; pero para quien está mirando la pantalla es un
        // campo que puede corregir ahí mismo, y un diálogo lo obligaría a cerrarlo
        // para encontrar cuál.
        if (f case ApiHttpFailure(codigo: 'tipo_de_sucursal_no_disponible')) {
          setState(() => _erroresDeCampo = {'branchTypeId': f.message});
          _llevarLaVistaAlPrimerError();

          return;
        }

        final campos = ExpedientesRepositorioHttp.camposDe(f);

        if (campos.isNotEmpty) {
          setState(() => _erroresDeCampo = campos);
          _llevarLaVistaAlPrimerError();

          return;
        }

        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  /// Lleva la vista —y el cursor— al **primer** campo señalado.
  ///
  /// ⚠️ **SIN ESTO, GUARDAR DESDE ABAJO PARECE NO HACER NADA.** Está medido: el botón
  /// va al final del formulario y el nombre al principio, así que con el servidor
  /// señalando `name` el error se pintaba y el desplazamiento se quedaba en 962 px. La
  /// persona veía exactamente lo mismo que antes de pulsar.
  ///
  /// Se enfoca el campo en vez de sólo desplazar porque son dos cosas que quiere a la
  /// vez: verlo y poder escribir en él sin volver a pulsarlo.
  void _llevarLaVistaAlPrimerError() {
    // EL ERROR LOCAL DEL NOMBRE CUENTA IGUAL que uno del servidor: la persona pulsó
    // guardar y hay algo que arreglar arriba.
    final senalados = {..._erroresDeCampo, if (_errorDeNombre != null) 'name': _errorDeNombre};

    if (_focos.llevarLaVistaAlPrimerError(senalados)) return;

    // LO QUE NO SE PUEDE ENFOCAR se trae por su sección, en el orden en que está en
    // la pantalla: el tipo arriba, el horario al final.
    if (senalados.containsKey('branchTypeId')) {
      if (_claveDeDatos.currentContext case final contexto?) {
        risegLlevarLaVistaA(contexto);
      }

      return;
    }

    if (senalados.keys.any((k) => k.startsWith('schedule'))) {
      if (_claveDelHorario.currentContext case final contexto?) {
        risegLlevarLaVistaA(contexto);
      }
    }
  }

  // =========================================================================
  // Las tres operaciones del encabezado
  // =========================================================================

  /// Cierra temporalmente o reabre, **con confirmación y de inmediato**.
  ///
  /// La confirmación no es ceremonia: cerrar una sucursal la saca de la operación del
  /// día, y reabrirla es una decisión que alguien tiene que tomar a mano. El producto
  /// de escritorio también confirma.
  Future<void> _cambiarEstadoOperativo() async {
    final cerrando = !_cerrada;
    final nombre = widget.sucursal.nombre;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: cerrando ? 'Cerrar temporalmente' : 'Reabrir sucursal',
      message: cerrando
          ? '$nombre dejará de aparecer como abierta. Sigue dada de alta y alguien '
                'tendrá que reabrirla.'
          : '$nombre volverá a aparecer como abierta hoy.',
      confirmLabel: cerrando ? 'Cerrar temporalmente' : 'Reabrir',
      cancelLabel: 'Cancelar',
    );

    if (!(confirmado ?? false) || !mounted) return;

    setState(() => _cambiandoOperativo = true);

    final resultado = cerrando
        ? await widget.repositorioDeSucursales.cerrarTemporalmente(
            empresaId: widget.empresaId,
            sucursalId: _sucursalId,
          )
        : await widget.repositorioDeSucursales.reabrir(
            empresaId: widget.empresaId,
            sucursalId: _sucursalId,
          );

    if (!mounted) return;

    resultado.when(
      ok: (sucursal) {
        setState(() {
          _cambiandoOperativo = false;
          // SE LEE DEL SERVIDOR, no se asume. Las rutas son idempotentes y pueden
          // devolver la fila sin cambiar; suponer el resultado contaría una historia
          // falsa.
          _cerrada = sucursal.estadoOperativo != 'operando';
        });

        widget.alCambiar?.call(sucursal);

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
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  /// Activa o desactiva: el interruptor, **convertido en acción**.
  ///
  /// Era un `Switch` dentro del formulario del panel, que se aplicaba al pulsar
  /// «Guardar». Aquí no puede serlo: el `PATCH` que lo cambia es la única cosa que esa
  /// ruta hace ya, y mezclarlo con el guardado del expediente volvería a juntar dos
  /// permisos en una intención.
  Future<void> _cambiarActiva() async {
    final desactivando = _activa;
    final nombre = widget.sucursal.nombre;

    final confirmado = await RisegDialog.showConfirmation(
      context: context,
      title: desactivando ? 'Desactivar sucursal' : 'Activar sucursal',
      message: desactivando
          ? '$nombre dejará de poder usarse en el sistema. No es lo mismo que '
                'cerrarla temporalmente: para desactivarla tiene que estar cerrada y '
                'sin personal activo asignado.'
          : '$nombre volverá a poder usarse en el sistema.',
      confirmLabel: desactivando ? 'Desactivar' : 'Activar',
      cancelLabel: 'Cancelar',
    );

    if (!(confirmado ?? false) || !mounted) return;

    setState(() => _cambiandoActiva = true);

    final resultado = await widget.repositorioDeSucursales.cambiarEstado(
      empresaId: widget.empresaId,
      sucursalId: _sucursalId,
      activa: !desactivando,
    );

    if (!mounted) return;

    resultado.when(
      ok: (sucursal) {
        setState(() {
          _cambiandoActiva = false;
          _activa = sucursal.activa;
        });

        widget.alCambiar?.call(sucursal);

        RisegFeedback.showSuccess(
          context,
          desactivando
              ? 'Se desactivó ${sucursal.nombre}.'
              : 'Se activó ${sucursal.nombre}.',
        );
      },
      failure: (f) {
        setState(() => _cambiandoActiva = false);

        // AQUÍ CAE `desactivacion_bloqueada` con su leyenda: «sigue operando» o «hay
        // personal activo asignado». Se muestra tal cual: son las dos cosas que hay
        // que resolver antes, y sólo el servidor sabe cuál de las dos es.
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  /// Elimina la sucursal, con motivo. **Sólo Maestro, y sólo si nunca se usó.**
  ///
  /// Al terminar **se vuelve a la lista**: el expediente que se estaba mirando ya no
  /// existe, y quedarse en él enseñaría los datos de una fila borrada.
  Future<void> _eliminar() async {
    final motivo = await pedirMotivoDeEliminacion(
      context,
      queEs: 'la sucursal',
      comoSeLlama: '${widget.sucursal.codigo} · ${widget.sucursal.nombre}',
      queSePierde: 'La sucursal desaparece de la empresa.',
    );

    if (motivo == null || !mounted) return;

    setState(() => _eliminando = true);

    final resultado = await widget.repositorioDeSucursales.eliminar(
      empresaId: widget.empresaId,
      sucursalId: _sucursalId,
      motivo: motivo,
    );

    if (!mounted) return;

    resultado.when(
      ok: (sucursal) {
        RisegFeedback.showSuccess(
          context,
          'Se eliminó la sucursal ${sucursal.nombre}.',
        );

        widget.onVolver();
      },
      failure: (f) {
        setState(() => _eliminando = false);

        // AQUÍ CAE `estructura_en_uso` CON EL CONTEO. La salida es desactivarla, y el
        // mensaje del servidor lo dice: no se reescribe aquí.
        mostrarRechazoDelServidor(context, f);
      },
    );
  }

  // =========================================================================
  // El choque: cuando otra persona guardó mientras yo editaba
  // =========================================================================

  /// Qué hacer con el 409 del candado optimista.
  ///
  /// **Antes aquí sólo había un aviso con un botón: «Cargar lo más reciente».** Eso
  /// recargaba el formulario y tiraba todo lo que la persona había escrito, por un
  /// choque que casi nunca era un choque de verdad: dos personas editando secciones
  /// distintas del mismo expediente se pisaban el trabajo mutuamente.
  ///
  /// Ahora el 409 trae **el expediente que el servidor tiene**, así que se puede
  /// comparar contra lo que se cargó al abrir y contra lo que hay en el formulario:
  ///
  ///  · lo que sólo cambió uno de los dos → se queda, sin preguntar;
  ///  · lo que cambiaron los dos a lo mismo → igual;
  ///  · **lo que cambiaron los dos a cosas distintas → eso, y sólo eso, se pregunta.**
  ///
  /// Si no hay nada que preguntar, se reintenta solo. Si lo hay, la persona elige y se
  /// reintenta con su decisión. Y si cierra el aviso, **no se pierde nada**: el
  /// formulario se queda como estaba.
  Future<void> _resolverElChoque(Failure fallo) async {
    final suyo = ExpedientesRepositorioHttp.actualDe(
      fallo,
      ExpedienteDeSucursal.deJson,
    );

    // SIN EL EXPEDIENTE DEL SERVIDOR NO SE PUEDE COMPARAR, y entonces se hace lo de
    // antes: avisar y recargar. Pasa con un servidor viejo, y es el único camino en
    // que la persona todavía tiene que volver a escribir lo suyo.
    // Y EL TOPE DE REINTENTOS CAE EN EL MISMO SITIO: tres vueltas y se avisa como
    // antes. Comparar una cuarta vez no es más seguro, sólo más largo.
    if (suyo == null || _expediente == null || _reintentos >= 3) {
      await _avisarSinPoderComparar();

      return;
    }

    final choque = _compararCon(suyo);

    // SE RESUELVE SOLO: cada uno tocó cosas distintas. **Es el caso frecuente de
    // verdad**, y preguntar aquí sería pedir que alguien confirme algo que no chocaba.
    if (choque.seResuelveSolo) {
      _aplicar(suyo, choque, const {});
      _reintentos++;
      await _guardar();

      return;
    }

    final elegidos = await mostrarDialogoDeChoque(
      context: context,
      choque: choque,
    );

    // CERRÓ EL AVISO: no se guarda y **no se toca el formulario**. Lo que escribió
    // sigue ahí, que es lo que este aviso viene a proteger.
    if (elegidos == null || !mounted) return;

    _aplicar(suyo, choque, elegidos);
    _reintentos++;
    await _guardar();
  }

  /// Las tres versiones de cada campo: lo que se cargó, lo que hay escrito y lo suyo.
  ChoqueDeExpediente _compararCon(ExpedienteDeSucursal suyo) {
    final base = _expediente!;
    final mia = _direccionDelFormulario();

    CampoComparado deLaDireccion(
      String campo,
      String etiqueta,
      String? Function(Direccion) cual,
    ) => CampoComparado(
      campo: 'address.$campo',
      etiqueta: etiqueta,
      base: base.direccion == null ? null : cual(base.direccion!),
      mio: mia == null ? null : cual(mia),
      suyo: suyo.direccion == null ? null : cual(suyo.direccion!),
    );

    return ChoqueDeExpediente([
      CampoComparado(
        campo: 'name',
        etiqueta: 'Nombre',
        base: base.nombre,
        mio: _nombre.text.trim(),
        suyo: suyo.nombre,
      ),
      CampoComparado(
        campo: 'branchTypeId',
        etiqueta: 'Tipo de sucursal',
        base: base.tipoId,
        mio: _tipoId,
        suyo: suyo.tipoId,
        // SE COMPARA EL ID Y SE LEE EL NOMBRE: dos tipos pueden llamarse igual, y un
        // UUID en el aviso no le dice nada a nadie.
        comoSeLee: _nombreDelTipo,
      ),
      deLaDireccion('street', 'Calle', (d) => d.calle),
      deLaDireccion('exteriorNumber', 'Número exterior', (d) => d.numeroExterior),
      deLaDireccion('interiorNumber', 'Número interior', (d) => d.numeroInterior),
      deLaDireccion('neighborhood', 'Colonia', (d) => d.colonia),
      deLaDireccion('municipality', 'Municipio', (d) => d.municipio),
      deLaDireccion('city', 'Ciudad', (d) => d.ciudad),
      deLaDireccion('state', 'Estado', (d) => d.estado),
      deLaDireccion('postalCode', 'Código postal', (d) => d.codigoPostal),
      deLaDireccion('country', 'País', (d) => d.pais),
      deLaDireccion('landmarks', 'Referencias', (d) => d.referencias),

      // EL HORARIO ENTERO ES UN SOLO CAMPO, y no un campo por día. Un día admite
      // varios tramos y se añaden y quitan como un conjunto, así que «mi martes con
      // su miércoles» sería un horario que ninguno de los dos escribió. Se compara
      // por su contenido completo y se lee como se lee en pantalla.
      CampoComparado(
        campo: 'schedule',
        etiqueta: 'Horario semanal',
        base: _horarioComoTexto(base.horario),
        mio: _horarioComoTexto(_horario),
        suyo: _horarioComoTexto(suyo.horario),
      ),
    ]);
  }

  /// Deja en el formulario el resultado de las elecciones, **y la versión del
  /// servidor como nueva base**: el siguiente guardado va con su contador, y si
  /// apareciera una tercera persona la comparación seguiría siendo correcta.
  void _aplicar(
    ExpedienteDeSucursal suyo,
    ChoqueDeExpediente choque,
    Map<String, bool> elegidos,
  ) {
    final valores = choque.resolver(elegidos);

    setState(() {
      // LA BASE PASA A SER LA SUYA, con su versión. Lo que se escribe encima es el
      // resultado de la mezcla, no lo que el servidor tiene.
      _expediente = suyo;

      _nombre.text = valores['name'] ?? '';
      _tipoId = valores['branchTypeId'];

      _calle.text = valores['address.street'] ?? '';
      _exterior.text = valores['address.exteriorNumber'] ?? '';
      _interior.text = valores['address.interiorNumber'] ?? '';
      _colonia.text = valores['address.neighborhood'] ?? '';
      _municipio.text = valores['address.municipality'] ?? '';
      _ciudad.text = valores['address.city'] ?? '';
      _estado.text = valores['address.state'] ?? '';
      _cp.text = valores['address.postalCode'] ?? '';
      _pais.text = valores['address.country'] ?? '';
      _referencias.text = valores['address.landmarks'] ?? '';

      // EL HORARIO SE RESUELVE POR OBJETO, no por su texto: lo que `resolver`
      // devuelve de este campo es el resumen legible, que no se puede volver a
      // convertir en tramos.
      _horario = choque.seQuedaLoSuyo('schedule', elegidos)
          ? [...suyo.horario]
          : [..._horario];
    });
  }

  /// El aviso de antes, para cuando no se puede comparar. **Recargar pierde lo
  /// escrito**, así que se dice.
  Future<void> _avisarSinPoderComparar() => showDialog<void>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Alguien más guardó este expediente'),
      content: const Text(
        'Mientras tenías el formulario abierto, otra persona guardó cambios en el '
        'expediente de esta sucursal. Para no borrar su trabajo, no se guardó '
        'nada.\n\n'
        'Se van a cargar los datos más recientes. Revisa lo que haya cambiado y '
        'vuelve a escribir lo tuyo.',
      ),
      actions: [
        RisegButton(
          label: 'Cargar lo más reciente',
          onPressed: () {
            Navigator.of(contexto).pop();
            _reintentos = 0;
            _cargar();
          },
        ),
      ],
    ),
  );

  /// El horario como se lee: `Lunes 09:00 – 14:00, 16:00 – 20:00 · Martes …`.
  ///
  /// **Un día sin tramos no aparece**, que es lo que «cerrado» significa aquí. Y la
  /// semana vacía se dice con palabras, no con una cadena en blanco: un hueco en el
  /// aviso se leería como un fallo de la pantalla.
  String _horarioComoTexto(List<TramoDeHorario> horario) {
    final dias = <String>[];

    for (var dia = 1; dia <= 7; dia++) {
      final tramos = [for (final t in horario) if (t.dia == dia) t]
        ..sort((a, b) => a.inicio.compareTo(b.inicio));

      if (tramos.isEmpty) continue;

      dias.add(
        '${TramoDeHorario.nombresDeDia[dia]} '
        '${tramos.map((t) => t.horario).join(', ')}',
      );
    }

    return dias.isEmpty ? 'Cerrada toda la semana' : dias.join(' · ');
  }

  /// El nombre del tipo, o lo que se puede decir cuando no se sabe.
  ///
  /// **«Sin tipo» y «un tipo que ya no está en el catálogo» no son lo mismo**: la
  /// primera es una sucursal histórica, de antes de que existieran los tipos, y la
  /// segunda es un tipo que alguien eliminó. Decir lo mismo de las dos haría pensar
  /// que se perdió un dato que nunca existió.
  String _nombreDelTipo(String? id) {
    if (id == null) return 'Sin tipo';

    for (final t in widget.tipos) {
      if (t.id == id) return t.nombre;
    }

    return 'Un tipo que ya no está en el catálogo';
  }

  // =========================================================================
  // Pintar
  // =========================================================================

  @override
  Widget build(BuildContext context) => Scaffold(
    // ⚠️ `Scaffold` PROPIO, Y NO ES DECORACIÓN. Esta pantalla la monta la lista de
    // sucursales en lugar de sí misma, igual que el catálogo de tipos, así que si no
    // trae su superficie **no hay ningún `Material` encima** y cada `TextField`, cada
    // `Switch` y cada `InkWell` revienta con «No Material widget found».
    //
    // No se veía porque hasta ahora las pruebas de esta pantalla la envolvían ellas
    // mismas en un `Scaffold`, y la única que la monta por su camino real —la de los
    // botones por permiso— abría el panel lateral, que trae el suyo. Al pasar el toque
    // de la fila al expediente, salieron ocho excepciones de golpe.
    backgroundColor: context.colors.surface,
    // EL RECORRIDO DE FOCO ENVUELVE AL `Scrollable`, no al contrario: la política
    // necesita encontrarlo desde el contexto de lo enfocado, y lo busca hacia arriba.
    // Sin esto, la vuelta de `Tab` —de «Guardar expediente» al enlace de regreso—
    // dejaba la vista abajo y el foco invisible 910 px más arriba.
    body: SafeArea(child: RisegRecorridoDeFoco(child: _cuerpo())),
  );

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    final fallo = _fallo;

    if (fallo != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(fallo.message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              RisegButton(label: 'Volver a intentar', onPressed: _cargar),
            ],
          ),
        ),
      );
    }

    final expediente = _expediente!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // EL REGRESO VA ARRIBA Y A LA IZQUIERDA, igual que en el catálogo de tipos:
          // no es una pestaña, así que sin esto no habría forma de salir.
          InkWell(
            onTap: widget.onVolver,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: 16,
                    color: context.colors.accent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Sucursales',
                    style: AppTypography.caption.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          RisegSectionHeader(
            title: '${expediente.codigo} · ${expediente.nombre}',
            description:
                'Todo lo de esta sucursal: su nombre, su tipo, su domicilio y su '
                'horario. Recuerda que la sucursal es un destino administrativo, no el '
                'lugar donde se cubre un servicio.',
          ),
          const SizedBox(height: AppSpacing.md),
          _encabezado(),
          const SizedBox(height: AppSpacing.lg),
          _seccionDeDatos(),
          const SizedBox(height: AppSpacing.lg),
          _seccionDeDomicilio(),
          // LA NOTA VA FUERA DE LA SECCIÓN, no entre sus campos: la del domicilio se
          // pinta en rejilla de dos columnas, y la nota ocuparía una celda al lado de
          // un campo, leyéndose como su ayuda.
          if (!widget.puedeEditarExpedientes) ...[
            const SizedBox(height: AppSpacing.xs),
            _notaDePermiso(
              'Para cambiar el domicilio necesitas el permiso de configurar la '
              'empresa.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _seccionDeHorario(),
          const SizedBox(height: AppSpacing.xl),
          if (_puedeGuardarAlgo)
            Align(
              alignment: Alignment.centerRight,
              child: RisegButton(
                label: 'Guardar expediente',
                icon: Icons.save_outlined,
                loading: _guardando,
                onPressed: _ocupado ? null : _guardar,
              ),
            )
          else
            // UNA LÍNEA, NO TRES. Cada sección ya lleva su nota diciendo qué permiso
            // le falta, y repetirlas aquí abajo —donde la persona no está mirando—
            // haría leer cuatro veces lo mismo.
            Text(
              'Sólo puedes consultar esta sucursal.',
              style: AppTypography.caption.copyWith(
                color: context.colors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  /// Si hay **algo** que esta persona pueda guardar. Con los dos permisos ausentes el
  /// botón no aparece: no es un formulario, es una ficha.
  bool get _puedeGuardarAlgo =>
      _puedeEditarEstructura || widget.puedeEditarExpedientes;

  // =========================================================================
  // El encabezado: los dos estados y las tres acciones
  // =========================================================================

  /// Las insignias y las acciones, **cada una visible sólo con su permiso**.
  ///
  /// Las tres venían del panel lateral que esta pantalla sustituyó, con sus permisos
  /// intactos: cerrar y reabrir es `organizacion.modificar` —no da de baja a nadie y es
  /// reversible—, el interruptor es `organizacion.archivar` **en las dos direcciones**,
  /// y eliminar exige el rol Maestro **y además** `archivar`.
  ///
  /// **Y SE APLICAN DE INMEDIATO, sin pasar por «Guardar»**: son operaciones con su
  /// confirmación y su evento de auditoría, no campos del formulario. Mezclarlas con
  /// el guardado haría que cerrar una sucursal dependiera de que nadie pulse
  /// «Cancelar» después.
  Widget _encabezado() {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⚠️ `Wrap` Y NO `Row`: con «Cerrada temporalmente» en la insignia y «Cerrar
        // temporalmente» en el botón, una fila se pasaba 95 px del ancho del panel
        // —desbordamiento real, lo destapó una prueba—. Aquí hay más sitio, pero el
        // texto es el mismo y la pantalla también se estrecha.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RisegStatusBadge(
              label: _cerrada ? 'Cerrada temporalmente' : 'Operando',
              tone: _cerrada ? RisegStatusTone.warning : RisegStatusTone.success,
              icon: _cerrada
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
            RisegStatusBadge(
              label: _activa ? 'Activa' : 'Inactiva',
              tone: _activa ? RisegStatusTone.success : RisegStatusTone.neutral,
              icon: _activa
                  ? Icons.check_circle_outline
                  : Icons.remove_circle_outline,
            ),

            if (widget.capacidades.puedeModificar)
              RisegButton(
                label: _cerrada ? 'Reabrir' : 'Cerrar temporalmente',
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                loading: _cambiandoOperativo,
                onPressed: _ocupado ? null : _cambiarEstadoOperativo,
              ),

            if (widget.capacidades.puedeArchivar)
              RisegButton(
                label: _activa ? 'Desactivar' : 'Activar',
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                loading: _cambiandoActiva,
                onPressed: _ocupado ? null : _cambiarActiva,
              ),

            // ELIMINAR VA AL FINAL Y EN ROJO: no se pulsa por error, y pertenece a
            // otra categoría que cerrar o desactivar.
            if (widget.esMaestro && widget.capacidades.puedeArchivar)
              RisegButton(
                label: 'Eliminar',
                variant: RisegButtonVariant.danger,
                icon: Icons.delete_outline,
                size: RisegButtonSize.compact,
                loading: _eliminando,
                onPressed: _ocupado ? null : _eliminar,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          // LOS DOS ESTADOS SE EXPLICAN JUNTOS porque es justo lo que se confunde:
          // «cerrada» es hoy y «inactiva» es para siempre.
          _activa
              ? _cerrada
                    ? 'Cerrada hoy, pero sigue dada de alta: alguien tiene que '
                          'reabrirla. No es lo mismo que inactiva.'
                    : 'Abierta y dada de alta. Cerrar temporalmente no la da de baja.'
              : 'Inactiva: ya no se usa. Para volver a usarla hay que activarla.',
          style: AppTypography.caption.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }

  // =========================================================================
  // Nombre y tipo: la estructura
  // =========================================================================

  Widget _seccionDeDatos() => RisegFormSection(
    key: _claveDeDatos,
    title: 'Datos generales',
    description:
        'El nombre y el tipo. El código no se cambia: es la identidad de la sucursal.',
    children: [
      RisegTextField(
        label: 'Nombre',
        controller: _nombre,
        focusNode: _focos['name'],
        enabled: _puedeEditarEstructura && !_ocupado,
        errorText: _errorDeNombre ?? _erroresDeCampo['name'],
        helperText: 'Como Centro o Matriz.',
      ),
      // SIN `SizedBox` ENTRE CAMPOS: esta sección no es rejilla, y `RisegFormSection`
      // ya le pone su espacio a cada hijo. Uno de más contaría doble.
      RisegSelect<String>(
        label: 'Tipo de sucursal',
        value: _tipoId,
        enabled: _puedeEditarEstructura && !_ocupado,
        hint: 'Elige un tipo',
        errorText: _erroresDeCampo['branchTypeId'],
        items: [
          for (final t in widget.tipos)
            RisegSelectItem(value: t.id, label: t.nombre),
        ],
        onChanged: (v) => setState(() => _tipoId = v),
      ),
      if (!_puedeEditarEstructura)
        _notaDePermiso(
          'Para cambiar el nombre o el tipo necesitas el permiso de modificar la '
          'organización.',
        ),
    ],
  );

  /// La nota de **qué permiso falta**, junto a los campos que por eso están de sólo
  /// lectura.
  ///
  /// **No se esconden los campos**: el expediente se consulta mucho más de lo que se
  /// edita, y quitarle la dirección a quien puede renombrar la sucursal le quitaría el
  /// dato sin motivo. Lo que no se hace es ofrecer un campo que al guardar va a
  /// contestar 403 sin explicar nada.
  Widget _notaDePermiso(String texto) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.lock_outline, size: 14, color: context.colors.textMuted),
      const SizedBox(width: AppSpacing.xxs),
      Expanded(
        child: Text(
          texto,
          style: AppTypography.caption.copyWith(color: context.colors.textMuted),
        ),
      ),
    ],
  );

  Widget _seccionDeHorario() => RisegFormSection(
    key: _claveDelHorario,
    title: 'Horario semanal',
    description:
        'Cada día puede tener más de un tramo: abrir de 9 a 14 y de 16 a 20 son dos '
        'tramos del mismo día. Un día sin tramos está cerrado.',
    children: [
      if (!widget.puedeEditarExpedientes)
        _notaDePermiso(
          'Para cambiar el horario necesitas el permiso de configurar la empresa.',
        ),
      for (var dia = 1; dia <= 7; dia++) _filaDeDia(dia),
      if (_erroresDeCampo.keys.any((k) => k.startsWith('schedule')))
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Text(
            [
              for (final e in _erroresDeCampo.entries)
                if (e.key.startsWith('schedule')) e.value,
            ].join('\n'),
            style: AppTypography.caption.copyWith(
              color: context.colors.error,
            ),
          ),
        ),
    ],
  );

  Widget _filaDeDia(int dia) {
    final colors = context.colors;
    final tramos = _tramosDe(dia);
    final abierto = tramos.isNotEmpty;
    final habilitado = widget.puedeEditarExpedientes && !_ocupado;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  TramoDeHorario.nombresDeDia[dia],
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                abierto ? 'Abierto' : 'Cerrado',
                style: AppTypography.caption.copyWith(color: colors.textMuted),
              ),
              Switch(
                value: abierto,
                onChanged: habilitado
                    ? (v) => _cambiarDia(dia, abierto: v)
                    : null,
              ),
            ],
          ),
          for (final tramo in tramos) _filaDeTramo(tramo, habilitado: habilitado),
          if (abierto && habilitado)
            Align(
              alignment: Alignment.centerLeft,
              child: RisegButton(
                label: 'Agregar tramo',
                icon: Icons.add,
                variant: RisegButtonVariant.secondary,
                size: RisegButtonSize.compact,
                onPressed: () => _agregarTramo(dia),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaDeTramo(TramoDeHorario tramo, {required bool habilitado}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: RisegTimeField(
            label: 'Desde',
            value: _comoTimeOfDay(tramo.inicio),
            enabled: habilitado,
            onChanged: (v) =>
                _cambiarHora(tramo, inicio: v.hour * 60 + v.minute),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: RisegTimeField(
            label: 'Hasta',
            value: _comoTimeOfDay(tramo.fin),
            enabled: habilitado,
            // «00:00» COMO CIERRE SE GUARDA COMO 24:00, y la ayuda lo dice en vez de
            // dejar que se descubra viendo un número raro.
            helperText: tramo.fin == 1440
                ? 'Cierra a medianoche (24:00).'
                : tramo.cruzaMedianoche
                      ? 'Cruza la medianoche: cierra al día siguiente.'
                      : null,
            onChanged: (v) => _cambiarHora(tramo, fin: v.hour * 60 + v.minute),
          ),
        ),
        if (habilitado)
          IconButton(
            tooltip: 'Quitar este tramo',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _quitarTramo(tramo),
          ),
      ],
    ),
  );

  /// 1440 no cabe en un `TimeOfDay`, así que el selector lo abre en **00:00** — que es
  /// justo el valor que [TramoDeHorario.nuevo] vuelve a convertir en 1440. El reloj
  /// da la vuelta y el dato no se pierde.
  TimeOfDay _comoTimeOfDay(int minutos) {
    final m = minutos >= 1440 ? 0 : minutos;

    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  Widget _seccionDeDomicilio() => RisegFormSection(
    title: 'Domicilio',
    description:
        'Si escribes cualquier dato, hacen falta calle, número exterior, colonia, '
        'municipio, estado y código postal. Si los dejas todos vacíos, no se guarda '
        'domicilio.',
    grid: true,
    children: [
      _campoDelDomicilio('address.street', 'Calle', _calle),
      _campoDelDomicilio('address.exteriorNumber', 'Número exterior', _exterior),
      _campoDelDomicilio(
        'address.interiorNumber',
        'Número interior',
        _interior,
        ayuda: 'Opcional.',
      ),
      _campoDelDomicilio('address.neighborhood', 'Colonia', _colonia),
      _campoDelDomicilio('address.municipality', 'Municipio', _municipio),
      _campoDelDomicilio(
        'address.city',
        'Ciudad',
        _ciudad,
        ayuda: 'Opcional.',
      ),
      _campoDelDomicilio('address.state', 'Estado', _estado),
      _campoDelDomicilio(
        'address.postalCode',
        'Código postal',
        _cp,
        ayuda: 'Cinco dígitos.',
        teclado: TextInputType.number,
      ),
      _campoDelDomicilio(
        'address.country',
        'País',
        _pais,
        ayuda: 'Opcional.',
      ),
      _campoDelDomicilio(
        'address.landmarks',
        'Referencias',
        _referencias,
        ayuda: 'Opcional. Entre qué calles, frente a qué.',
      ),
    ],
  );

  /// Un campo del domicilio, **con su clave del servidor dicha una sola vez**.
  ///
  /// Antes eran diez bloques de cuatro líneas iguales, y al añadir el nodo de foco
  /// habrían sido diez sitios donde emparejar a mano la clave del error con la del
  /// nodo. Dos claves que se escriben por separado es exactamente cómo un campo se
  /// queda sin señalar sin que nada falle: el error se pintaría en «Colonia» y la
  /// vista iría a «Municipio», y ninguna prueba de las que existen lo notaría.
  Widget _campoDelDomicilio(
    String campo,
    String etiqueta,
    TextEditingController controlador, {
    String? ayuda,
    TextInputType? teclado,
  }) => RisegTextField(
    label: etiqueta,
    controller: controlador,
    focusNode: _focos[campo],
    enabled: widget.puedeEditarExpedientes && !_ocupado,
    errorText: _erroresDeCampo[campo],
    helperText: ayuda,
    keyboardType: teclado,
  );
}
