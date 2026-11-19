import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../../../organizacion/web/modelos/puesto.dart';
import '../datos/condiciones_repositorio_http.dart';
import '../modelos/cliente.dart' show Monto;
import '../modelos/condicion_comercial.dart';

/// El formulario de una **condición comercial**: lo que se le cobra al cliente durante una
/// vigencia, con su puesto, su turno, sus plazas, su precio, su IVA y su horario semanal.
///
/// ## Por qué es un solo formulario para tres actos
///
/// Crear la primera, programar la siguiente y corregir piden **los mismos campos** y los
/// distingue quién llama. Tres formularios serían tres sitios donde añadir un campo nuevo,
/// y el día que se olvidara uno el precio dejaría de guardarse **sin que nada fallara**.
///
/// Lo que sí cambia según el acto son dos cosas, y las dos vienen de fuera:
///
///  · **el sueldo de referencia se pide SÓLO en la primera.** En las otras dos el servidor
///    lo rechaza con 422, y pedirlo para tirarlo sería hacer teclear un dato que no se
///    guarda;
///  · **el motivo se pide SÓLO al corregir la vigente**, que es la que está cobrando.
///
/// ## 🚫 EL SOLAPE DE HORARIOS NO SE VALIDA AQUÍ, y es deliberado
///
/// La aritmética de la semana —el cruce de medianoche, los 10 080 minutos— vive en el
/// servidor y la garantiza una exclusión del motor, que además **dice qué bloque choca**.
/// Repetirla en la pantalla dejaría dos implementaciones que algún día discreparían, y
/// entonces la pantalla aceptaría algo que la base rechaza o al revés.
///
/// ## 24:00 se captura como 00:00
///
/// El reloj del sistema no puede expresar «24:00», así que **un fin a las 00:00 significa la
/// medianoche como FINAL del día** y se manda como el minuto 1440. El formulario lo dice en
/// voz alta debajo del campo, porque es la clase de regla que alguien descubriría por
/// accidente.
/// ## El alta de la línea usa ESTE MISMO formulario
///
/// Con [pideNombre] en `true` el diálogo pide además **el nombre y el tipo de la línea**, y
/// entonces lo que devuelve crea **la línea y su primera condición en una sola petición**
/// (decisión del dueño del 18-nov-2026, de la tabla de paridad con RISEG ONE).
///
/// 🚫 **No es un formulario distinto a propósito:** dos pantallas con los mismos quince
/// campos serían dos sitios donde añadir el siguiente, y el día que se olvidara uno el
/// precio se guardaría a medias **sin que nada fallara**.
Future<ResultadoDeCondicion?> mostrarDialogoDeCondicion(
  BuildContext context, {
  required String titulo,
  required List<ModalidadDeTurno> modalidades,
  required List<Puesto> puestos,
  required DiaDeNegocio hoy,
  required GuardiaDeSalida guardia,
  required bool pideSueldoDeReferencia,
  required bool pideMotivo,
  CondicionComercial? existente,
  bool pideNombre = false,
  TipoDeLinea tipo = TipoDeLinea.personal,
  Future<Puesto?> Function()? alCrearPuesto,
  Future<List<ModalidadDeTurno>?> Function()? alAgregarModalidades,
}) => showDialog<ResultadoDeCondicion>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _DialogoDeCondicion(
    titulo: titulo,
    modalidades: modalidades,
    puestos: puestos,
    hoy: hoy,
    guardia: guardia,
    pideSueldoDeReferencia: pideSueldoDeReferencia,
    pideMotivo: pideMotivo,
    existente: existente,
    pideNombre: pideNombre,
    tipo: tipo,
    alCrearPuesto: alCrearPuesto,
    alAgregarModalidades: alAgregarModalidades,
  ),
);

/// Las llaves de los campos del formulario de condición.
///
/// ## Por qué existen, y por qué no son «para las pruebas»
///
/// Una prueba que busque un campo por su **etiqueta** no lo encuentra: en este sistema de
/// diseño la etiqueta es un `Text` **encima** del campo, no dentro. Así que sin llaves lo
/// único que queda es buscar por posición —`find.byType(TextFormField).at(3)`—, y eso
/// convierte cualquier reordenación del formulario en una prueba que mide otro campo **sin
/// fallar**. Es el mismo defecto que una aserción fijada a un total global.
///
/// Son **públicas** a propósito: la prueba no puede inventárselas, y tenerlas en un solo
/// sitio es lo que impide que el nombre de una se quede viejo en un lado.
class ClavesDeCondicion {
  const ClavesDeCondicion();

  Key get inicio => const Key('condicion-inicio');
  Key get termino => const Key('condicion-termino');
  Key get tipo => const Key('condicion-tipo');
  Key get nombre => const Key('condicion-nombre');
  Key get puesto => const Key('condicion-puesto');
  Key get crearPuesto => const Key('condicion-crear-puesto');
  Key get modalidad => const Key('condicion-modalidad');
  Key get agregarModalidades => const Key('condicion-agregar-modalidades');
  Key get periodo => const Key('condicion-periodo');
  Key get horaDeCambio => const Key('condicion-hora-de-cambio');
  Key get plazas => const Key('condicion-plazas');
  Key get modo => const Key('condicion-modo');
  Key get precio => const Key('condicion-precio');
  Key get observaciones => const Key('condicion-observaciones');
  Key get total => const Key('condicion-total');
  Key get moneda => const Key('condicion-moneda');
  Key get iva => const Key('condicion-iva');
  Key get descripcion => const Key('condicion-descripcion');
  Key get sueldo => const Key('condicion-sueldo');
  Key get bono => const Key('condicion-bono');
  Key get motivo => const Key('condicion-motivo');
  Key get guardar => const Key('condicion-guardar');
}

const ClavesDeCondicion clavesDeCondicion = ClavesDeCondicion();

/// Lo que el formulario devuelve. El repositorio decide a qué ruta va.
class ResultadoDeCondicion {
  const ResultadoDeCondicion({
    required this.condicion,
    this.nombre,
    this.tipo = TipoDeLinea.personal,
    this.sueldoDeReferenciaMenores,
    this.bonoDeReferenciaMenores,
    this.motivo,
  });

  final CondicionEnviada condicion;

  /// El nombre de la línea. **Sólo en el alta**: en los otros tres actos la línea ya existe
  /// y renombrarla es otra operación.
  final String? nombre;

  /// Personal o concepto. En el alta lo elige quien captura; en los otros actos viene de la
  /// línea y vuelve igual.
  final TipoDeLinea tipo;

  /// Sólo en la primera condición de la línea. Nulo es **«no se capturó»**, que no es cero:
  /// un sueldo de referencia de cero pesos no es una referencia.
  final int? sueldoDeReferenciaMenores;
  final int? bonoDeReferenciaMenores;

  /// Sólo al corregir la vigente.
  final String? motivo;
}

class _DialogoDeCondicion extends StatefulWidget {
  const _DialogoDeCondicion({
    required this.titulo,
    required this.modalidades,
    required this.puestos,
    required this.hoy,
    required this.guardia,
    required this.pideSueldoDeReferencia,
    required this.pideMotivo,
    required this.existente,
    required this.pideNombre,
    required this.tipo,
    required this.alCrearPuesto,
    required this.alAgregarModalidades,
  });

