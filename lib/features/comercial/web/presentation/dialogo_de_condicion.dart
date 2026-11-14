import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../../../organizacion/web/modelos/puesto.dart';
import '../datos/condiciones_repositorio_http.dart';
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
  Key get puesto => const Key('condicion-puesto');
  Key get modalidad => const Key('condicion-modalidad');
  Key get periodo => const Key('condicion-periodo');
  Key get plazas => const Key('condicion-plazas');
  Key get precio => const Key('condicion-precio');
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
    this.sueldoDeReferenciaMenores,
    this.bonoDeReferenciaMenores,
    this.motivo,
  });

  final CondicionEnviada condicion;

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
  });

  final String titulo;
  final List<ModalidadDeTurno> modalidades;
  final List<Puesto> puestos;
  final DiaDeNegocio hoy;
  final GuardiaDeSalida guardia;
  final bool pideSueldoDeReferencia;
  final bool pideMotivo;
  final CondicionComercial? existente;

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
      _inicio != _inicioInicial ||
      _termino != _terminoInicial ||
      _puestoId != _puestoInicial ||
      _modalidadId != _modalidadInicial ||
      _periodo != _periodoInicial ||
      _plazas.text.trim() != _plazasInicial ||
      _precio.text.trim() != _precioInicial ||
      _moneda != _monedaInicial ||
      _iva != _ivaInicial ||
      _descripcion.text.trim() != _descripcionInicial ||
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
  late final String _plazasInicial = widget.existente?.plazas.toString() ?? '';
  late final String _precioInicial = widget.existente == null
      ? ''
      : _comoTexto(widget.existente!.precioUnitarioMenores);
  late final String _monedaInicial = widget.existente?.moneda ?? 'MXN';
  late final TratamientoDeIva _ivaInicial =
      widget.existente?.tratamientoDeIva ?? TratamientoDeIva.masIva;
  late final String _descripcionInicial = widget.existente?.descripcion ?? '';
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
  String _moneda = 'MXN';
  TratamientoDeIva _iva = TratamientoDeIva.masIva;

  final _plazas = TextEditingController();
  final _precio = TextEditingController();
  final _descripcion = TextEditingController();
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
    _moneda = _monedaInicial;
    _iva = _ivaInicial;
    _plazas.text = _plazasInicial;
    _precio.text = _precioInicial;
    _descripcion.text = _descripcionInicial;

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
    _plazas.dispose();
    _precio.dispose();
    _descripcion.dispose();
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
      widget.modalidades.where((m) => m.id == _modalidadId).firstOrNull;

  /// Los puestos que una condición admite: **operativos y activos**.
  ///
  /// ⚠️ Un puesto **administrativo** lo rechaza el servidor con un código propio
  /// (`puesto_no_operativo`), porque una condición comercial describe **una plaza que se
  /// presta**. Ofrecerlo aquí sería dejar elegir algo que va a fallar.
  List<Puesto> get _puestosElegibles => [
    for (final p in widget.puestos)
      if (p.tipo == 'operativo' && p.activo) p,
  ];

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
                helperText:
                    'El último día que cobra, incluido. Déjalo vacío si no tiene '
                    'fecha de fin: lo normal es cerrarla o programar la siguiente '
                    'cuando llegue el momento.',
                onChanged: (v) => setState(() {
                  _termino = v;
                  _errores.remove('termino');
                }),
              ),
              const SizedBox(height: AppSpacing.md),

              // --- Qué se presta --------------------------------------------
              RisegSelect<String>(
                key: clavesDeCondicion.puesto,
                label: 'Puesto',
                value: _puestoId,
                errorText: _errores['puesto'],
                helperText: _puestosElegibles.isEmpty
                    ? 'No hay puestos operativos activos. Se dan de alta en '
                          'Organización › Puestos.'
                    : 'Sólo puestos operativos: una condición describe una plaza '
                          'que se presta.',
                items: [
                  for (final p in _puestosElegibles)
                    RisegSelectItem(value: p.id, label: p.nombre),
                ],
                onChanged: (v) => setState(() {
                  _puestoId = v;
                  _errores.remove('puesto');
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegSelect<String?>(
                key: clavesDeCondicion.modalidad,
                label: 'Modalidad de turno (opcional)',
                value: _modalidadId,
                // ⚠️ LA EXPLICACIÓN DE LA MODALIDAD SE ENSEÑA AQUÍ, y es la mitad del
                // trabajo de la 0064: lleva cuántas personas hacen falta para cubrir un
                // puesto 24/7, que es el número que de verdad se usa al cotizar.
                helperText: modalidad?.explicacion ?? _ayudaDeModalidades,
                helperMaxLines: 4,
                items: [
                  const RisegSelectItem<String?>(value: null, label: 'Sin modalidad'),
                  for (final m in widget.modalidades)
                    if (m.estaActiva || m.id == _modalidadInicial)
                      RisegSelectItem<String?>(value: m.id, label: m.nombre),
                ],
                onChanged: (v) => setState(() {
                  _modalidadId = v;

                  // Al cambiar de modalidad, el periodo que no aplica SE BORRA. Dejarlo
                  // puesto mandaría un periodo sobrante y el servidor contestaría 422 por
                  // un campo que la pantalla ya había escondido.
                  if (_modalidad?.pidePeriodo != true) _periodo = null;
                  _errores.remove('periodo');
                }),
              ),
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
              const SizedBox(height: AppSpacing.md),

              // --- Cuánto ---------------------------------------------------
              RisegTextField(
                key: clavesDeCondicion.plazas,
                label: 'Plazas',
                controller: _plazas,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _errores['plazas'],
                helperText: 'Cuántos elementos se cobran de esta línea.',
                onChanged: (_) => _limpiar('plazas'),
              ),
              const SizedBox(height: AppSpacing.md),
              RisegTextField(
                key: clavesDeCondicion.precio,
                label: 'Precio por plaza',
                controller: _precio,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                errorText: _errores['precio'],
                helperText:
                    'Mensual y por plaza, en $_moneda. **Cero es válido**: existe el '
                    'servicio de cortesía o incluido.',
                helperMaxLines: 3,
                onChanged: (_) => _limpiar('precio'),
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
              RisegTextField(
                key: clavesDeCondicion.descripcion,
                label: 'Descripción (opcional)',
                controller: _descripcion,
                maxLines: 2,
                errorText: _errores['descripcion'],
                helperText: 'Lo que hace falta decir de esta línea en particular.',
                onChanged: (_) => _limpiar('descripcion'),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- El horario -----------------------------------------------
              _RejillaSemanal(
                bloques: _horario,
                alCambiar: () => setState(() {}),
              ),

              // --- El sueldo de referencia, sólo en la primera ---------------
              if (widget.pideSueldoDeReferencia) ...[
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

  void _guardar() {
    final errores = <String, String>{};

    if (_inicio == null) errores['inicio'] = 'Falta la fecha desde la que cobra.';

    if (_inicio != null && _termino != null && _termino!.isBefore(_inicio!)) {
      errores['termino'] = 'No puede terminar antes de empezar.';
    }

    if (_puestoId == null) errores['puesto'] = 'Elige el puesto de la plaza.';

    if (_modalidad?.pidePeriodo == true && _periodo == null) {
      errores['periodo'] = 'Di si la plaza es diurna o nocturna.';
    }

    final plazas = int.tryParse(_plazas.text.trim());

    if (plazas == null || plazas <= 0) {
      errores['plazas'] = 'Tiene que ser un número mayor que cero.';
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

    Navigator.of(context).pop(
      ResultadoDeCondicion(
        condicion: CondicionEnviada(
          // `deFechaLocal` y no el constructor a secas: lo que la persona eligió es un día
          // del calendario, no un instante, y aplicarle el desplazamiento de zona lo
          // movería un día.
          inicio: DiaDeNegocio.deFechaLocal(_inicio!),
          termino: _termino == null ? null : DiaDeNegocio.deFechaLocal(_termino!),
          puestoId: _puestoId!,
          modalidadId: _modalidadId,
          periodo: _periodo,
          plazas: plazas!,
          precioUnitarioMenores: precio!,
          moneda: _moneda,
          iva: _iva,
          descripcion: _descripcion.text.trim().isEmpty
              ? null
              : _descripcion.text.trim(),
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
