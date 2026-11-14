import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system_web.dart';
import '../../../../core/error/mensajes_humanos.dart';
import '../../../../core/fechas/dia_de_negocio.dart';
import '../../../../core/fechas/fecha_en_pantalla.dart';
import '../../../../core/trabajo_sin_guardar/declara_su_trabajo_sin_guardar.dart';
import '../../../../core/trabajo_sin_guardar/guardia_de_salida.dart';
import '../datos/condiciones_repositorio_http.dart';
import '../modelos/condicion_comercial.dart';

/// **El sueldo de referencia (para ofrecer el puesto)** de una línea comercial, con su
/// historial y el cambio desde una fecha.
///
/// ## 🚫 ESTO NO ES EL SUELDO DE NADIE
///
/// Es lo que se ofrece al reclutar para esta línea: pre-llena el formulario al asignar
/// personal. **El sueldo real de cada persona vive en su asignación**, y cambiar esta cifra
/// no le cambia el sueldo a ningún empleado ya asignado. La pantalla lo dice con esas
/// palabras, porque es la confusión que el nombre invita a hacer.
///
/// ## Por qué es una vigencia aparte del precio
///
/// Sobre la misma línea corren **dos líneas de tiempo**: el precio al cliente, que se
/// negocia con él, y esta cifra, que la mueve el mercado laboral. Antes de la migración 0065
/// vivían juntas, así que subir lo que se ofrece donde hay rotación **obligaba a recapturar
/// el contrato del cliente** — precio, IVA, plazas y horario incluidos. Lo que se quería
/// mover era una cifra interna.
///
/// Así que cambiarlo aquí **no toca el precio**, y esta pantalla no recarga las condiciones
/// al terminar: hacerlo daría a entender que sí.
///
/// ## Los dos permisos, de dos módulos
///
/// **Ver** pide `personal.sueldo.ver` y **cambiar** pide
/// `clients_services.pricing.manage`. Quien administra precios no ve sueldos por eso, y
/// quien ve sueldos no los cambia aquí sin el permiso de precios. Con uno y no el otro, la
/// pantalla enseña lo que corresponde y **esconde lo que no se puede hacer**.
Future<bool?> mostrarSueldoDeReferencia(
  BuildContext context, {
  required CondicionesRepositorioHttp repositorio,
  required String empresaId,
  required String servicioId,
  required LineaComercial linea,
  required DiaDeNegocio hoy,
  required bool puedeCambiar,
  required GuardiaDeSalida guardia,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _DialogoDeSueldo(
    repositorio: repositorio,
    empresaId: empresaId,
    servicioId: servicioId,
    linea: linea,
    hoy: hoy,
    puedeCambiar: puedeCambiar,
    guardia: guardia,
  ),
);

class _DialogoDeSueldo extends StatefulWidget {
  const _DialogoDeSueldo({
    required this.repositorio,
    required this.empresaId,
    required this.servicioId,
    required this.linea,
    required this.hoy,
    required this.puedeCambiar,
    required this.guardia,
  });

  final CondicionesRepositorioHttp repositorio;
  final String empresaId;
  final String servicioId;
  final LineaComercial linea;
  final DiaDeNegocio hoy;
  final bool puedeCambiar;
  final GuardiaDeSalida guardia;

  @override
  State<_DialogoDeSueldo> createState() => _DialogoDeSueldoState();
}

class _DialogoDeSueldoState extends State<_DialogoDeSueldo> {
  List<SueldoDeReferencia>? _historial;
  String? _fallo;
  bool _cargando = true;
  bool _guardando = false;

  /// Si el cambio llegó a guardarse. Es lo que el diálogo devuelve, para que la sección
  /// avise sin tener que releer nada.
  bool _cambio = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = null;
    });

    final r = await widget.repositorio.sueldosDeReferencia(
      empresaId: widget.empresaId,
      servicioId: widget.servicioId,
      lineaId: widget.linea.id,
    );

    if (!mounted) return;

    r.when(
      ok: (h) => setState(() {
        _historial = h;
        _cargando = false;
      }),
      failure: (f) => setState(() {
        _fallo = MensajesHumanos.deMutacion(f);
        _cargando = false;
      }),
    );
  }

  /// El tramo abierto, que es el que está vigente o programado. **A lo sumo uno**: lo
  /// garantiza la exclusión del motor, no una suposición de esta pantalla.
  SueldoDeReferencia? get _abierto {
    for (final s in _historial ?? const <SueldoDeReferencia>[]) {
      if (s.termino == null) return s;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sueldo de referencia (para ofrecer el puesto)'),
    content: SizedBox(
      width: 560,
      child: _cargando
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.linea.nombre, style: AppTypography.bodyStrong),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text(
                    'Lo que se ofrece al reclutar para esta línea. 🚫 NO es el sueldo '
                    'de nadie: el de cada persona vive en su asignación, y cambiar esto '
                    'no se lo cambia a nadie.\n\n'
                    'Tampoco toca el precio del cliente.',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_fallo case final mensaje?) ...[
                    Text(mensaje, style: AppTypography.body),
                    const SizedBox(height: AppSpacing.sm),
                    RisegButton(
                      label: 'Reintentar',
                      variant: RisegButtonVariant.secondary,
                      size: RisegButtonSize.compact,
                      onPressed: _cargar,
                    ),
                  ] else ...[
                    _Historial(historial: _historial ?? const []),
                    if (widget.puedeCambiar) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _Formulario(
                        hoy: widget.hoy,
                        abierto: _abierto,
                        guardando: _guardando,
                        guardia: widget.guardia,
                        nombreDeLaLinea: widget.linea.nombre,
                        alGuardar: _guardar,
                      ),
                    ],
                  ],
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: _guardando ? null : () => Navigator.of(context).pop(_cambio),
        child: const Text('Cerrar'),
      ),
    ],
  );

  Future<void> _guardar(_Movimiento movimiento) async {
    setState(() => _guardando = true);

    final r = await widget.repositorio.moverSueldoDeReferencia(
      empresaId: widget.empresaId,
      servicioId: widget.servicioId,
      lineaId: widget.linea.id,
      desde: movimiento.desde,
      sueldoMenores: movimiento.sueldoMenores,
      bonoMenores: movimiento.bonoMenores,
      moneda: movimiento.moneda,
      motivo: movimiento.motivo,
    );

    if (!mounted) return;

    setState(() => _guardando = false);

    await r.when(
      ok: (_) async {
        _cambio = true;

        // SE RELEE EL HISTORIAL Y NO SE AÑADE LA FILA A MANO: el servidor pudo haber
        // CERRADO el tramo anterior o haberlo CORREGIDO en su sitio según la fecha, y
        // reconstruir esa decisión aquí serían dos reglas para un solo hecho.
        await _cargar();
      },
      failure: (f) async {
        if (!mounted) return;

        RisegFeedback.showError(context, MensajesHumanos.deMutacion(f));
      },
    );
  }
}

