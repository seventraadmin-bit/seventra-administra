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
/// ## Lo que sigue pendiente, y está dicho
///
/// ⚠️ Esto renueva **el servicio y sus precios**. La **cadena del contrato** —que un
/// contrato renueva a otro— es de C6, así que `CP-23` sigue abierto hasta entonces. El
/// resumen del tercer paso no promete nada sobre contratos.
Future<PlanDeRenovacion?> mostrarRenovacion(
  BuildContext context, {
  required String nombreDelServicio,
  required DiaDeNegocio? terminoActual,
  required DiaDeNegocio hoy,
  required List<RenglonDeRenovacion> renglones,
  required bool puedeTocarPrecios,
  required GuardiaDeSalida guardia,
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
  ),
);

/// Una línea del servicio con su condición vigente, tal como entra al diálogo.
class RenglonDeRenovacion {
  const RenglonDeRenovacion({
    required this.linea,
    required this.vigente,
    required this.tieneProgramada,
  });

  final LineaComercial linea;

  /// La condición que cobra hoy. **Nula** cuando la línea no cobra nada: entonces no hay
  /// precio que renovar y el renglón sólo se informa.
  final CondicionComercial? vigente;

  /// ⚠️ Con una condición **ya programada**, esta línea **no se puede renovar aquí**: el
  /// servidor admite una sola futura pendiente por línea y responderia 409. Se dice en el
  /// resumen en lugar de dejar que falle al guardar.
  final bool tieneProgramada;

  bool get sePuedeRenovar => vigente != null && !tieneProgramada;
}

/// Lo que el diálogo entrega: la fecha nueva y los precios que de verdad cambian.
class PlanDeRenovacion {
  const PlanDeRenovacion({
    required this.termino,
    required this.quitarElTermino,
    required this.desdeCuandoLosPrecios,
    required this.cambios,
  });

  /// La fecha de término nueva. Nula si [quitarElTermino].
  final DiaDeNegocio? termino;

  /// **Renovado sin fecha de fin**, que es una salida legítima del primer paso.
  final bool quitarElTermino;

  /// El primer día del periodo nuevo, desde el que valen los precios nuevos.
  final DiaDeNegocio desdeCuandoLosPrecios;

  /// Sólo las líneas cuyo precio cambia. **Una lista vacía es válida**: renovar sin tocar
  /// precios es extender, y eso se hace todo el tiempo.
  final List<CambioDePrecio> cambios;

  bool get tocaPrecios => cambios.isNotEmpty;
}

/// El precio nuevo de una línea.
class CambioDePrecio {
  const CambioDePrecio({
    required this.linea,
    required this.vigente,
    required this.precioNuevoMenores,
  });

  final LineaComercial linea;

  /// La condición que se va a cerrar al programar la siguiente. De ella sale **todo lo
  /// demás** —puesto, turno, plazas, IVA y horario—: renovar cambia el precio, no la plaza.
  final CondicionComercial vigente;

  final int precioNuevoMenores;
}

class _DialogoDeRenovacion extends StatefulWidget {
  const _DialogoDeRenovacion({
    required this.nombreDelServicio,
    required this.terminoActual,
    required this.hoy,
    required this.renglones,
    required this.puedeTocarPrecios,
    required this.guardia,
  });

  final String nombreDelServicio;
  final DiaDeNegocio? terminoActual;
  final DiaDeNegocio hoy;
  final List<RenglonDeRenovacion> renglones;
  final bool puedeTocarPrecios;
  final GuardiaDeSalida guardia;

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
      _precios.entries.any((e) => e.value.text.trim() != _iniciales[e.key]);

  @override
  String get queSePierde => 'la renovación de ${widget.nombreDelServicio}';

  late final Map<String, String> _iniciales = {
    for (final r in widget.renglones)
      if (r.vigente case final v?) r.linea.id: _comoTexto(v.precioUnitarioMenores),
  };

  final Map<String, TextEditingController> _precios = {};

  int _paso = 0;
  DateTime? _termino;
  bool _quitar = false;
  DateTime? _desdeLosPrecios;
  String? _errorDeFecha;

