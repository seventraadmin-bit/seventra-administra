import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../modelos/condicion_comercial.dart';

/// **Renovar / extender un servicio, en tres pasos** — y desde C3, **con precios**.
///
/// ## Por qué tres pasos y no un formulario
///
/// Renovar son dos decisiones que se toman en orden y una que se revisa: **hasta cuándo**,
/// **a qué precio cada línea**, y **qué va a pasar**. Puestas en una sola pantalla, la
/// segunda se pasa por alto —son N campos prellenados con lo que ya hay— y el resultado es
/// justo lo que CP-23 vino a impedir: **mover la fecha y seguir facturando al precio
/// viejo**.
///
/// El tercer paso no pide nada: dice **qué líneas cambian y cuáles quedan «sin cambio»**.
/// Es el que convierte «le di a Guardar» en «sé qué firmé».
///
/// ## 🚫 EL AUMENTO NO SE SUGIERE, NI AQUÍ NI EN NINGÚN SITIO
///
/// Cada campo de precio nace **con el precio que ya hay**, no con un aumento calculado.
/// Cada cliente sube distinto según su negociación, y que RISEG suba las tarifas en enero
/// es **una costumbre de RISEG**, no una regla del producto: un «+5 %» precargado la
/// convertiría en ley para todas las empresas que usen esto.
///
/// ## Tres salidas por línea, y «mismo precio» es la de por omisión
///
/// Cada línea que cobra elige **mismo precio**, **precio nuevo** o **dar de baja al
/// término** (decisión del dueño, 14-nov-2026: renovar quitando el supervisor y conservando
/// a los guardias es lo que pasa de verdad). 🚫 **La omisión conserva lo pactado:** una
/// renovación que por omisión diera algo de baja sería una trampa.
///
/// ## 🚫 «SIN CAMBIO» NO ES «NO LA TOQUES» — corregido el 14 de noviembre de 2026
///
/// Una renovación manda **el precio de todas las líneas que cobran hoy**, también las que
/// conservan su importe, porque **el periodo nuevo no hereda nada**: la condición vigente de
/// cada línea termina con el periodo que se cierra —el servidor no admite una condición
/// abierta dentro de un servicio con término—. Una línea que se quedara fuera **dejaría de
/// cobrar** al día siguiente, y el servidor rechaza la renovación incompleta nombrándola.
///
/// De ahí dos cosas que esta pantalla hace y antes no: **sin el permiso de precios no se
/// puede renovar** un servicio que cobra —se puede mover la fecha, que es otra acción—, y
/// **una línea con condición programada bloquea la renovación entera** hasta que se cancele.
///
/// ## Lo que sigue pendiente, y está dicho
///
/// ⚠️ Esto renueva **el servicio y sus precios**, en **una sola petición atómica**. La
/// **cadena del contrato** —que un contrato renueva a otro— es de C6, así que `CP-23` sigue
/// abierto hasta entonces. El resumen del tercer paso no promete nada sobre contratos.
Future<PlanDeRenovacion?> mostrarRenovacion(
  BuildContext context, {
  required String nombreDelServicio,
  required DiaDeNegocio? terminoActual,
  required DiaDeNegocio hoy,
  required List<RenglonDeRenovacion> renglones,
  required bool puedeTocarPrecios,
  required GuardiaDeSalida guardia,
  bool reactivando = false,
}) => showDialog<PlanDeRenovacion>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _DialogoDeRenovacion(
    nombreDelServicio: nombreDelServicio,
    terminoActual: terminoActual,
    hoy: hoy,
    renglones: renglones,
    puedeTocarPrecios: puedeTocarPrecios,
    guardia: guardia,
    reactivando: reactivando,
  ),
);

/// Una línea del servicio con la condición de la que se parte, tal como entra al diálogo.
class RenglonDeRenovacion {
  const RenglonDeRenovacion({
    required this.linea,
    required this.vigente,
    required this.tieneProgramada,
  });

