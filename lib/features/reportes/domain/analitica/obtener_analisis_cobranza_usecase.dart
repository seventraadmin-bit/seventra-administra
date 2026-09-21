import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/complemento_pago_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/cuenta_por_cobrar_antiguedad.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_proyeccion_caja_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/documento_por_emitir_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/entidad_fiscal_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';

/// Filtros de la sección Cuentas por cobrar.
///
/// Son de **snapshot**, no de periodo: la cartera es una foto de hoy.
/// El rango compartido de Reportes no la recorta — y la pantalla lo dice
/// explícitamente, en vez de mezclar los dos universos en silencio.
class FiltroCobranza {
  const FiltroCobranza({
    this.clienteId,
    this.servicioId,
    this.entidadFiscalId,
    this.estatus,
    this.soloConSaldo = false,
    this.soloVencidas = false,
    this.cubeta,
  });

  final String? clienteId;
  final String? servicioId;
  final String? entidadFiscalId;
  final EstatusCuentaPorCobrar? estatus;
  final bool soloConSaldo;
  final bool soloVencidas;
  final RangoAntiguedadCuentaPorCobrar? cubeta;

  bool get hayAlguno =>
      clienteId != null ||
      servicioId != null ||
      entidadFiscalId != null ||
      estatus != null ||
      soloConSaldo ||
      soloVencidas ||
      cubeta != null;

  FiltroCobranza copyWith({
    String? clienteId,
    String? servicioId,
    String? entidadFiscalId,
    EstatusCuentaPorCobrar? estatus,
    bool? soloConSaldo,
    bool? soloVencidas,
    RangoAntiguedadCuentaPorCobrar? cubeta,
    bool limpiarCliente = false,
    bool limpiarServicio = false,
    bool limpiarEntidadFiscal = false,
    bool limpiarEstatus = false,
    bool limpiarCubeta = false,
  }) {
    return FiltroCobranza(
      clienteId: limpiarCliente ? null : (clienteId ?? this.clienteId),
      servicioId: limpiarServicio ? null : (servicioId ?? this.servicioId),
      entidadFiscalId: limpiarEntidadFiscal ? null : (entidadFiscalId ?? this.entidadFiscalId),
      estatus: limpiarEstatus ? null : (estatus ?? this.estatus),
      soloConSaldo: soloConSaldo ?? this.soloConSaldo,
      soloVencidas: soloVencidas ?? this.soloVencidas,
      cubeta: limpiarCubeta ? null : (cubeta ?? this.cubeta),
    );
  }
}

/// Una Cuenta por cobrar con todo lo que la pantalla necesita ya
/// resuelto: nombres, aplicado, días de atraso y cubeta de antigüedad.
///
/// Todos los nombres llegan resueltos EN LOTE por el caso de uso — la
/// fila nunca consulta nada por su cuenta.
class CuentaPorCobrarProyectada {
  const CuentaPorCobrarProyectada({
    required this.cuenta,
    required this.clienteNombre,
    required this.entidadFiscalNombre,
    required this.serviciosNombres,
    required this.aplicado,
    required this.cubeta,
    required this.diasAtraso,
    required this.complementoPendiente,
  });

  final CuentaPorCobrarData cuenta;
  final String clienteNombre;

  /// `null` cuando el documento no trae Entidad fiscal — no se inventa
  /// una.
  final String? entidadFiscalNombre;

  /// Un documento puede facturar VARIOS Servicios (relación N:M real).
  /// La pantalla muestra el único, o "Varios" — nunca elige uno al azar.
  final List<String> serviciosNombres;

  /// Suma de aplicaciones vigentes contra esta cuenta.
  final int aplicado;

  final RangoAntiguedadCuentaPorCobrar cubeta;

  /// Días transcurridos desde el vencimiento. `null` cuando la cuenta no
  /// está vencida o no tiene fecha de vencimiento capturada — nunca 0,
  /// que se confundiría con "vence hoy".
  final int? diasAtraso;

  /// `true` si alguno de los Pagos que la liquidaron sigue debiendo su
  /// Complemento. Derivado con la misma función del dominio que usa la
  /// pantalla de Complementos.
  final bool complementoPendiente;

  int get saldo => cuenta.saldoPendiente;

  bool get estaVencidaHoy => cubeta != RangoAntiguedadCuentaPorCobrar.alCorriente;
}