  final String titulo;
  final List<ModalidadDeTurno> modalidades;
  final List<Puesto> puestos;
  final DiaDeNegocio hoy;
  final GuardiaDeSalida guardia;
  final bool pideSueldoDeReferencia;
  final bool pideMotivo;
  final CondicionComercial? existente;

  /// El alta de la línea: pide además el nombre y el tipo.
  final bool pideNombre;

  /// Personal o concepto. En el alta se elige; corrigiendo una condición **viene de la
  /// línea y no se toca**: una línea no cambia de naturaleza a mitad de su vida.
  final TipoDeLinea tipo;

  /// Crear un puesto **sin salir del formulario**.
  ///
  /// 🚫 **Existe porque salir perdía lo capturado.** El dueño lo encontró probando: sin
  /// puestos operativos el formulario sólo decía «se dan de alta en Organización › Puestos»,
  /// y había que salir, crear área y puesto, y volver a empezar.
  final Future<Puesto?> Function()? alCrearPuesto;

  /// Agregar las modalidades recomendadas **desde aquí**, cuando el catálogo está vacío.
  ///
  /// 🚫 **El otro hallazgo de su prueba:** la empresa del ensayo no tenía ni una modalidad y
  /// no había pantalla para dárselas, así que «Modalidad de turno» sólo ofrecía «Sin
  /// modalidad» — y desde la 0066 la modalidad es obligatoria, así que sin esto no se podría
  /// capturar nada.
  final Future<List<ModalidadDeTurno>?> Function()? alAgregarModalidades;

  @override
  State<_DialogoDeCondicion> createState() => _DialogoDeCondicionState();
}