  final LineaComercial linea;

  /// La condición de la que se parte: **la que cobra hoy** y, cuando el servicio está
  /// terminado y se está reactivando, **la última que cobró**.
  ///
  /// ⚠️ **Nula** cuando la línea no tiene ninguna: entonces no hay precio que renovar y el
  /// renglón sólo se informa. Y por eso la pantalla dice «Cobraba» en lugar de «Hoy» al
  /// reactivar: en un servicio que paró, «hoy» no cobra nada.
  final CondicionComercial? vigente;

  /// ⚠️ Con una condición **ya programada**, esta línea **no se puede renovar aquí**: el
  /// servidor admite una sola futura pendiente por línea y responderia 409. Se dice en el
  /// resumen en lugar de dejar que falle al guardar.
  final bool tieneProgramada;

  bool get sePuedeRenovar => vigente != null && !tieneProgramada;
}

/// Lo que el diálogo entrega: la fecha nueva y **el precio de cada línea que cobra hoy**.
class PlanDeRenovacion {
  const PlanDeRenovacion({
    required this.termino,
    required this.quitarElTermino,
    required this.desdeCuandoLosPrecios,
    required this.precios,
  });

  /// La fecha de término nueva. Nula si [quitarElTermino].
  final DiaDeNegocio? termino;

  /// **Renovado sin fecha de fin**, que es una salida legítima del primer paso.
  final bool quitarElTermino;

  /// El primer día del periodo nuevo, desde el que valen los precios nuevos.
  final DiaDeNegocio desdeCuandoLosPrecios;

  /// 🚫 **TODAS las líneas que cobran hoy, no sólo las que cambian de precio**, y eso cambió
  /// el 14 de noviembre de 2026. La condición vigente de cada línea **termina con el periodo
  /// que se cierra** —el servidor no admite una condición abierta en un servicio con
  /// término—, así que una línea que no viaje aquí **deja de cobrar** en el periodo nuevo:
  /// «sin cambio» significa **otra condición con el mismo precio**, no «no la toques».
  final List<PrecioDeRenovacion> precios;

  /// Las que de verdad cambian de importe. Se **deriva** en lugar de guardarse: dos listas
  /// podrían discrepar, y el resumen enseña justo esta diferencia.
  List<PrecioDeRenovacion> get cambios => [
    for (final p in precios)
      if (p.cambia) p,
  ];

  /// Las que se dan de baja al término.
  List<PrecioDeRenovacion> get bajas => [
    for (final p in precios)
      if (p.seDaDeBaja) p,
  ];
}

/// Lo que se decide para una línea al renovar. **Tres salidas y ninguna más**, decisión del
/// dueño del 14 de noviembre de 2026.
enum DecisionDeRenovacion {
  /// Estrena condición con **el importe que ya tenía**. 🚫 No es «no la toques».
  mismoPrecio('Mismo precio'),

  /// Estrena condición con **otro importe**.
  precioNuevo('Precio nuevo'),

  /// **Deja de cobrar al término** del periodo que se cierra, y la línea queda retirada.
  darDeBaja('Dar de baja al término');

  const DecisionDeRenovacion(this.enPantalla);

  final String enPantalla;
}

/// El precio de una línea en el periodo nuevo, o su baja.
class PrecioDeRenovacion {
  const PrecioDeRenovacion({
    required this.linea,
    required this.vigente,
    required this.precioNuevoMenores,
    required this.decision,
  });

  final LineaComercial linea;

  /// La condición que se va a cerrar al programar la siguiente. De ella sale **todo lo
  /// demás** —puesto, turno, plazas, IVA y horario—: renovar cambia el precio, no la plaza.
  final CondicionComercial vigente;

  /// El importe del periodo nuevo. **Nulo cuando la línea se da de baja**: no hay condición
  /// nueva, así que no hay precio — y un cero se leería como «gratis».
  final int? precioNuevoMenores;