/// Una cubeta de antigüedad con sus tres lecturas.
class CubetaAntiguedad {
  const CubetaAntiguedad({
    required this.cubeta,
    required this.importe,
    required this.cuentas,
    required this.porcentaje,
  });

  final RangoAntiguedadCuentaPorCobrar cubeta;
  final int importe;
  final int cuentas;

  /// Fracción del saldo total incluido (0.25 == 25 %). `null` cuando el
  /// saldo total es cero: un porcentaje sobre cero no es cero.
  final double? porcentaje;
}

/// Cuánto debe un cliente. `esOtros` agrupa la cola larga.
class ConcentracionCliente {
  const ConcentracionCliente({
    required this.clienteId,
    required this.nombre,
    required this.saldo,
    required this.cuentas,
    this.esOtros = false,
  });

  /// `null` sólo para la fila agregada "Otros".
  final String? clienteId;
  final String nombre;
  final int saldo;
  final int cuentas;
  final bool esOtros;
}

/// Horizonte de cobranza esperada.
enum HorizonteCobranza { proximos7, dias8a15, dias16a30, posterior }

class TramoCobranzaEsperada {
  const TramoCobranzaEsperada({required this.horizonte, required this.importe, required this.compromisos});

  final HorizonteCobranza horizonte;
  final int importe;
  final int compromisos;
}

/// Todo el análisis de cartera, calculado en una sola pasada.
class AnalisisCobranza {
  const AnalisisCobranza({
    required this.cuentas,
    required this.aging,
    required this.concentracion,
    required this.cobranzaEsperada,
    required this.saldoPendiente,
    required this.saldoVencido,
    required this.cuentasConSaldo,
    required this.clientesConSaldo,
    required this.diasAtrasoPromedio,
    required this.proyeccionDisponible,
    required this.cobranzaSinFechaEsperada,
  });

  /// Ya filtradas y ordenadas como las muestra la pantalla.
  final List<CuentaPorCobrarProyectada> cuentas;

  final List<CubetaAntiguedad> aging;
  final List<ConcentracionCliente> concentracion;
  final List<TramoCobranzaEsperada> cobranzaEsperada;

  /// Saldo **a la fecha** de las cuentas incluidas por el filtro.
  final int saldoPendiente;
  final int saldoVencido;
  final int cuentasConSaldo;
  final int clientesConSaldo;

  /// Promedio ponderado por saldo de los días de atraso de lo vencido.
  /// `null` cuando no hay nada vencido con fecha — nunca 0, que diría
  /// "todo al día" cuando en realidad no hay base de cálculo.
  final double? diasAtrasoPromedio;

  /// `false` cuando no hay cuentas financieras configuradas y la
  /// proyección de caja no puede correr: la sección lo dice en vez de
  /// mostrar ceros.
  final bool proyeccionDisponible;

  /// Saldo vencido que NO entra en la cobranza esperada porque nadie ha
  /// reprogramado su cobro. Se muestra aparte: inventarle una fecha
  /// sería fabricar una expectativa.
  final int cobranzaSinFechaEsperada;

  int get saldoAlCorriente => saldoPendiente - saldoVencido;

  /// Fracción vencida del saldo (0.4 == 40 %). `null` sin saldo.
  double? get porcentajeVencido => saldoPendiente == 0 ? null : saldoVencido / saldoPendiente;

  /// Suma de las cubetas — debe ser idéntica a [saldoPendiente]. La
  /// prueba de paridad lo verifica; este getter existe para que la
  /// comprobación sea barata y explícita.
  int get totalAging => aging.fold(0, (a, c) => a + c.importe);
}

/// Análisis de cartera de Reportes.
///
/// **No implementa ninguna regla nueva.** Vencido y antigüedad salen de
/// `cuenta_por_cobrar_antiguedad.dart`; la fecha esperada de cobro sale
/// de `ObtenerProyeccionCajaUseCase` (que ya sabe que una CxC vencida
/// sin `fechaCobroReprogramada` deja de ser predecible); el estado del
/// Complemento sale de `complemento_pago_derivado.dart`. Reportes sólo
/// agrega y presenta.
///
/// Sin N+1: ocho consultas de universo completo y todo lo demás resuelto
/// en memoria contra mapas — nunca una consulta por cuenta.
class ObtenerAnalisisCobranzaUseCase {
  ObtenerAnalisisCobranzaUseCase(
    this._cuentaRepository,
    this._pagoRepository,
    this._complementoRepository,
    this._clienteRepository,
    this._entidadFiscalRepository,
    this._servicioRepository,
    this._documentoRepository,
    this._proyeccionCaja,
    this._servicioEventualRepository,
  );