class _DialogoDeCondicionState extends State<_DialogoDeCondicion>
    with DeclaraSuTrabajoSinGuardar<_DialogoDeCondicion> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// ⚠️ **SE COMPARA CONTRA LO CARGADO**, no contra un «se tocó algo». Es la regla del
  /// dueño: quien escribe un precio y lo deja como estaba no tiene trabajo sin guardar, y
  /// preguntarle sería un diálogo que estorba sin motivo.
  @override
  bool get hayCambiosSinGuardar =>
      _nombre.text.trim().isNotEmpty ||
      _tipo != widget.tipo ||
      _inicio != _inicioInicial ||
      _termino != _terminoInicial ||
      _puestoId != _puestoInicial ||
      _modalidadId != _modalidadInicial ||
      _periodo != _periodoInicial ||
      _horaDeCambio != _horaDeCambioInicial ||
      _plazas.text.trim() != _plazasInicial ||
      _modo != _modoInicial ||
      _precio.text.trim() != _precioInicial ||
      _moneda != _monedaInicial ||
      _iva != _ivaInicial ||
      _descripcion.text.trim() != _descripcionInicial ||
      _observaciones.text.trim() != _observacionesInicial ||
      _sueldo.text.trim().isNotEmpty ||
      _bono.text.trim().isNotEmpty ||
      _motivo.text.trim().isNotEmpty ||
      !_mismoHorario();

  @override
  String get queSePierde => widget.existente == null
      ? 'la condición comercial que estás capturando'
      : 'los cambios de la condición comercial';

  // --- Las bases, perezosas: el mixin registra antes de que esto acabe de armarse ---
  late final DateTime? _inicioInicial = _comoFecha(widget.existente?.inicio);
  late final DateTime? _terminoInicial = _comoFecha(widget.existente?.termino);
  late final String? _puestoInicial = widget.existente?.puestoId;
  late final String? _modalidadInicial = widget.existente?.modalidadId;
  late final PeriodoDeTurno? _periodoInicial = widget.existente?.periodoDelTurno;
  late final TimeOfDay? _horaDeCambioInicial =
      widget.existente?.horaDeCambioMinuto == null
      ? null
      : _comoHora(widget.existente!.horaDeCambioMinuto!);
  late final String _plazasInicial = widget.existente?.plazas.toString() ?? '';
  late final ModoDeCotizacion _modoInicial =
      widget.existente?.modo ?? ModoDeCotizacion.porPersona;

  /// El precio tal como se capturó: **el unitario o el total**, según el modo. Un solo campo
  /// de texto para los dos, porque sólo uno se enseña a la vez.
  late final String _precioInicial = switch (widget.existente) {
    null => '',
    final c when c.modo.esPorPersona => c.precioUnitarioMenores == null
        ? ''
        : _comoTexto(c.precioUnitarioMenores!),
    final c => c.totalMensualMenores == null ? '' : _comoTexto(c.totalMensualMenores!),
  };

  late final String _monedaInicial = widget.existente?.moneda ?? 'MXN';
  late final TratamientoDeIva _ivaInicial =
      widget.existente?.tratamientoDeIva ?? TratamientoDeIva.masIva;
  late final String _descripcionInicial = widget.existente?.descripcion ?? '';
  late final String _observacionesInicial = widget.existente?.observaciones ?? '';
  late final List<_BloqueEditable> _horarioInicial = [
    for (final h in widget.existente?.horarios ?? const <BloqueHorario>[])
      _BloqueEditable(
        dia: h.dia,
        inicio: _comoHora(h.inicioMinuto),
        fin: _comoHora(h.finMinuto),
      ),
  ];

  DateTime? _inicio;
  DateTime? _termino;
  String? _puestoId;
  String? _modalidadId;
  PeriodoDeTurno? _periodo;
  TimeOfDay? _horaDeCambio;
  ModoDeCotizacion _modo = ModoDeCotizacion.porPersona;
  String _moneda = 'MXN';
  TratamientoDeIva _iva = TratamientoDeIva.masIva;
  late TipoDeLinea _tipo = widget.tipo;

  /// ⚠️ **COPIAS LOCALES Y MUTABLES de los dos catálogos**, porque desde aquí se pueden
  /// crear: un puesto nuevo o las modalidades recomendadas tienen que aparecer en su
  /// desplegable **sin cerrar el formulario**, que es justo lo que se perdía antes.
  late List<Puesto> _puestos = [...widget.puestos];
  late List<ModalidadDeTurno> _modalidades = [...widget.modalidades];

  bool _ocupado = false;

  final _nombre = TextEditingController();
  final _plazas = TextEditingController();
  final _precio = TextEditingController();
  final _descripcion = TextEditingController();
  final _observaciones = TextEditingController();
  final _sueldo = TextEditingController();
  final _bono = TextEditingController();
  final _motivo = TextEditingController();

  final List<_BloqueEditable> _horario = [];

  final Map<String, String> _errores = {};

  @override
  void initState() {
    super.initState();

    final c = widget.existente;

    _inicio = _inicioInicial;
    _termino = _terminoInicial;
    _puestoId = _puestoInicial;
    _modalidadId = _modalidadInicial;
    _periodo = _periodoInicial;
    _horaDeCambio = _horaDeCambioInicial;
    _modo = _modoInicial;
    _moneda = _monedaInicial;
    _iva = _ivaInicial;
    _plazas.text = _plazasInicial;
    _precio.text = _precioInicial;
    _descripcion.text = _descripcionInicial;
    _observaciones.text = _observacionesInicial;

    for (final h in c?.horarios ?? const <BloqueHorario>[]) {
      _horario.add(
        _BloqueEditable(
          dia: h.dia,
          inicio: _comoHora(h.inicioMinuto),
          fin: _comoHora(h.finMinuto),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _plazas.dispose();
    _precio.dispose();
    _descripcion.dispose();
    _observaciones.dispose();
    _sueldo.dispose();
    _bono.dispose();
    _motivo.dispose();

    // ⚠️ `super.dispose()` AL FINAL: el mixin libera su registro ahí, y liberarlo antes de
    // soltar los controladores dejaría una ventana en la que el guardia pregunta por un
    // formulario que ya no existe.
    super.dispose();
  }

  /// La modalidad elegida, si está en el catálogo cargado.
  ModalidadDeTurno? get _modalidad =>
      _modalidades.where((m) => m.id == _modalidadId).firstOrNull;

  /// ¿Esta línea lleva puesto, turno y horario? Lo contrario es un concepto que se cobra.
  bool get _esDePersonal => _tipo.esPersonal;

  /// Las modalidades que se pueden elegir: **activas**, más la que la condición ya tiene
  /// —aunque la hayan desactivado después, porque quitarla del desplegable al corregir
  /// borraría el turno de una condición que sí lo tiene—.
  List<ModalidadDeTurno> get _modalidadesElegibles => [
    for (final m in _modalidades)
      if (m.estaActiva || m.id == _modalidadInicial) m,
  ];

  /// La rejilla semanal se pide **sólo** cuando el catálogo de la modalidad lo dice, y nunca
  /// en un concepto.
  bool get _pideRejilla =>
      _esDePersonal && _modalidad != null && !_modalidad!.pideHoraDeCambio;

  /// Y la hora de cambio es la otra mitad de la misma pregunta.
  bool get _pideHoraDeCambio =>
      _esDePersonal && (_modalidad?.pideHoraDeCambio ?? false);

  // 🚫 AQUÍ VIVÍA UN PRELLENADO, Y EL DUEÑO LO QUITÓ el 14 de noviembre de 2026, el mismo
  // día que lo pidió: elegir el turno llenaba la cantidad que se cobra con las personas que
  // ese rol necesita para cubrir 24/7. **Ese campo es DINERO** —el importe mensual del
  // servicio es cantidad × precio—, y las personas necesarias son una referencia de
  // operación: que una decidiera la otra mezclaba dos cosas que se parecen y no son la
  // misma. Ahora las personas **sólo se leen** junto al turno, en su explicación, y la
  // cantidad **se captura a mano siempre**.

  /// Los puestos que una condición admite: **operativos y activos**.
  ///
  /// ⚠️ Un puesto **administrativo** lo rechaza el servidor con un código propio
  /// (`puesto_no_operativo`), porque una condición comercial describe **una plaza que se
  /// presta**. Ofrecerlo aquí sería dejar elegir algo que va a fallar.
  List<Puesto> get _puestosElegibles => [
    for (final p in _puestos)
      if (p.tipo == 'operativo' && p.activo) p,
  ];

  /// Lo que se cobraría al mes con lo capturado, **sólo para enseñarlo**.
  ///
  /// ⚠️ **La cifra que se guarda la deriva el servidor** —el mismo `CASE` que suma los
  /// indicadores—: esto es la ayuda de quien captura, no una segunda verdad. Nulo cuando
  /// todavía no hay con qué calcularla, y entonces no se enseña un cero: «no hay dato» y
  /// «cobra cero» son cosas distintas.
  int? get _totalEnPantalla {
    final precio = _comoMenores(_precio.text);
    if (precio == null) return null;

    if (!_modo.esPorPersona) return precio;

    final cantidad = int.tryParse(_plazas.text.trim());
    if (cantidad == null || cantidad <= 0) return null;

    return precio * cantidad;
  }

  /// La cuenta escrita debajo del total: `3 × $15,000.00 · sin IVA`.
  String get _detalleDelTotal {
    final iva = _iva == TratamientoDeIva.noAplica
        ? 'no se factura'
        : 'sin IVA';

    if (!_modo.esPorPersona) return 'Total pactado · $iva';

    final cantidad = int.tryParse(_plazas.text.trim());
    final precio = _comoMenores(_precio.text);

    if (cantidad == null || precio == null) return 'Falta la cantidad o el precio · $iva';

    // ⚠️ `Monto` Y NO UN FORMATO PROPIO: es el mismo que pinta el importe del encabezado y
    // el de la tarjeta, así que las tres cifras se leen igual. Dos formatos de dinero en la
    // misma pantalla parecen dos números distintos.
    return '$cantidad × ${Monto(moneda: _moneda, menores: precio).enPantalla} · $iva';
  }

  /// La ayuda de la hora de cambio, **con el horario ya derivado**: «Turnos de 12 h: de
  /// 08:00 a 20:00».
  String _ayudaDeLaHoraDeCambio(ModalidadDeTurno modalidad) {
    final minuto = _horaDeCambio == null
        ? null
        : _horaDeCambio!.hour * 60 + _horaDeCambio!.minute;

    final ventana = modalidad.ventanaDelTurno(
      minuto,
      nocturno: _periodo == PeriodoDeTurno.nocturno,
    );

    if (ventana == null) {
      return 'A qué hora entra el turno diurno. De ahí sale el horario, así que no hay que '
          'capturarlo día por día.';
    }

    return 'Con esa hora, esta plaza va de $ventana.';
  }

  /// Si la modalidad trae rejilla **precargada** y la rejilla está vacía, se pone la de
  /// oficina: **lunes a viernes de 09:00 a 17:00**, ocho horas, y **editable**.
  ///
  /// 🚫 **No pisa lo capturado.** Sólo actúa cuando no hay ni un bloque: precargar encima de
  /// un horario que alguien escribió sería borrarle el trabajo.
  void _precargarRejillaSiHaceFalta() {
    if (_modalidad?.rejillaPrecargada != true) return;
    if (_horario.isNotEmpty) return;

    for (var dia = 1; dia <= 5; dia++) {
      _horario.add(
        _BloqueEditable(
          dia: dia,
          inicio: const TimeOfDay(hour: 9, minute: 0),
          fin: const TimeOfDay(hour: 17, minute: 0),
        ),
      );
    }
  }

  /// Crea un puesto **sin cerrar el formulario** y lo deja elegido.
  Future<void> _crearPuesto() async {
    final crear = widget.alCrearPuesto;
    if (crear == null) return;

    setState(() => _ocupado = true);

    final puesto = await crear();

    if (!mounted) return;

    setState(() {
      _ocupado = false;

      if (puesto != null) {
        _puestos = [..._puestos, puesto];
        _puestoId = puesto.id;
        _errores.remove('puesto');
      }
    });
  }

  /// Agrega las modalidades recomendadas y **deja el catálogo listo** aquí mismo.
  Future<void> _agregarModalidades() async {
    final agregar = widget.alAgregarModalidades;
    if (agregar == null) return;

    setState(() => _ocupado = true);

    final catalogo = await agregar();

    if (!mounted) return;

    setState(() {
      _ocupado = false;

      if (catalogo != null) {
        _modalidades = catalogo;
        _errores.remove('modalidad');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final modalidad = _modalidad;

    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- La línea, sólo al darla de alta --------------------------
              if (widget.pideNombre) ...[
                RisegSelect<TipoDeLinea>(
                  key: clavesDeCondicion.tipo,
                  label: 'Tipo de línea',
                  value: _tipo,
                  helperText: _tipo.esPersonal
                      ? 'Una plaza que se presta: lleva puesto, turno y horario.'
                      : 'Material, equipo u otro concepto: sin puesto, sin turno y '
                            'sin horario.',
                  helperMaxLines: 3,
                  items: [
                    for (final t in TipoDeLinea.values)
                      RisegSelectItem(value: t, label: t.nombre),
                  ],
                  onChanged: (v) => setState(() {
                    _tipo = v ?? TipoDeLinea.personal;

                    // AL PASAR A CONCEPTO SE LIMPIA LO QUE UN CONCEPTO NO TIENE, y no es
                    // cosmética: el servidor responde 422 por cada campo que sobra, y
                    // mandarlos escondidos sería pedir un rechazo por algo que la pantalla
                    // ya no enseña.
                    if (!_tipo.esPersonal) {
                      _puestoId = null;
                      _modalidadId = null;
                      _periodo = null;
                      _horaDeCambio = null;
                      _horario.clear();
                      _sueldo.clear();
                      _bono.clear();
                    }

                    _errores.clear();
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                RisegTextField(
                  key: clavesDeCondicion.nombre,
                  label: 'Nombre de la línea',
                  controller: _nombre,
                  errorText: _errores['nombre'],
                  helperText:
                      'Una línea por cada perfil, turno y costo diferente: «Guardias '
                      'intramuros», «Supervisor».',
                  helperMaxLines: 3,
                  onChanged: (_) => _limpiar('nombre'),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // --- Vigencia -------------------------------------------------
              RisegDateField(
                key: clavesDeCondicion.inicio,
                label: 'Desde',
                value: _inicio,
                errorText: _errores['inicio'],
                helperText: 'El primer día que cobra este precio.',
                onChanged: (v) => setState(() {
                  _inicio = v;
                  _errores.remove('inicio');
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegDateField(
                key: clavesDeCondicion.termino,
                label: 'Hasta (opcional)',
                value: _termino,
                errorText: _errores['termino'],
                // ⚠️ `helperMaxLines` NO ES DECORACIÓN: sin él esta ayuda de tres
                // líneas se cortaba con puntos suspensivos —lo encontró el dueño en su
                // prueba del 18-nov-2026— porque el campo de fecha no lo pasaba a la
                // decoración y Flutter recorta a UNA línea por omisión.
                helperText:
                    'El último día que cobra, incluido. Déjalo vacío si no tiene '
                    'fecha de fin: lo normal es cerrarla o programar la siguiente '
                    'cuando llegue el momento.',
                helperMaxLines: 3,
                onChanged: (v) => setState(() {
                  _termino = v;
                  _errores.remove('termino');
                }),
              ),
              const SizedBox(height: AppSpacing.md),

              // --- Qué se presta --------------------------------------------
              if (_esDePersonal) ...[
                RisegSelect<String>(
                  key: clavesDeCondicion.puesto,
                  label: 'Puesto',
                  value: _puestoId,
                  errorText: _errores['puesto'],
                  helperText: _puestosElegibles.isEmpty
                      ? 'Todavía no hay puestos operativos activos.'
                      : 'Sólo puestos operativos: una condición describe una plaza '
                            'que se presta.',
                  helperMaxLines: 2,
                  items: [
                    for (final p in _puestosElegibles)
                      RisegSelectItem(value: p.id, label: p.nombre),
                  ],
                  onChanged: (v) => setState(() {
                    _puestoId = v;
                    _errores.remove('puesto');
                  }),
                ),
                // 🚫 CREAR EL PUESTO AQUÍ MISMO, sin cerrar el formulario. Antes la
                // pantalla sólo decía dónde se daban de alta, y seguir ese consejo
                // significaba salir y **perder todo lo capturado**.
                if (widget.alCrearPuesto != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RisegButton(
                      key: clavesDeCondicion.crearPuesto,
                      label: 'Crear un puesto',
                      icon: Icons.add,
                      variant: RisegButtonVariant.ghost,
                      onPressed: _ocupado ? null : _crearPuesto,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
              const SizedBox(height: AppSpacing.md),
              // --- El turno, sólo en una línea de personal -------------------
              if (_esDePersonal) ...[
                RisegSelect<String?>(
                  key: clavesDeCondicion.modalidad,
                  label: 'Modalidad de turno',
                  value: _modalidadId,
                  errorText: _errores['modalidad'],
                  // ⚠️ LA EXPLICACIÓN DE LA MODALIDAD SE ENSEÑA AQUÍ, y es la mitad del
                  // trabajo de la 0064: lleva cuántas personas hacen falta para cubrir un
                  // puesto 24/7, que es el número que de verdad se usa al cotizar.
                  helperText: modalidad?.explicacion ?? _ayudaDeModalidades,
                  helperMaxLines: 4,
                  // 🚫 YA NO HAY «SIN MODALIDAD», y es la corrección del dueño del
                  // 18-nov-2026: en RISEG ONE la modalidad siempre fue obligatoria, y aquí
                  // era opcional porque la 0019 la dejó nullable — nadie lo decidió.
                  items: [
                    for (final m in _modalidadesElegibles)
                      RisegSelectItem<String?>(value: m.id, label: m.nombre),
                  ],
                  onChanged: (v) => setState(() {
                    _modalidadId = v;

                    // Al cambiar de modalidad, lo que la nueva NO usa se borra. Dejarlo
                    // puesto mandaría un campo sobrante y el servidor contestaría 422 por
                    // algo que la pantalla ya había escondido.
                    if (_modalidad?.pidePeriodo != true) _periodo = null;
                    if (_modalidad?.pideHoraDeCambio != true) _horaDeCambio = null;
                    if (_modalidad?.pideHoraDeCambio == true) _horario.clear();

                    _precargarRejillaSiHaceFalta();

                    _errores
                      ..remove('modalidad')
                      ..remove('periodo')
                      ..remove('horaDeCambio');

                    // 🚫 Y NO SE TOCA LA CANTIDAD QUE SE COBRA. Es dinero y se captura a
                    // mano: ver el comentario de arriba.
                  }),
                ),
                // EL CATÁLOGO VACÍO SE ARREGLA AQUÍ MISMO. Con la modalidad obligatoria,
                // una empresa sin catálogo no podría capturar ni una condición.
                if (_modalidadesElegibles.isEmpty &&
                    widget.alAgregarModalidades != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RisegButton(
                      key: clavesDeCondicion.agregarModalidades,
                      label: 'Agregar las modalidades recomendadas',
                      icon: Icons.playlist_add,
                      variant: RisegButtonVariant.ghost,
                      onPressed: _ocupado ? null : _agregarModalidades,
                    ),
                  ),
                ],
                if (modalidad?.pidePeriodo == true) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegSelect<PeriodoDeTurno>(
                    key: clavesDeCondicion.periodo,
                    label: 'Periodo del turno',
                    value: _periodo,
                    errorText: _errores['periodo'],
                    helperText:
                        '«${modalidad!.nombre}» no rota, así que la plaza es de día o '
                        'de noche — y se cobra distinto.',
                    helperMaxLines: 3,
                    items: [
                      for (final p in PeriodoDeTurno.values)
                        RisegSelectItem(value: p, label: p.nombre),
                    ],
                    onChanged: (v) => setState(() {
                      _periodo = v;
                      _errores.remove('periodo');
                    }),
                  ),
                ],
                // LA HORA DE CAMBIO, cuando el turno se captura así: UNA sola hora, y de
                // ella sale el horario. 🚫 Y entonces la rejilla semanal no aparece —el
                // ciclo de un 24×24 no cabe en una semana—.
                if (_pideHoraDeCambio) ...[
                  const SizedBox(height: AppSpacing.md),
                  RisegTimeField(
                    key: clavesDeCondicion.horaDeCambio,
                    label: 'Hora de cambio de turno',
                    value: _horaDeCambio,
                    errorText: _errores['horaDeCambio'],
                    helperText: _ayudaDeLaHoraDeCambio(modalidad!),
                    onChanged: (v) => setState(() {
                      _horaDeCambio = v;
                      _errores.remove('horaDeCambio');
                    }),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
              ],

              // --- Cuánto ---------------------------------------------------
              //
              // CÓMO SE COTIZÓ, lo primero del dinero: de aquí depende qué precio se pide y
              // cómo se calcula el total. Decisión del dueño del 18-nov-2026.
              RisegSelect<ModoDeCotizacion>(
                key: clavesDeCondicion.modo,
                label: 'Cómo se cotizó',
                value: _modo,
                helperText: _modo.esPorPersona
                    ? 'El total mensual sale de multiplicar: cantidad × precio por persona.'
                    : 'Se pactó un total mensual. La cantidad se sigue capturando —la '
                          'operación necesita saber cuántos— pero no multiplica.',
                helperMaxLines: 3,
                items: [
                  for (final m in ModoDeCotizacion.values)
                    RisegSelectItem(value: m, label: m.nombre),
                ],
                onChanged: (v) => setState(() {
                  _modo = v ?? ModoDeCotizacion.porPersona;
                  _errores.remove('precio');
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: clavesDeCondicion.plazas,
                // 🚫 **«NÚMERO DE ELEMENTOS», nombre del dueño del 19-nov-2026, Y EL ANTERIOR
                // LE HIZO TECLEAR DINERO EN ÉL.** Se llamó «Plazas», luego «Personas en el
                // puesto» y luego «Cantidad que se cobra» —el 14-nov, buscando decir que
                // multiplica el precio—, y en su prueba en pantalla escribió **36000** en este
                // campo creyendo que pedía un importe: «cantidad» en español es **cuánto
                // dinero** tanto como **cuántas cosas**, y junto a un precio gana el dinero.
                //
                // «Elementos» no tiene esa ambigüedad y además es el término que la propia
                // tarjeta ya usaba al leerlo —«2 elementos»—: la pantalla pedía una cosa con
                // un nombre y la mostraba con otro. Lo que multiplica se dice **en la ayuda**,
                // que es donde cabe sin convertir la etiqueta en una frase.
                label: _esDePersonal ? 'Número de elementos' : 'Cantidad',
                controller: _plazas,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _errores['plazas'],
                helperText: _modo.esPorPersona
                    ? (_esDePersonal
                          ? 'Cuántas personas cubre esta línea. Si se cotizó por '
                                'persona, multiplica el precio.'
                          : 'Cuántas unidades se cobran. Multiplica el precio.')
                    : 'Con un total mensual pactado, esta cantidad NO multiplica: se '
                          'registra porque la operación necesita saberla.',
                helperMaxLines: 3,
                onChanged: (_) => setState(() => _errores.remove('plazas')),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: clavesDeCondicion.precio,
                // EL NOMBRE DEL CAMPO LO DICE EL MODO, no una etiqueta fija: «Precio por
                // plaza» no significaba nada cuando lo pactado es un total. El dueño pidió
                // además que dijera «persona» y no «plaza».
                label: switch ((_modo.esPorPersona, _esDePersonal)) {
                  (true, true) => 'Precio por persona',
                  (true, false) => 'Precio unitario',
                  (false, _) => 'Precio total mensual',
                },
                controller: _precio,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                errorText: _errores['precio'],
                // 🚫 SIN ASTERISCOS: el `helperText` es texto plano y los dos que había se
                // veían literales en pantalla —lo encontró el dueño el 18-nov-2026—.
                helperText: _modo.esPorPersona
                    ? 'Mensual y por cada uno, en $_moneda. Cero es válido: existe el '
                          'servicio de cortesía o incluido.'
                    : 'Lo que se cobra al mes en total, en $_moneda. Cero es válido: '
                          'existe el servicio de cortesía o incluido.',
                helperMaxLines: 3,
                onChanged: (_) => setState(() => _errores.remove('precio')),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: RisegSelect<String>(
                      key: clavesDeCondicion.moneda,
                      label: 'Moneda',
                      value: _moneda,
                      items: const [
                        RisegSelectItem(value: 'MXN', label: 'MXN · pesos'),
                        RisegSelectItem(value: 'USD', label: 'USD · dólares'),
                      ],
                      onChanged: (v) => setState(() => _moneda = v ?? 'MXN'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: RisegSelect<TratamientoDeIva>(
                      key: clavesDeCondicion.iva,
                      label: 'IVA',
                      value: _iva,
                      // 🚫 «No aplica» NO ES UN HUECO: hay servicios que se cobran sin
                      // documento fiscal, y el dueño lo dijo así. Tratar el IVA como
                      // obligatorio obligaría a elegir una respuesta falsa.
                      helperText: _iva == TratamientoDeIva.noAplica
                          ? 'Este servicio no se factura.'
                          : null,
                      items: [
                        for (final t in TratamientoDeIva.values)
                          RisegSelectItem(value: t, label: t.nombre),
                      ],
                      onChanged: (v) =>
                          setState(() => _iva = v ?? TratamientoDeIva.masIva),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // EL TOTAL MENSUAL, GRANDE Y CLARO, en los dos modos: es la cifra por la que
              // se pregunta, y el dueño pidió que se viera. Se calcula aquí sólo para
              // ENSEÑARLA mientras se captura; la que se guarda la deriva el servidor.
              _TotalMensual(
                key: clavesDeCondicion.total,
                menores: _totalEnPantalla,
                moneda: _moneda,
                detalle: _detalleDelTotal,
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: clavesDeCondicion.descripcion,
                label: 'Descripción (opcional)',
                controller: _descripcion,
                maxLines: 2,
                errorText: _errores['descripcion'],
                helperText: 'Lo que hace falta decir de esta línea en particular.',
                onChanged: (_) => _limpiar('descripcion'),
              ),
              const SizedBox(height: AppSpacing.md),
              // OBSERVACIONES: el campo que RISEG ONE siempre tuvo y que se había perdido
              // en la mudanza. Lo encontró la tabla de paridad del 18-nov-2026.
              RisegTextField(
                key: clavesDeCondicion.observaciones,
                label: 'Observaciones (opcional)',
                controller: _observaciones,
                maxLines: 2,
                errorText: _errores['observaciones'],
                helperText: 'Lo que conviene recordar de cómo se pactó.',
                onChanged: (_) => _limpiar('observaciones'),
              ),

              // --- El horario -----------------------------------------------
              //
              // 🚫 SÓLO CUANDO EL CATÁLOGO DE LA MODALIDAD LO DICE. Antes se enseñaba
              // SIEMPRE —en RISEG ONE sólo aparece en «Personalizado»— y en un turno
              // rotativo la rejilla ni siquiera puede representar el ciclo.
              if (_pideRejilla) ...[
                const SizedBox(height: AppSpacing.lg),
                _RejillaSemanal(
                  bloques: _horario,
                  alCambiar: () => setState(() {}),
                ),
              ],

              // --- El sueldo de referencia, sólo en la primera ---------------
              if (widget.pideSueldoDeReferencia && _esDePersonal) ...[
                const SizedBox(height: AppSpacing.lg),
                RisegFormSection(
                  title: 'Sueldo de referencia (para ofrecer el puesto)',
                  description:
                      'Lo que se ofrece al reclutar para esta línea. 🚫 NO es el '
                      'sueldo de nadie: pre-llena el formulario al asignar personal, '
                      'y el sueldo real de cada persona vive en su asignación. '
                      'Se puede cambiar después sin tocar el precio del cliente.',
                  children: [
                    RisegTextField(
                      key: clavesDeCondicion.sueldo,
                      label: 'Sueldo mensual (opcional)',
                      controller: _sueldo,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      errorText: _errores['sueldo'],
                      helperText:
                          'Déjalo vacío si no hay cifra. Vacío NO es cero: un cero '
                          'se leería como «se ofrece el puesto por nada».',
                      helperMaxLines: 3,
                      onChanged: (_) => _limpiar('sueldo'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    RisegTextField(
                      key: clavesDeCondicion.bono,
                      label: 'Bono (opcional)',
                      controller: _bono,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      errorText: _errores['bono'],
                      helperText: 'Cero sí es una respuesta: «este puesto no lleva bono».',
                      helperMaxLines: 2,
                      onChanged: (_) => _limpiar('bono'),
                    ),
                  ],
                ),
              ],

              // --- El motivo, sólo al corregir la vigente --------------------
              if (widget.pideMotivo) ...[
                const SizedBox(height: AppSpacing.lg),
                RisegTextField(
                  key: clavesDeCondicion.motivo,
                  label: 'Motivo de la corrección',
                  controller: _motivo,
                  maxLines: 2,
                  errorText: _errores['motivo'],
                  helperText:
                      'Esta condición está cobrando, así que la corrección queda en '
                      'la bitácora con su razón. En seis meses alguien preguntará.',
                  helperMaxLines: 3,
                  onChanged: (_) => _limpiar('motivo'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: clavesDeCondicion.guardar,
          onPressed: _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  /// El tope de la descripción. **Lo fija el servidor**, no la pantalla: su validación
  /// rechaza por encima, así que un número mayor aquí dejaría pasar un formulario para que
  /// el servidor lo rechazara después.
  static const int _maxDescripcion = 500;

  /// El techo de la cantidad que se cobra, **el mismo que el servidor** (0066).
  static const int _maxCantidad = 999;

  /// Desde cuántos se pregunta «¿seguro?» antes de guardar.
  ///
  /// 🚫 **DECISIÓN DEL DUEÑO, 18-nov-2026: cincuenta.** Capturó 30 000 personas por 15 000
  /// pesos —450 millones— y nada preguntó. El techo y la confirmación son **dos cosas
  /// distintas**: el techo impide lo imposible, y esto hace mirar lo improbable.
  static const int _cantidadQueConfirma = 50;

  static const String _ayudaDeModalidades =
      'Cada modalidad trae su explicación, con cuántas personas hacen falta para '
      'cubrir un puesto 24/7. Se editan en el catálogo de turnos.';

  void _limpiar(String campo) {
    if (_errores.containsKey(campo)) setState(() => _errores.remove(campo));
  }

  bool _mismoHorario() {
    if (_horario.length != _horarioInicial.length) return false;

    for (var i = 0; i < _horario.length; i++) {
      if (_horario[i] != _horarioInicial[i]) return false;
    }

    return true;
  }

  // =========================================================================
  // Guardar
  // =========================================================================

  Future<void> _guardar() async {
    final errores = <String, String>{};

    if (widget.pideNombre && _nombre.text.trim().isEmpty) {
      errores['nombre'] = 'Ponle nombre a la línea.';
    }

    if (_inicio == null) errores['inicio'] = 'Falta la fecha desde la que cobra.';

    if (_inicio != null && _termino != null && _termino!.isBefore(_inicio!)) {
      errores['termino'] = 'No puede terminar antes de empezar.';
    }

    // LO QUE SÓLO EXISTE EN UNA LÍNEA DE PERSONAL. En un concepto no se pide ninguna de las
    // tres cosas, y mandarlas respondería 422.
    if (_esDePersonal) {
      if (_puestoId == null) errores['puesto'] = 'Elige el puesto de la plaza.';

      // 🚫 OBLIGATORIA DESDE LA 0066: antes se podía guardar «Sin modalidad» y el servidor
      // lo aceptaba, que es la deriva que la tabla de paridad encontró.
      if (_modalidadId == null) {
        errores['modalidad'] = _modalidadesElegibles.isEmpty
            ? 'No hay modalidades en el catálogo: agrega las recomendadas.'
            : 'Elige la modalidad del turno.';
      }

      if (_modalidad?.pidePeriodo == true && _periodo == null) {
        errores['periodo'] = 'Di si la plaza es diurna o nocturna.';
      }

      if (_pideHoraDeCambio && _horaDeCambio == null) {
        errores['horaDeCambio'] = 'Di a qué hora entra el turno diurno.';
      }
    }

    final plazas = int.tryParse(_plazas.text.trim());

    if (plazas == null || plazas <= 0) {
      errores['plazas'] = 'Tiene que ser un número mayor que cero.';
    }

    // EL TECHO, el mismo que el servidor: 999. Decirlo aquí ahorra un viaje, y el servidor
    // lo vuelve a comprobar porque la pantalla no es una garantía.
    if (plazas != null && plazas > _maxCantidad) {
      errores['plazas'] = 'Son demasiados para una sola línea: repártelos en varias.';
    }

    final precio = _comoMenores(_precio.text);

    if (precio == null) {
      errores['precio'] = 'Escribe el precio, por ejemplo 15000 o 15000.50.';
    }

    // ⚠️ EL MENSAJE NO DICE EL NÚMERO, y no es por el candado de textos —que lo cazó
    // porque «500» se parece a un código de estado—: es que decirle a alguien «admite
    // hasta 500 caracteres» le hace CONTAR. Lo que necesita saber es que se pasó y que
    // tiene que recortar. El tope sigue siendo el del servidor, en la constante.
    if (_descripcion.text.trim().length > _maxDescripcion) {
      errores['descripcion'] = 'Se pasó de largo: recórtala un poco.';
    }

    // EL SUELDO Y EL BONO, cada uno con su regla: el sueldo no admite cero y el bono sí.
    int? sueldo;
    int? bono;

    if (widget.pideSueldoDeReferencia) {
      final textoDelSueldo = _sueldo.text.trim();
      final textoDelBono = _bono.text.trim();

      if (textoDelSueldo.isNotEmpty) {
        sueldo = _comoMenores(textoDelSueldo);

        if (sueldo == null || sueldo <= 0) {
          errores['sueldo'] = 'Tiene que ser mayor que cero. Si no hay cifra, déjalo vacío.';
        }
      }

      if (textoDelBono.isNotEmpty) {
        bono = _comoMenores(textoDelBono);

        if (bono == null) errores['bono'] = 'Escribe una cantidad, por ejemplo 1000.';

        // UN BONO SIN SUELDO NO SE PUEDE GUARDAR, y el servidor lo rechazaría: la fila
        // lleva el sueldo como obligatorio. Se dice aquí para no gastar un viaje.
        if (sueldo == null && errores['sueldo'] == null) {
          errores['sueldo'] = 'Si capturas un bono, el sueldo también hace falta.';
        }
      }
    }

    if (widget.pideMotivo && _motivo.text.trim().isEmpty) {
      errores['motivo'] = 'Di por qué se corrige: es la condición que está cobrando.';
    }

    // LOS BLOQUES, cada uno completo o ninguno. Cero bloques es válido.
    for (final bloque in _horario) {
      if (bloque.inicio == null || bloque.fin == null) {
        errores['horario'] = 'Hay un bloque sin hora de inicio o de fin.';
        break;
      }
    }

    if (errores.isNotEmpty) {
      setState(() {
        _errores
          ..clear()
          ..addAll(errores);
      });

      if (errores['horario'] case final mensaje?) {
        RisegFeedback.showError(context, mensaje);
      }

      return;
    }

    // LA CONFIRMACIÓN DE UNA CANTIDAD GRANDE, con el total escrito dentro: lo que el dueño
    // pidió al ver pasar 450 millones sin una pregunta.
    if (plazas! >= _cantidadQueConfirma) {
      final total = _totalEnPantalla;

      final seguro = await RisegDialog.showConfirmation(
        context: context,
        title: '¿$plazas en una sola línea?',
        message: total == null
            ? 'Son muchos para una sola línea. Revisa la cantidad antes de guardar.'
            : 'Esta línea cobraría '
                  '${Monto(moneda: _moneda, menores: total).enPantalla} al mes. '
                  'Revisa la cantidad y el precio antes de guardar.',
        confirmLabel: 'Sí, es correcto',
        cancelLabel: 'Volver a revisar',
      );

      if (seguro != true || !mounted) return;
    }

    if (!mounted) return;

    Navigator.of(context).pop(
      ResultadoDeCondicion(
        nombre: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
        tipo: _tipo,
        condicion: CondicionEnviada(
          // `deFechaLocal` y no el constructor a secas: lo que la persona eligió es un día
          // del calendario, no un instante, y aplicarle el desplazamiento de zona lo
          // movería un día.
          inicio: DiaDeNegocio.deFechaLocal(_inicio!),
          termino: _termino == null ? null : DiaDeNegocio.deFechaLocal(_termino!),
          puestoId: _puestoId,
          modalidadId: _modalidadId,
          periodo: _periodo,
          horaDeCambioMinuto: _horaDeCambio == null
              ? null
              : _horaDeCambio!.hour * 60 + _horaDeCambio!.minute,
          plazas: plazas,
          modo: _modo,
          // UNO DE LOS DOS, SEGÚN EL MODO: el otro viaja nulo. El mismo campo de texto
          // alimenta los dos porque sólo uno se enseña a la vez.
          precioUnitarioMenores: _modo.esPorPersona ? precio : null,
          totalMensualMenores: _modo.esPorPersona ? null : precio,
          moneda: _moneda,
          iva: _iva,
          descripcion: _descripcion.text.trim().isEmpty
              ? null
              : _descripcion.text.trim(),
          observaciones: _observaciones.text.trim().isEmpty
              ? null
              : _observaciones.text.trim(),
          horarios: [
            for (final b in _horario)
              HorarioEnviado(
                dia: b.dia,
                inicioMinuto: b.inicio!.hour * 60 + b.inicio!.minute,
                finMinuto: _finEnMinutos(b.fin!),
              ),
          ],
        ),
        sueldoDeReferenciaMenores: sueldo,
        bonoDeReferenciaMenores: bono,
        motivo: widget.pideMotivo ? _motivo.text.trim() : null,
      ),
    );
  }

  /// ⚠️ **00:00 COMO FIN SIGNIFICA 1440**, la medianoche como FINAL del día.
  ///
  /// El reloj del sistema no sabe decir «24:00» y el contrato exige `1..1440`, así que un
  /// cero se mandaría como un fin inválido. Convertirlo aquí es lo que hace que «de 20:00 a
  /// medianoche» se pueda capturar.
  static int _finEnMinutos(TimeOfDay fin) {
    final minutos = fin.hour * 60 + fin.minute;

    return minutos == 0 ? 1440 : minutos;
  }

  static DateTime? _comoFecha(DiaDeNegocio? dia) => dia?.comoFechaLocal;

  static TimeOfDay _comoHora(int minuto) {
    // 1440 vuelve a ser 00:00 en el reloj, que es cómo se capturó.
    final normalizado = minuto % 1440;

    return TimeOfDay(hour: normalizado ~/ 60, minute: normalizado % 60);
  }

  /// `15000.50` → `1500050`. Nulo si el texto no es una cantidad.
  ///
  /// Acepta hasta dos decimales y **rechaza tres**: `15000.555` no es una cantidad en pesos,
  /// y redondearla en silencio guardaría un precio que nadie escribió.
  static int? _comoMenores(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty) return null;

    final partes = limpio.split('.');
    if (partes.length > 2) return null;

    final enteros = int.tryParse(partes[0].isEmpty ? '0' : partes[0]);
    if (enteros == null || enteros < 0) return null;

    if (partes.length == 1) return enteros * 100;

    final decimales = partes[1];
    if (decimales.length > 2) return null;

    final centavos = int.tryParse(decimales.padRight(2, '0'));
    if (centavos == null) return null;

    return enteros * 100 + centavos;
  }

  /// `1500050` → `15000.50`, para rellenar el campo al corregir.
  static String _comoTexto(int menores) {
    final centavos = menores % 100;

    return centavos == 0
        ? (menores ~/ 100).toString()
        : '${menores ~/ 100}.${centavos.toString().padLeft(2, '0')}';
  }
}

/// El **total mensual**, grande y claro, con la cuenta debajo.
///
/// 🚫 **Es la cifra por la que se pregunta**, y el dueño pidió verla en los dos modos: con
/// un precio por persona nadie multiplica de cabeza, y con un total pactado hay que poder
/// comprobar que es el que se negoció.
///
/// ⚠️ **Y no es la verdad: la calcula el servidor.** Esto acompaña a quien captura. Cuando
/// falta un dato **no enseña cero**, porque «no hay dato» y «cobra cero» son cosas
/// distintas y las dos existen.
class _TotalMensual extends StatelessWidget {
  const _TotalMensual({
    required this.menores,
    required this.moneda,
    required this.detalle,
    super.key,
  });

  final int? menores;
  final String moneda;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL MENSUAL',
            style: AppTypography.label.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            menores == null
                ? 'Falta un dato'
                : Monto(moneda: moneda, menores: menores!).enPantalla,
            style: AppTypography.heading2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(detalle, style: AppTypography.caption.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }
}

/// Un bloque del horario mientras se edita. Mutable a propósito: es estado de formulario.
class _BloqueEditable {
  _BloqueEditable({required this.dia, this.inicio, this.fin});

  int dia;
  TimeOfDay? inicio;
  TimeOfDay? fin;

  @override
  bool operator ==(Object other) =>
      other is _BloqueEditable &&
      other.dia == dia &&
      other.inicio == inicio &&
      other.fin == fin;

  @override
  int get hashCode => Object.hash(dia, inicio, fin);
}

/// El editor del horario semanal: bloques que se añaden y se quitan.
///
/// ## Por qué bloques y no una rejilla de casillas
///
/// Un turno de 24 horas cruza la medianoche y **dos días contiguos no son dos bloques**: son
/// uno que empieza un día y acaba el siguiente. Una rejilla de casillas por hora no puede
/// expresar eso sin inventar una convención, y la convención es exactamente lo que el
/// servidor ya decidió —`inicio == fin` son 24 horas, `fin` menor que `inicio` cruza—.
///
/// **Cero bloques es válido** y significa «sin horario semanal fijo»: un servicio por
/// disponibilidad o bolsa de horas no tiene rejilla. Exigir al menos uno obligaría a inventar
/// un bloque falso de 00:00 a 24:00, que es almacenar un dato que nadie distinguirá después
/// del verdadero.
class _RejillaSemanal extends StatelessWidget {
  const _RejillaSemanal({required this.bloques, required this.alCambiar});

  final List<_BloqueEditable> bloques;
  final VoidCallback alCambiar;

  static const List<String> _dias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  @override
  Widget build(BuildContext context) => RisegFormSection(
    title: 'Horario semanal',
    description:
        'Un bloque por cada tramo que se cubre. Un día sin bloque es descanso. '
        'Si no hay horario fijo —disponibilidad, bolsa de horas—, déjalo vacío.',
    children: [
      if (bloques.isEmpty)
        const Text('Sin horario semanal fijo.', style: AppTypography.caption)
      else
        for (var i = 0; i < bloques.length; i++) ...[
          _FilaDeBloque(
            bloque: bloques[i],
            numero: i + 1,
            dias: _dias,
            alCambiar: alCambiar,
            alQuitar: () {
              bloques.removeAt(i);
              alCambiar();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      const SizedBox(height: AppSpacing.sm),
      RisegButton(
        label: 'Añadir bloque',
        icon: Icons.add,
        variant: RisegButtonVariant.secondary,
        size: RisegButtonSize.compact,
        onPressed: () {
          bloques.add(
            _BloqueEditable(
              // El día siguiente al último, para que capturar una semana sea pulsar siete
              // veces y ajustar las horas, no elegir el día cada vez.
              dia: bloques.isEmpty ? 1 : (bloques.last.dia % 7) + 1,
              inicio: bloques.lastOrNull?.inicio,
              fin: bloques.lastOrNull?.fin,
            ),
          );

          alCambiar();
        },
      ),
    ],
  );
}

class _FilaDeBloque extends StatelessWidget {
  const _FilaDeBloque({
    required this.bloque,
    required this.numero,
    required this.dias,
    required this.alCambiar,
    required this.alQuitar,
  });

  final _BloqueEditable bloque;
  final int numero;
  final List<String> dias;
  final VoidCallback alCambiar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final cruza =
        bloque.inicio != null &&
        bloque.fin != null &&
        (_minutos(bloque.fin!) <= _minutos(bloque.inicio!));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: RisegSelect<int>(
            label: 'Día $numero',
            value: bloque.dia,
            items: [
              for (var d = 1; d <= 7; d++)
                RisegSelectItem(value: d, label: dias[d - 1]),
            ],
            onChanged: (v) {
              bloque.dia = v ?? bloque.dia;
              alCambiar();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 3,
          child: RisegTimeField(
            label: 'Entra',
            value: bloque.inicio,
            onChanged: (v) {
              bloque.inicio = v;
              alCambiar();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 3,
          child: RisegTimeField(
            label: 'Sale',
            value: bloque.fin,
            // ⚠️ LA REGLA DE 00:00 SE DICE EN PANTALLA, porque es la clase de cosa que
            // alguien descubriría por accidente: el reloj no sabe decir «24:00».
            helperText: cruza
                ? 'Termina al día siguiente.'
                : '00:00 es la medianoche del final del día.',
            onChanged: (v) {
              bloque.fin = v;
              alCambiar();
            },
          ),
        ),
        IconButton(
          onPressed: alQuitar,
          icon: const Icon(Icons.close),
          tooltip: 'Quitar este bloque',
        ),
      ],
    );
  }

  static int _minutos(TimeOfDay hora) => hora.hour * 60 + hora.minute;
}

// ===========================================================================
// Cerrar la condición vigente
// ===========================================================================

/// Lo que el diálogo de cierre devuelve.
class CierreDeCondicion {
  const CierreDeCondicion({required this.termino, required this.motivo});

  final DiaDeNegocio termino;
  final String motivo;
}

/// **Dejar de cobrar**: la fecha del último día y por qué.
///
/// ## 🚫 La fecha no se asume hoy, y el motivo no es opcional
///
/// Cerrar con el día equivocado es **facturar un mes de más o de menos**, y el día en que
/// algo dejó de operar lo sabe quien lo cierra, no el reloj del servidor. El motivo queda en
/// la bitácora: «se cerró» sin razón no se puede auditar.
///
/// ## Y se dice qué NO es
///
/// Esto **no retira la línea**: la línea sigue existiendo y se le puede poner otra condición
/// después. Lo que deja de pasar es que cobre.
Future<CierreDeCondicion?> mostrarDialogoDeCierre(
  BuildContext context, {
  required String nombreDeLaLinea,
  required DiaDeNegocio hoy,
  required DiaDeNegocio? inicioDeLaVigente,
}) {
  DateTime? termino = hoy.comoFechaLocal;
  final motivo = TextEditingController();
  String? errorDeFecha;
  String? errorDeMotivo;

  // ⚠️ EL SELECTOR NO DEJA ELEGIR UN DÍA ANTERIOR AL INICIO DE LA VIGENTE, porque el
  // servidor lo rechaza con su propio código. Impedirlo aquí ahorra el viaje; el 422 sigue
  // siendo la garantía, no esto.
  final minima = inicioDeLaVigente?.comoFechaLocal;

  return RisegDialog.showForm<CierreDeCondicion>(
    context: context,
    title: 'Dejar de cobrar «$nombreDeLaLinea»',
    confirmLabel: 'Cerrar la condición',
    cancelLabel: 'Cancelar',
    destructive: true,
    contentBuilder: (_) => StatefulBuilder(
      builder: (contexto, refrescar) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'La condición se queda entera en el historial con su precio: lo único '
            'que cambia es que gana fecha de término.\n\n'
            'Esto NO retira la línea: se le puede poner otra condición después.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          RisegDateField(
            label: 'Último día que cobra',
            value: termino,
            firstDate: minima,
            errorText: errorDeFecha,
            helperText: 'Incluido: ese día todavía se factura.',
            onChanged: (v) => refrescar(() {
              termino = v;
              errorDeFecha = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          RisegTextField(
            label: 'Motivo',
            controller: motivo,
            maxLines: 2,
            errorText: errorDeMotivo,
            helperText: 'Por qué deja de cobrar. Queda en la bitácora.',
            onChanged: (_) {
              if (errorDeMotivo != null) refrescar(() => errorDeMotivo = null);
            },
          ),
        ],
      ),
    ),
    onConfirm: () async {
      final fecha = termino;
      final razon = motivo.text.trim();

      if (fecha == null) errorDeFecha = 'Falta la fecha.';
      if (razon.isEmpty) errorDeMotivo = 'Di por qué deja de cobrar.';

      if (fecha == null || razon.isEmpty) return null;

      return CierreDeCondicion(
        termino: DiaDeNegocio.deFechaLocal(fecha),
        motivo: razon,
      );
    },
  ).whenComplete(motivo.dispose);
}