  @override
  void initState() {
    super.initState();

    _termino = widget.terminoActual?.comoFechaLocal;

    // ⚠️ **CADA CAMPO NACE CON EL PRECIO QUE YA HAY**, no con un aumento: dejarlo como
    // está significa «sin cambio», y eso es lo que tiene que ser fácil.
    for (final r in widget.renglones) {
      if (r.vigente case final v?) {
        _precios[r.linea.id] = TextEditingController(
          text: _comoTexto(v.precioUnitarioMenores),
        );
      }
    }

    // El primer día del periodo nuevo: **el siguiente al término que hay hoy**, que es la
    // frontera natural de una renovación. Sin término actual no hay frontera, así que se
    // propone hoy y se puede cambiar.
    _desdeLosPrecios = widget.terminoActual == null
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

  /// Los renglones que cambian de precio, recalculados en cada paso para que el resumen no
  /// pueda discrepar de los campos.
  List<CambioDePrecio> get _cambios => [
    for (final r in widget.renglones)
      if (r.sePuedeRenovar)
        if (_menores(_precios[r.linea.id]!.text) case final nuevo?)
          if (nuevo != r.vigente!.precioUnitarioMenores)
            CambioDePrecio(
              linea: r.linea,
              vigente: r.vigente!,
              precioNuevoMenores: nuevo,
            ),
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(switch (_paso) {
      0 => 'Renovar / extender · hasta cuándo',
      1 => 'Renovar / extender · los precios',
      _ => 'Renovar / extender · qué va a pasar',
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
          onPressed: _confirmar,
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
        widget.terminoActual == null
            ? '${widget.nombreDelServicio} no tiene fecha de término hoy.'
            : '${widget.nombreDelServicio} termina el '
                  '${fechaDeNegocioCorta(widget.terminoActual!)}.',
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
    if (!widget.puedeTocarPrecios) {
      return const Text(
        // 🚫 Y SE DICE QUE NO SE TOCAN, en lugar de esconder el paso: quien renueve sin el
        // permiso de precios tiene que saber que el periodo nuevo se factura al precio
        // anterior, que es exactamente el silencio que CP-23 vino a romper.
        'No se te permite cambiar precios, así que esta renovación mueve la fecha y '
        'deja los precios como están: el periodo nuevo se facturará al precio '
        'anterior.\n\n'
        'Si hay que renegociar, pídelo a quien administre precios.',
        style: AppTypography.body,
      );
    }

    final renovables = [
      for (final r in widget.renglones)
        if (r.sePuedeRenovar) r,
    ];

    if (renovables.isEmpty) {
      return const Text(
        'Este servicio no tiene ninguna línea con precio que renovar.',
        style: AppTypography.body,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cada línea viene con el precio que tiene hoy. **Lo que dejes igual queda sin '
          'cambio.**',
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
          RisegTextField(
            key: Key('renovacion-precio-${r.linea.id}'),
            label: r.linea.nombre,
            controller: _precios[r.linea.id],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            helperText:
                'Hoy ${_dinero(r.vigente!.precioUnitarioMenores, r.vigente!.moneda)} '
                '× ${r.vigente!.plazas} '
                '${r.vigente!.plazas == 1 ? 'plaza' : 'plazas'}.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final r in widget.renglones)
          if (!r.sePuedeRenovar)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                r.vigente == null
                    ? '${r.linea.nombre}: no cobra nada, así que no hay precio que '
                          'renovar.'
                    : '${r.linea.nombre}: ya tiene una condición programada. Cancélala '
                          'antes de renovar su precio.',
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
    final cambios = _cambios;
    final cambian = {for (final c in cambios) c.linea.id};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _quitar
              ? 'El servicio queda **sin fecha de término**.'
              : 'El servicio terminará el '
                    '${_termino == null ? '—' : fechaDeNegocioCorta(DiaDeNegocio.deFechaLocal(_termino!))}.',
          style: AppTypography.bodyStrong,
        ),
        const SizedBox(height: AppSpacing.md),
        if (cambios.isEmpty)
          const Text(
            // ⚠️ SE DICE EN VOZ ALTA, porque es el caso en que CP-23 se rompía: una
            // renovación que mueve la fecha y no toca precios es legítima —extender— y
            // tiene que distinguirse de haberse olvidado de los precios.
            'Ningún precio cambia: esto extiende el servicio con las condiciones que ya '
            'tiene.',
            style: AppTypography.body,
          )
        else ...[
          Text(
            'Los precios nuevos valen desde el '
            '${_desdeLosPrecios == null ? '—' : fechaDeNegocioCorta(DiaDeNegocio.deFechaLocal(_desdeLosPrecios!))}.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final c in cambios)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '${c.linea.nombre}: '
                '${_dinero(c.vigente.precioUnitarioMenores, c.vigente.moneda)} → '
                '${_dinero(c.precioNuevoMenores, c.vigente.moneda)}',
                style: AppTypography.body,
              ),
            ),
        ],
        // LAS QUE QUEDAN IGUAL SE ENUMERAN, no se callan. Que una línea no aparezca es
        // indistinguible de que nadie la mirara.
        for (final r in widget.renglones)
          if (!cambian.contains(r.linea.id))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                '${r.linea.nombre}: sin cambio'
                '${r.tieneProgramada ? ' (tiene una condición programada)' : ''}'
                '${r.vigente == null ? ' (no cobra nada)' : ''}',
                style: AppTypography.caption,
              ),
            ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          // ⚠️ LO QUE ESTO NO HACE, DICHO AQUÍ. La cadena del contrato —que un contrato
          // renueva a otro— llega con los contratos, y prometerla aquí sería prometer algo
          // que nadie va a poder consultar después.
          'Esto renueva el servicio y sus precios. No registra que un contrato renueve a '
          'otro: eso llega con los contratos.',
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
      cambios: _cambios,
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