  final CuentaPorCobrarRepository _cuentaRepository;
  final PagoRepository _pagoRepository;
  final ComplementoPagoRepository _complementoRepository;
  final ClienteRepository _clienteRepository;
  final EntidadFiscalRepository _entidadFiscalRepository;
  final ServicioRepository _servicioRepository;
  final DocumentoPorEmitirRepository _documentoRepository;
  final ObtenerProyeccionCajaUseCase _proyeccionCaja;
  final ServicioEventualRepository _servicioEventualRepository;

  /// Cuántos clientes se listan por nombre antes de agrupar en "Otros".
  static const topConcentracion = 6;

  Future<AnalisisCobranza> ejecutar({FiltroCobranza filtro = const FiltroCobranza(), DateTime? hoy}) async {
    final referencia = hoy ?? DateTime.now();
    final diaHoy = DateTime(referencia.year, referencia.month, referencia.day);

    // Los filtros que el repositorio sabe resolver van en la consulta;
    // los derivados (vencida, cubeta, con saldo) se aplican después,
    // sobre el mismo criterio de dominio que usa el resto de la app.
    final cuentas = await _cuentaRepository.listar(
      clienteId: filtro.clienteId,
      servicioId: filtro.servicioId,
      entidadFiscalId: filtro.entidadFiscalId,
      estatus: filtro.estatus?.name,
    );

    final aplicaciones = await _pagoRepository.listarTodasLasAplicacionesActivas();
    final aplicadoPorCuenta = <String, int>{};
    final pagoIdsPorCuenta = <String, Set<String>>{};
    for (final a in aplicaciones) {
      aplicadoPorCuenta[a.cuentaPorCobrarId] = (aplicadoPorCuenta[a.cuentaPorCobrarId] ?? 0) + a.monto;
      pagoIdsPorCuenta.putIfAbsent(a.cuentaPorCobrarId, () => <String>{}).add(a.pagoId);
    }

    // Estado del Complemento por Pago, con la función del dominio.
    final complementos = await _complementoRepository.listar();
    final complementosPorPago = <String, List<ComplementoPagoData>>{};
    for (final c in complementos) {
      complementosPorPago.putIfAbsent(c.pagoId, () => []).add(c);
    }
    final cuentaPorId = {for (final c in cuentas) c.id: c};
    final cuentasPorPago = <String, List<CuentaPorCobrarData>>{};
    for (final a in aplicaciones) {
      final cuenta = cuentaPorId[a.cuentaPorCobrarId];
      if (cuenta != null) cuentasPorPago.putIfAbsent(a.pagoId, () => []).add(cuenta);
    }
    final pagosConComplementoPendiente = <String>{
      for (final pagoId in cuentasPorPago.keys)
        if (complementoPendienteDePago(
          cuentasDelPago: cuentasPorPago[pagoId]!,
          complementosDelPago: complementosPorPago[pagoId] ?? const [],
        ))
          pagoId,
    };

    // Nombres, todos en lote.
    // schemaVersion 87: una Cuenta por cobrar puede nacer de un
    // Servicio Eventual y entonces no tiene documento ni, a veces,
    // Cliente. Se filtran los nulos en el lote, sin un `if` por fila.
    final documentoIds = cuentas.map((c) => c.documentoPorEmitirId).whereType<String>();
    final documentos = await _documentoRepository.listarPorIds(documentoIds);
    final serviciosPorDocumento = await _documentoRepository.listarServicioIdsPorDocumento(documentoIds);
    final clientes = await _clienteRepository.listarPorIds(cuentas.map((c) => c.clienteId).whereType<String>());
    // La otra mitad de la contraparte (schemaVersion 88): sin esto una
    // CxC de solicitante eventual aparecería sin nombre en el análisis.
    final nombresEventual = await _servicioEventualRepository
        .nombresSolicitantePorIds(cuentas.map((c) => c.servicioEventualId).whereType<String>());
    final entidades = await _entidadFiscalRepository.listarPorIds(
      [for (final d in documentos.values) if (d.entidadFiscalId != null) d.entidadFiscalId!],
    );
    final servicios = await _servicioRepository.listar();
    final nombreServicio = {for (final s in servicios) s.servicio.id: s.servicio.nombre};

    final proyectadas = <CuentaPorCobrarProyectada>[];
    for (final cuenta in cuentas) {
      final cubeta = calcularRangoAntiguedad(cuenta, diaHoy);
      final documento = documentos[cuenta.documentoPorEmitirId];
      final pagosDeLaCuenta = pagoIdsPorCuenta[cuenta.id] ?? const <String>{};

      proyectadas.add(CuentaPorCobrarProyectada(
        cuenta: cuenta,
        clienteNombre: nombreContraparte(
          contraparteDeCuenta(cuenta),
          nombresCliente: {for (final e in clientes.entries) e.key: e.value.nombreComercial},
          nombresServicioEventual: nombresEventual,
        ),
        entidadFiscalNombre: documento?.entidadFiscalId == null
            ? null
            : entidades[documento!.entidadFiscalId]?.razonSocial,
        serviciosNombres: [
          for (final servicioId in serviciosPorDocumento[cuenta.documentoPorEmitirId] ?? const <String>[])
            nombreServicio[servicioId] ?? servicioId,
        ],
        aplicado: aplicadoPorCuenta[cuenta.id] ?? 0,
        cubeta: cubeta,
        diasAtraso: _diasAtraso(cuenta, diaHoy),
        complementoPendiente: pagosDeLaCuenta.any(pagosConComplementoPendiente.contains),
      ));
    }

    final filtradas = [
      for (final p in proyectadas)
        if (!(filtro.soloConSaldo && p.saldo <= 0) &&
            !(filtro.soloVencidas && !p.estaVencidaHoy) &&
            !(filtro.cubeta != null && p.cubeta != filtro.cubeta))
          p,
    ]..sort(_masUrgentePrimero);

    // A partir de aquí todo se calcula SOBRE LAS FILTRADAS: el KPI, el
    // aging, la concentración y la tabla comparten universo por
    // construcción, no por coincidencia.
    var saldoPendiente = 0;
    var saldoVencido = 0;
    var cuentasConSaldo = 0;
    var atrasoPonderado = 0;
    var saldoConAtraso = 0;
    final clientesConSaldo = <String>{};
    final importePorCubeta = <RangoAntiguedadCuentaPorCobrar, int>{};
    final conteoPorCubeta = <RangoAntiguedadCuentaPorCobrar, int>{};
    final saldoPorCliente = <String, int>{};
    final cuentasPorCliente = <String, int>{};
    final nombrePorCliente = <String, String>{};

    for (final p in filtradas) {
      // Una cuenta pagada o cancelada no aporta saldo, y por lo tanto
      // tampoco aporta al aging: nunca se clasifica como vencida.
      if (p.saldo <= 0) continue;
      saldoPendiente += p.saldo;
      cuentasConSaldo++;
      clientesConSaldo.add(claveContraparte(contraparteDeCuenta(p.cuenta)));
      importePorCubeta[p.cubeta] = (importePorCubeta[p.cubeta] ?? 0) + p.saldo;
      conteoPorCubeta[p.cubeta] = (conteoPorCubeta[p.cubeta] ?? 0) + 1;
      // Clave por tipo + id: un Cliente y un eventual con el mismo id
      // jamás se suman entre sí.
      final clave = claveContraparte(contraparteDeCuenta(p.cuenta));
      saldoPorCliente[clave] = (saldoPorCliente[clave] ?? 0) + p.saldo;
      cuentasPorCliente[clave] = (cuentasPorCliente[clave] ?? 0) + 1;
      nombrePorCliente[clave] = p.clienteNombre;
      if (p.estaVencidaHoy) {
        saldoVencido += p.saldo;
        final dias = p.diasAtraso;
        if (dias != null) {
          atrasoPonderado += dias * p.saldo;
          saldoConAtraso += p.saldo;
        }
      }
    }

    final aging = [
      for (final cubeta in RangoAntiguedadCuentaPorCobrar.values)
        CubetaAntiguedad(
          cubeta: cubeta,
          importe: importePorCubeta[cubeta] ?? 0,
          cuentas: conteoPorCubeta[cubeta] ?? 0,
          porcentaje: saldoPendiente == 0 ? null : (importePorCubeta[cubeta] ?? 0) / saldoPendiente,
        ),
    ];

    final proyeccion = await _proyeccionCaja.ejecutar(hoy: diaHoy, hasta: diaHoy.add(const Duration(days: 90)));

    return AnalisisCobranza(
      cuentas: filtradas,
      aging: aging,
      concentracion: _concentracion(saldoPorCliente, cuentasPorCliente, nombrePorCliente),
      cobranzaEsperada: _cobranzaEsperada(proyeccion, diaHoy),
      saldoPendiente: saldoPendiente,
      saldoVencido: saldoVencido,
      cuentasConSaldo: cuentasConSaldo,
      clientesConSaldo: clientesConSaldo.length,
      diasAtrasoPromedio: saldoConAtraso == 0 ? null : atrasoPonderado / saldoConAtraso,
      proyeccionDisponible: proyeccion.cuentasConfiguradas,
      cobranzaSinFechaEsperada: proyeccion.pendientesVencidos
          .where((p) => p.origen == OrigenCompromiso.cuentaPorCobrar)
          .fold(0, (a, p) => a + p.importe),
    );
  }