/// Lo que el formulario entrega.
class _Movimiento {
  const _Movimiento({
    required this.desde,
    required this.sueldoMenores,
    required this.bonoMenores,
    required this.moneda,
    required this.motivo,
  });

  final DiaDeNegocio desde;
  final int sueldoMenores;
  final int? bonoMenores;
  final String moneda;
  final String motivo;
}

class _Historial extends StatelessWidget {
  const _Historial({required this.historial});

  final List<SueldoDeReferencia> historial;

  @override
  Widget build(BuildContext context) {
    if (historial.isEmpty) {
      return const Text(
        // 🚫 «Ausencia nunca es cero»: una línea sin cifra no ofrece cero pesos, no ofrece
        // nada. Enseñar «$0.00» se leería como «se ofrece el puesto por nada».
        'Esta línea no tiene sueldo de referencia capturado.',
        style: AppTypography.body,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in historial) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: context.colors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dinero(s.sueldoMenores, s.moneda),
                        style: AppTypography.bodyStrong,
                      ),
                      Text(
                        s.bonoMenores == null
                            // Sin bono NO es bono de cero: son dos respuestas distintas y
                            // se dicen distinto.
                            ? 'Sin bono capturado'
                            : 'Bono ${_dinero(s.bonoMenores!, s.moneda)}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Desde ${_dia(s.inicio)}',
                      style: AppTypography.caption,
                    ),
                    Text(
                      s.termino == null
                          ? 'Sin fecha de fin'
                          : 'Hasta ${_dia(s.termino)}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _Formulario extends StatefulWidget {
  const _Formulario({
    required this.hoy,
    required this.abierto,
    required this.guardando,
    required this.guardia,
    required this.nombreDeLaLinea,
    required this.alGuardar,
  });

  final DiaDeNegocio hoy;
  final SueldoDeReferencia? abierto;
  final bool guardando;

  /// D-56 · **regla permanente del dueño**: toda pantalla con «Guardar» se registra. Vale
  /// dentro de un diálogo, y aquí más: perder una cifra y su motivo obliga a volver a
  /// decidir el motivo, que es lo que cuesta.
  final GuardiaDeSalida guardia;

  final String nombreDeLaLinea;
  final Future<void> Function(_Movimiento) alGuardar;

  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario>
    with DeclaraSuTrabajoSinGuardar<_Formulario> {
  @override
  GuardiaDeSalida get guardia => widget.guardia;

  /// ⚠️ **SE COMPARA CONTRA LO CARGADO**, que aquí es «los tres campos vacíos»: el
  /// formulario nace en blanco porque mover el sueldo es un acto nuevo, no la edición de
  /// una fila. La fecha **no cuenta** —viene puesta en hoy y no la escribió nadie—, así que
  /// cambiarla sola no es trabajo que perder.
  @override
  bool get hayCambiosSinGuardar =>
      _sueldo.text.trim().isNotEmpty ||
      _bono.text.trim().isNotEmpty ||
      _motivo.text.trim().isNotEmpty;

  @override
  String get queSePierde =>
      'el sueldo de referencia que estás cambiando en ${widget.nombreDeLaLinea}';

  final _sueldo = TextEditingController();
  final _bono = TextEditingController();
  final _motivo = TextEditingController();

  DateTime? _desde;
  String _moneda = 'MXN';

  String? _errorDeSueldo;
  String? _errorDeBono;
  String? _errorDeMotivo;
  String? _errorDeFecha;

  @override
  void initState() {
    super.initState();

    _desde = DateTime(widget.hoy.anio, widget.hoy.mes, widget.hoy.dia);
    _moneda = widget.abierto?.moneda ?? 'MXN';
  }

  @override
  void dispose() {
    _sueldo.dispose();
    _bono.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RisegFormSection(
    title: 'Cambiar el sueldo de referencia',
    description:
        'El tramo anterior se cierra el día previo. Si la fecha coincide con el '
        'inicio del tramo vigente, se corrige ese en lugar de abrir otro.',
    children: [
      RisegDateField(
        label: 'Desde',
        value: _desde,
        errorText: _errorDeFecha,
        // 🚫 NO SE SUGIERE NINGUNA FECHA DE CALENDARIO. Que RISEG suba las tarifas en
        // enero es una costumbre de RISEG, no una regla del producto, y un campo que
        // propusiera el 1 de enero la convertiría en ley para todas las empresas.
        helperText: 'El primer día en que vale la cifra nueva.',
        onChanged: (v) => setState(() {
          _desde = v;
          _errorDeFecha = null;
        }),
      ),
      const SizedBox(height: AppSpacing.md),
      RisegTextField(
        label: 'Sueldo mensual',
        controller: _sueldo,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        errorText: _errorDeSueldo,
        helperText: 'Tiene que ser mayor que cero.',
        onChanged: (_) {
          if (_errorDeSueldo != null) setState(() => _errorDeSueldo = null);
        },
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: RisegTextField(
              label: 'Bono (opcional)',
              controller: _bono,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              errorText: _errorDeBono,
              helperText: 'Cero sí es una respuesta.',
              onChanged: (_) {
                if (_errorDeBono != null) setState(() => _errorDeBono = null);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: RisegSelect<String>(
              label: 'Moneda',
              value: _moneda,
              items: const [
                RisegSelectItem(value: 'MXN', label: 'MXN · pesos'),
                RisegSelectItem(value: 'USD', label: 'USD · dólares'),
              ],
              onChanged: (v) => setState(() => _moneda = v ?? 'MXN'),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      RisegTextField(
        label: 'Motivo',
        controller: _motivo,
        maxLines: 2,
        errorText: _errorDeMotivo,
        helperText:
            'Rotación, aumento al mínimo o una negociación son tres razones '
            'distintas, y en seis meses nadie recuerda cuál fue.',
        helperMaxLines: 3,
        onChanged: (_) {
          if (_errorDeMotivo != null) setState(() => _errorDeMotivo = null);
        },
      ),
      const SizedBox(height: AppSpacing.md),
      RisegButton(
        label: 'Guardar el cambio',
        loading: widget.guardando,
        onPressed: widget.guardando ? null : _guardar,
      ),
    ],
  );

  Future<void> _guardar() async {
    final desde = _desde;
    final sueldo = _menores(_sueldo.text);
    final textoDelBono = _bono.text.trim();
    final bono = textoDelBono.isEmpty ? null : _menores(textoDelBono);
    final motivo = _motivo.text.trim();

    setState(() {
      _errorDeFecha = desde == null ? 'Falta la fecha.' : null;
      _errorDeSueldo = sueldo == null || sueldo <= 0
          ? 'Escribe una cantidad mayor que cero.'
          : null;
      _errorDeBono = textoDelBono.isNotEmpty && bono == null
          ? 'Escribe una cantidad, por ejemplo 1000.'
          : null;
      _errorDeMotivo = motivo.isEmpty ? 'Di por qué cambia.' : null;
    });

    if (_errorDeFecha != null ||
        _errorDeSueldo != null ||
        _errorDeBono != null ||
        _errorDeMotivo != null) {
      return;
    }

    await widget.alGuardar(
      _Movimiento(
        desde: DiaDeNegocio(desde!.year, desde.month, desde.day),
        sueldoMenores: sueldo!,
        bonoMenores: bono,
        moneda: _moneda,
        motivo: motivo,
      ),
    );

    if (!mounted) return;

    // Guardado: los campos se limpian para que un segundo cambio no herede el anterior,
    // pero la fecha se queda — lo normal es capturar varias líneas con la misma.
    _sueldo.clear();
    _bono.clear();
    _motivo.clear();
  }

  /// `9500.50` → `950050`. Nulo si el texto no es una cantidad. Misma regla que en el
  /// formulario de condición, y por la misma razón: tres decimales no son una cantidad en
  /// pesos, y redondearlos en silencio guardaría una cifra que nadie escribió.
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
}

/// Un día del negocio para la pantalla, o `sin fecha`.
String _dia(DiaDeNegocio? dia) =>
    dia == null ? 'sin fecha' : fechaDeNegocioCorta(dia);

/// `$9,500.00 MXN`. ⚠️ Divide entre 100, que es una suposición sobre la moneda dicha en voz
/// alta: hoy el catálogo del servidor sólo admite monedas de dos decimales.
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