  final DecisionDeRenovacion decision;

  bool get seDaDeBaja => decision == DecisionDeRenovacion.darDeBaja;

  /// ⚠️ **SE COMPARA CONTRA EL PRECIO EN SU PROPIA FORMA** (0066): una línea cotizada con un
  /// total mensual se renueva con un total, y compararlo contra el unitario —que ahí es
  /// nulo— marcaría como «cambio» cada línea que no cambió.
  bool get cambia => !seDaDeBaja && precioNuevoMenores != vigente.precioQueSeEdita;
}

class _DialogoDeRenovacion extends StatefulWidget {
  const _DialogoDeRenovacion({
    required this.nombreDelServicio,
    required this.terminoActual,
    required this.hoy,
    required this.renglones,
    required this.puedeTocarPrecios,
    required this.guardia,
    required this.reactivando,
  });

  final String nombreDelServicio;
  final DiaDeNegocio? terminoActual;
  final DiaDeNegocio hoy;
  final List<RenglonDeRenovacion> renglones;
  final bool puedeTocarPrecios;
  final GuardiaDeSalida guardia;

  /// El servicio está **terminado** y este acto lo revive. Cambia lo que se lee —«paró el»
  /// en lugar de «termina el», «Cobraba» en lugar de «Hoy»— y **no** cambia lo que se
  /// decide: las tres salidas por línea son las mismas.
  final bool reactivando;

  @override
  State<_DialogoDeRenovacion> createState() => _DialogoDeRenovacionState();
}