  /// Vencidas más antiguas primero; entre iguales, el saldo mayor. Es el
  /// orden con el que se trabaja una cartera.
  static int _masUrgentePrimero(CuentaPorCobrarProyectada a, CuentaPorCobrarProyectada b) {
    final porAtraso = (b.diasAtraso ?? -1).compareTo(a.diasAtraso ?? -1);
    if (porAtraso != 0) return porAtraso;
    return b.saldo.compareTo(a.saldo);
  }

  static int? _diasAtraso(CuentaPorCobrarData cuenta, DateTime hoy) {
    if (!estaVencida(cuenta, hoy)) return null;
    final vencimiento = cuenta.fechaVencimiento!;
    return hoy.difference(DateTime(vencimiento.year, vencimiento.month, vencimiento.day)).inDays;
  }

  List<ConcentracionCliente> _concentracion(
    Map<String, int> saldoPorCliente,
    Map<String, int> cuentasPorCliente,
    Map<String, String> nombrePorCliente,
  ) {
    final ordenados = saldoPorCliente.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = ordenados.take(topConcentracion).toList();
    final resto = ordenados.skip(topConcentracion).toList();

    return [
      for (final e in top)
        ConcentracionCliente(
          clienteId: e.key,
          nombre: nombrePorCliente[e.key] ?? e.key,
          saldo: e.value,
          cuentas: cuentasPorCliente[e.key] ?? 0,
        ),
      // Veinte clientes en una gráfica no se leen. La cola larga se
      // agrupa, pero SU IMPORTE NO SE PIERDE: la suma sigue siendo el
      // saldo total.
      if (resto.isNotEmpty)
        ConcentracionCliente(
          clienteId: null,
          nombre: '',
          saldo: resto.fold(0, (a, e) => a + e.value),
          cuentas: resto.fold(0, (a, e) => a + (cuentasPorCliente[e.key] ?? 0)),
          esOtros: true,
        ),
    ];
  }

  List<TramoCobranzaEsperada> _cobranzaEsperada(ProyeccionCaja proyeccion, DateTime hoy) {
    final importe = {for (final h in HorizonteCobranza.values) h: 0};
    final conteo = {for (final h in HorizonteCobranza.values) h: 0};

    for (final compromiso in proyeccion.compromisos) {
      if (compromiso.origen != OrigenCompromiso.cuentaPorCobrar) continue;
      if (compromiso.tipo != TipoCompromiso.entrada) continue;
      final dias = compromiso.fecha.difference(hoy).inDays;
      final horizonte = switch (dias) {
        <= 7 => HorizonteCobranza.proximos7,
        <= 15 => HorizonteCobranza.dias8a15,
        <= 30 => HorizonteCobranza.dias16a30,
        _ => HorizonteCobranza.posterior,
      };
      importe[horizonte] = importe[horizonte]! + compromiso.importe;
      conteo[horizonte] = conteo[horizonte]! + 1;
    }

    return [
      for (final h in HorizonteCobranza.values)
        TramoCobranzaEsperada(horizonte: h, importe: importe[h]!, compromisos: conteo[h]!),
    ];
  }
}

/// Si un Pago sigue debiendo su Complemento, usando exclusivamente las
/// funciones del dominio (`pagoRequiereComplemento` +
/// `complementoPendiente`). Se extrae aquí para no repetir la
/// composición en tres lugares.
bool complementoPendienteDePago({
  required List<CuentaPorCobrarData> cuentasDelPago,
  required List<ComplementoPagoData> complementosDelPago,
}) {
  if (!pagoRequiereComplemento(cuentasDelPago)) return false;
  return complementoPendiente(requiereComplemento: true, complementosDelPago: complementosDelPago);
}