class _DialogoDeRenovacionState extends State<_DialogoDeRenovacion>
    with DeclaraSuTrabajoSinGuardar<_DialogoDeRenovacion> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// Contra **lo cargado**: la fecha que ya tenía y los precios que ya tenía. Avanzar de
  /// paso sin cambiar nada no es trabajo que perder.
  @override
  bool get hayCambiosSinGuardar =>
      _termino != widget.terminoActual?.comoFechaLocal ||
      _quitar ||
      _precios.entries.any((e) => e.value.text.trim() != _iniciales[e.key]) ||
      // ⚠️ Y LAS DECISIONES CUENTAN COMO TRABAJO: elegir «dar de baja» en tres líneas y
      // salirse sin guardar pierde tres decisiones, aunque ningún campo de texto cambiara.
      _decisiones.values.any((d) => d != DecisionDeRenovacion.mismoPrecio);

  @override
  String get queSePierde => 'la renovación de ${widget.nombreDelServicio}';

  late final Map<String, String> _iniciales = {
    for (final r in widget.renglones)
      if (r.vigente case final v?) r.linea.id: _comoTexto(v.precioQueSeEdita),
  };

  final Map<String, TextEditingController> _precios = {};

  /// Qué se decidió para cada línea. **Ausente es «mismo precio»**, que es la salida que
  /// conserva lo pactado: una renovación que por omisión diera de baja algo sería una trampa.
  final Map<String, DecisionDeRenovacion> _decisiones = {};

  int _paso = 0;
  DateTime? _termino;
  bool _quitar = false;
  DateTime? _desdeLosPrecios;
  String? _errorDeFecha;

  @override
  void initState() {
    super.initState();

    // ⚠️ **AL REACTIVAR NACE VACÍA, y no con la fecha en que paró:** esa fecha ya pasó, y el
    // campo no admite el pasado —reactivar es comprometerse a futuro—. Proponerla dejaría un
    // valor que el propio selector rechaza, y quien la viera creería que ya está decidida.
    _termino = widget.reactivando ? null : widget.terminoActual?.comoFechaLocal;

    // ⚠️ **CADA CAMPO NACE CON EL PRECIO QUE YA HAY**, no con un aumento: dejarlo como
    // está significa «sin cambio», y eso es lo que tiene que ser fácil.
    for (final r in widget.renglones) {
      if (r.vigente case final v?) {
        _precios[r.linea.id] = TextEditingController(
          text: _comoTexto(v.precioQueSeEdita),
        );
      }
    }

    // El primer día del periodo nuevo: **el siguiente al término que hay hoy**, que es la
    // frontera natural de una renovación. Sin término actual no hay frontera, así que se
    // propone hoy y se puede cambiar.
    //
    // ⚠️ **AL REACTIVAR SE PROPONE HOY**, y no el día siguiente al término: ese día ya pasó
    // —el servicio paró hace semanas—, así que proponerlo sería proponer cobrar un periodo
    // en el que no se operó.
    _desdeLosPrecios = widget.terminoActual == null || widget.reactivando
        ? widget.hoy.comoFechaLocal
        : widget.terminoActual!.comoFechaLocal.add(const Duration(days: 1));
  }

  @override
  void dispose() {
    for (final c in _precios.values) {
      c.dispose();
    }

    super.dispose();
  }

  /// Las líneas que **se pueden renovar**: cobran algo hoy y no tienen otra programada.
  List<RenglonDeRenovacion> get _renovables => [
    for (final r in widget.renglones)
      if (r.sePuedeRenovar) r,
  ];

  /// Las líneas que **cobran hoy y estorban**: tienen una condición ya programada.
  ///
  /// 🚫 **Bloquean la renovación ENTERA, no sólo la suya.** La renovación cubre todas las
  /// líneas que cobran hoy —el servidor lo exige— y el servidor admite **una sola condición
  /// futura por línea**, así que mientras una tenga la suya no hay renovación posible. Antes
  /// esta pantalla decía «cancélala antes de renovar su precio», como si las demás pudieran
  /// renovarse sin ella.
  List<RenglonDeRenovacion> get _estorban => [
    for (final r in widget.renglones)
      if (r.vigente != null && r.tieneProgramada) r,
  ];

  /// **Por qué no se puede guardar, o nulo si se puede.** Un solo sitio para los dos lugares
  /// que lo enseñan —el paso de los precios y el resumen—: con dos textos, uno de los dos
  /// acabaría diciendo otra cosa.
  String? get _porQueNoSePuedeGuardar {
    if (_estorban.isNotEmpty) {
      // ⚠️ «UNA LÍNEA NO PUEDE TENER DOS PRECIOS FUTUROS» y no «el servidor admite una
      // sola»: el candado de jerga tiene razón en prohibir «el servidor» — a quien captura
      // le importa la regla, no quién la impone.
      return 'No se puede renovar mientras alguna línea tenga una condición programada: '
          'una renovación vuelve a poner el precio de TODAS las líneas que cobran, y una '
          'línea no puede tener dos precios futuros a la vez.\n\n'
          'Cancela la programada en la pestaña Comercial y vuelve aquí: '
          '${_estorban.map((r) => r.linea.nombre).join(' · ')}.';
    }

    // ⚠️ Sin permiso de precios no se puede renovar un servicio que cobra, porque el periodo
    // nuevo NO hereda los precios: hay que volver a ponerlos. Lo que sí se puede sin ese
    // permiso es mover la fecha, y eso tiene su propia acción.
    if (!widget.puedeTocarPrecios && _renovables.isNotEmpty) {
      return '${widget.reactivando ? 'Reactivar' : 'Renovar'} vuelve a poner el precio de '
          'cada línea en el periodo nuevo, y para eso hace falta el permiso de precios.\n\n'
          'El periodo nuevo NO hereda los precios: si nadie los pone, '
          '${widget.nombreDelServicio} quedaría operando sin nada que cobrar.\n\n'
          '${widget.reactivando ? 'Pídelo a quien administre precios.' : 'Si sólo quieres mover la fecha, usa «Programar el término». Para renovar de verdad, pídelo a quien administre precios.'}';
    }

    return null;
  }

  bool get _sePuedeGuardar => _porQueNoSePuedeGuardar == null;

  /// **La decisión de CADA línea renovable**, recalculada en cada paso para que el resumen no
  /// pueda discrepar de lo elegido.
  ///
  /// 🚫 **Las que no cambian también entran**, y el campo vacío o ilegible cuenta como «el que
  /// ya tiene»: dejar una línea fuera la dejaría sin precio en el periodo nuevo, que es
  /// exactamente lo que el servidor rechaza desde el 14 de noviembre de 2026.
  List<PrecioDeRenovacion> get _preciosDelPeriodo => [
    for (final r in widget.renglones)
      if (r.sePuedeRenovar)
        if (_decisiones[r.linea.id] ?? DecisionDeRenovacion.mismoPrecio
            case final decision)
          PrecioDeRenovacion(
            linea: r.linea,
            vigente: r.vigente!,
            decision: decision,
            precioNuevoMenores: switch (decision) {
              DecisionDeRenovacion.darDeBaja => null,
              DecisionDeRenovacion.mismoPrecio => r.vigente!.precioQueSeEdita,
              DecisionDeRenovacion.precioNuevo =>
                _menores(_precios[r.linea.id]!.text) ?? r.vigente!.precioQueSeEdita,
            },
          ),
  ];

  /// Sólo las que cambian de importe. Es lo que el resumen enumera como cambio.
  List<PrecioDeRenovacion> get _cambios => [
    for (final p in _preciosDelPeriodo)
      if (p.cambia) p,
  ];

  /// Las que se dan de baja, para el resumen y para el mensaje final.
  List<PrecioDeRenovacion> get _bajas => [
    for (final p in _preciosDelPeriodo)
      if (p.seDaDeBaja) p,
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(switch ((widget.reactivando, _paso)) {
      (true, 0) => 'Reactivar · hasta cuándo',
      (true, 1) => 'Reactivar · los precios',
      (true, _) => 'Reactivar · qué va a pasar',
      (false, 0) => 'Renovar / extender · hasta cuándo',
      (false, 1) => 'Renovar / extender · los precios',
      (false, _) => 'Renovar / extender · qué va a pasar',
    }),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: switch (_paso) {
          0 => _pasoDeLaFecha(),
          1 => _pasoDeLosPrecios(),
          _ => _pasoDelResumen(),
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      if (_paso > 0)
        TextButton(
          onPressed: () => setState(() => _paso--),
          child: const Text('Atrás'),
        ),
      if (_paso < 2)
        FilledButton(onPressed: _siguiente, child: const Text('Siguiente'))
      else
        FilledButton(
          key: const Key('renovacion-confirmar'),
          // 🚫 **DESHABILITADO Y NO ESCONDIDO**: quien llegó hasta aquí tiene que ver que el
          // botón existe y leer en el paso anterior por qué no puede pulsarlo. Un botón que
          // desaparece se lee como «esta pantalla está rota».
          onPressed: _sePuedeGuardar ? _confirmar : null,
          child: const Text('Guardar'),
        ),
    ],
  );

  // =========================================================================
  // Paso 1 · hasta cuándo
  // =========================================================================

  Widget _pasoDeLaFecha() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        switch ((widget.reactivando, widget.terminoActual)) {
          (true, final paro?) =>
            '${widget.nombreDelServicio} paró el ${fechaDeNegocioCorta(paro)} '
                'y vuelve a operar.',
          (true, null) => '${widget.nombreDelServicio} vuelve a operar.',
          (false, null) => '${widget.nombreDelServicio} no tiene fecha de término hoy.',
          (false, final fin?) =>
            '${widget.nombreDelServicio} termina el ${fechaDeNegocioCorta(fin)}.',
        },
        style: AppTypography.body,
      ),
      const SizedBox(height: AppSpacing.md),
      RisegDateField(
        key: const Key('renovacion-termino'),
        label: 'Nueva fecha de término',
        value: _quitar ? null : _termino,
        firstDate: widget.hoy.comoFechaLocal,
        enabled: !_quitar,
        errorText: _errorDeFecha,
        helperText: 'Hoy o después. Es el último día que el servicio opera.',
        onChanged: (v) => setState(() {
          _termino = v;
          _errorDeFecha = null;
        }),
      ),
      const SizedBox(height: AppSpacing.sm),
      RisegCheckbox(
        label: 'Se renovó sin fecha de fin',
        value: _quitar,
        onChanged: (v) => setState(() {
          _quitar = v;
          _errorDeFecha = null;
        }),
      ),
    ],
  );

  // =========================================================================
  // Paso 2 · los precios
  // =========================================================================

  Widget _pasoDeLosPrecios() {
    final renovables = _renovables;

    // 🚫 **LO QUE IMPIDE GUARDAR SE DICE AQUÍ, en el paso que lo provoca**, y no al final: al
    // final ya se tomaron las decisiones y leerlo entonces sólo sirve para volver atrás.
    if (_porQueNoSePuedeGuardar case final razon?) {
      return Text(razon, style: AppTypography.body);
    }

    if (renovables.isEmpty) {
      return const Text(
        'Este servicio no tiene ninguna línea con precio que renovar, así que esto sólo '
        'mueve la fecha.',
        style: AppTypography.body,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cada línea tiene tres salidas: seguir con el mismo precio, poner otro, o darla '
          'de baja al término. Por omisión siguen con el mismo.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        RisegDateField(
          key: const Key('renovacion-desde'),
          label: 'Los precios nuevos valen desde',
          value: _desdeLosPrecios,
          firstDate: widget.hoy.comoFechaLocal,
          helperText: widget.terminoActual == null
              ? 'El primer día del periodo nuevo.'
              : 'Por omisión, el día siguiente al término de hoy.',
          onChanged: (v) => setState(() => _desdeLosPrecios = v),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final r in renovables) ...[
          RisegSelect<DecisionDeRenovacion>(
            key: Key('renovacion-decision-${r.linea.id}'),
            label: r.linea.nombre,
            value: _decisiones[r.linea.id] ?? DecisionDeRenovacion.mismoPrecio,
            // ⚠️ «COBRABA» AL REACTIVAR, no «Hoy»: en un servicio que paró, hoy no cobra
            // nada, y decir «Hoy $15 000» sería afirmar algo falso en la pantalla.
            // LA CUENTA SE LEE SEGÚN LA FORMA EN QUE ESA LÍNEA SE COTIZÓ: con un total
            // pactado, «× 3 personas» sería multiplicar algo que no se multiplica.
            helperText: r.vigente!.modo.esPorPersona
                ? '${widget.reactivando ? 'Cobraba' : 'Hoy'} '
                      '${_dinero(r.vigente!.precioQueSeEdita, r.vigente!.moneda)} '
                      '× ${r.vigente!.plazas} '
                      '${r.vigente!.plazas == 1 ? 'persona' : 'personas'}.'
                : '${widget.reactivando ? 'Cobraba' : 'Hoy'} '
                      '${_dinero(r.vigente!.precioQueSeEdita, r.vigente!.moneda)} '
                      'al mes, en total.',
            helperMaxLines: 2,
            items: [
              for (final d in DecisionDeRenovacion.values)
                RisegSelectItem(value: d, label: d.enPantalla),
            ],
            onChanged: (v) => setState(() {
              _decisiones[r.linea.id] = v ?? DecisionDeRenovacion.mismoPrecio;
            }),
          ),
          // EL CAMPO SÓLO EXISTE CUANDO HAY PRECIO QUE PONER. Enseñarlo deshabilitado en las
          // otras dos salidas invitaría a teclear en un número que no se va a mandar.
          if (_decisiones[r.linea.id] == DecisionDeRenovacion.precioNuevo) ...[
            const SizedBox(height: AppSpacing.sm),
            RisegTextField(
              key: Key('renovacion-precio-${r.linea.id}'),
              label: 'Precio nuevo por persona',
              controller: _precios[r.linea.id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              // ⚠️ NACE CON EL PRECIO QUE YA HAY, no con un aumento calculado: que RISEG
              // suba las tarifas en enero es una costumbre de RISEG, no una regla.
              helperText: 'Viene con el de hoy. Cámbialo por el pactado.',
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (_decisiones[r.linea.id] == DecisionDeRenovacion.darDeBaja) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Deja de cobrarse'
              '${_desdeLosPrecios == null ? '' : ' el ${fechaDeNegocioCorta(DiaDeNegocio.deFechaLocal(_desdeLosPrecios!))}'}'
              ', y la línea queda retirada. Su historia se conserva entera.',
              style: AppTypography.caption,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
        // LAS QUE NO COBRAN NADA SE ENUMERAN Y SE QUEDAN FUERA. (La otra razón para no poder
        // renovar una línea —que ya tenga una condición programada— no llega hasta aquí:
        // bloquea la renovación entera y se dice arriba.)
        for (final r in widget.renglones)
          if (r.vigente == null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${r.linea.nombre}: no cobra nada, así que no hay precio que renovar.',
                style: AppTypography.caption,
              ),
            ),
      ],
    );
  }

  // =========================================================================
  // Paso 3 · qué va a pasar
  // =========================================================================

  Widget _pasoDelResumen() {
    final precios = _preciosDelPeriodo;
    final cambios = _cambios;
    final bajas = _bajas;

    // LO QUE YA SE DIJO ARRIBA no se repite abajo como «sin cambio»: una línea aparece una
    // vez, en la frase que le toca.
    final yaDichas = {
      for (final p in [...cambios, ...bajas]) p.linea.id,
    };

    final siguen = precios.length - bajas.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [
            if (widget.reactivando) 'El servicio vuelve a operar.',
            _quitar
                ? 'Queda **sin fecha de término**.'
                : 'Terminará el '
                      '${_termino == null ? '—' : fechaDeNegocioCorta(DiaDeNegocio.deFechaLocal(_termino!))}.',
          ].join(' '),
          style: AppTypography.bodyStrong,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_porQueNoSePuedeGuardar case final razon?)
          Text(razon, style: AppTypography.bodyStrong)
        else if (precios.isEmpty)
          const Text(
            'Ninguna línea cobra nada hoy, así que esto sólo mueve la fecha.',
            style: AppTypography.body,
          )
        else ...[
          Text(
            // ⚠️ «VUELVEN A EMPEZAR», y no «los precios nuevos valen desde»: desde el 14 de
            // noviembre de 2026 **todas** las líneas estrenan condición en el periodo nuevo,
            // también las que conservan su importe. Decir que sólo valen «los nuevos» haría
            // creer que las demás siguen cobrando por su cuenta, y lo que de verdad pasa es
            // que se reprograman igual.
            '${siguen == 0 ? 'Ninguna línea sigue' : '$siguen ${siguen == 1 ? 'línea sigue' : 'líneas siguen'}'} '
            'en el periodo nuevo, desde el '
            '${_desdeLosPrecios == null ? '—' : fechaDeNegocioCorta(DiaDeNegocio.deFechaLocal(_desdeLosPrecios!))}'
            '${cambios.isEmpty && bajas.isEmpty ? ', con el mismo precio que tienen hoy.' : ':'}',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final c in cambios)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${c.linea.nombre}: '
                '${_dinero(c.vigente.precioQueSeEdita, c.vigente.moneda)} → '
                '${_dinero(c.precioNuevoMenores!, c.vigente.moneda)}',
                style: AppTypography.body,
              ),
            ),
          // 🚫 LAS BAJAS SE DICEN CON SU FECHA Y CON LAS DOS MITADES: el día en que deja de
          // cobrarse y el último que sí se cobra. «Se da de baja el 1 de enero» a secas se
          // lee de las dos maneras, y una de las dos es un mes de más.
          for (final b in bajas)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${b.linea.nombre}: se da de baja'
                '${_desdeLosPrecios == null ? '' : ' el ${fechaDeNegocioCorta(DiaDeNegocio.deFechaLocal(_desdeLosPrecios!))}'}'
                '${_desdeLosPrecios == null ? '' : ' —se cobra hasta el ${fechaDeNegocioCorta(DiaDeNegocio.deFechaLocal(_desdeLosPrecios!.subtract(const Duration(days: 1))))}—'}'
                ', y la línea queda retirada.',
                style: AppTypography.bodyStrong,
              ),
            ),
        ],
        // LAS QUE QUEDAN IGUAL SE ENUMERAN, no se callan. Que una línea no aparezca es
        // indistinguible de que nadie la mirara.
        for (final r in widget.renglones)
          if (!yaDichas.contains(r.linea.id))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                '${r.linea.nombre}: sin cambio'
                '${r.tieneProgramada ? ' (tiene una condición programada y se queda fuera)' : ''}'
                '${r.vigente == null ? ' (no cobra nada)' : ''}',
                style: AppTypography.caption,
              ),
            ),
        const SizedBox(height: AppSpacing.md),
        Text(
          // ⚠️ LO QUE ESTO NO HACE, DICHO AQUÍ. La cadena del contrato —que un contrato
          // renueva a otro— llega con los contratos, y prometerla aquí sería prometer algo
          // que nadie va a poder consultar después.
          '${widget.reactivando ? 'Esto reactiva el servicio y pone sus precios.' : 'Esto renueva el servicio y sus precios.'} '
          'No registra que un contrato renueve a otro: eso llega con los contratos.',
          style: AppTypography.caption,
        ),
      ],
    );
  }

  // =========================================================================
  // Navegación
  // =========================================================================

  void _siguiente() {
    if (_paso == 0) {
      if (!_quitar && _termino == null) {
        setState(() => _errorDeFecha = 'Pon la fecha, o marca que no tiene fin.');

        return;
      }

      setState(() => _paso = 1);

      return;
    }

    setState(() => _paso = 2);
  }

  void _confirmar() => Navigator.of(context).pop(
    PlanDeRenovacion(
      termino: _quitar || _termino == null
          ? null
          : DiaDeNegocio.deFechaLocal(_termino!),
      quitarElTermino: _quitar,
      desdeCuandoLosPrecios: _desdeLosPrecios == null
          ? widget.hoy
          : DiaDeNegocio.deFechaLocal(_desdeLosPrecios!),
      precios: _preciosDelPeriodo,
    ),
  );

  /// `15000.50` → `1500050`. Nulo si el texto no es una cantidad. Misma regla que en el
  /// formulario de condición: tres decimales no son una cantidad en pesos.
  static int? _menores(String texto) {
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

  static String _comoTexto(int menores) {
    final centavos = menores % 100;

    return centavos == 0
        ? (menores ~/ 100).toString()
        : '${menores ~/ 100}.${centavos.toString().padLeft(2, '0')}';
  }
}

/// `$15,000.00 MXN`. ⚠️ Divide entre 100, suposición sobre la moneda dicha en voz alta.
String _dinero(int menores, String moneda) {
  final pesos = (menores ~/ 100).toString();
  final centavos = (menores % 100).toString().padLeft(2, '0');

  final conSeparadores = StringBuffer();

  for (var i = 0; i < pesos.length; i++) {
    if (i > 0 && (pesos.length - i) % 3 == 0) conSeparadores.write(',');
    conSeparadores.write(pesos[i]);
  }

  return '\$$conSeparadores.$centavos $moneda';
}
