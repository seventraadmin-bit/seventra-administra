import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/finanzas/data/tables/pago_table.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/complemento_pago_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_financiera_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/cuenta_por_cobrar_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/ingreso_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/complemento_pago_derivado.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';

import 'comparacion_periodo.dart';
import 'obtener_analisis_cobranza_usecase.dart' show complementoPendienteDePago;
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';
import 'package:riseg_one/features/servicios_eventuales/domain/repositories/servicio_eventual_repository.dart';

/// Obligación de Complemento de pago, proyectada por Pago.
///
/// Tres estados y sólo tres. **No es un motor fiscal nuevo**: sale
/// íntegramente de `complemento_pago_derivado.dart`.
enum EstadoComplementoPago {
  /// Ninguna de las Cuentas que el Pago liquidó es PPD con complemento.
  noAplica,

  /// Lo exige y no hay uno `registrado` vigente. Un complemento
  /// cancelado en el histórico NO satisface la obligación.
  pendiente,

  /// Existe un complemento vigente.
  registrado,
}

/// Una aplicación de un Pago contra una Cuenta, con el documento ya
/// resuelto.
class AplicacionProyectada {
  const AplicacionProyectada({
    required this.aplicacion,
    required this.cuentaPorCobrarId,
    required this.folioDocumento,
    required this.monto,
  });

  final AplicacionPagoData aplicacion;
  final String cuentaPorCobrarId;

  /// Folio del documento cubierto; `null` cuando la Cuenta todavía no
  /// tiene folio capturado.
  final String? folioDocumento;

  final int monto;
}

/// Un Pago con todo lo que la pantalla necesita.
///
/// **Un Pago = una fila.** Sus aplicaciones cuelgan de aquí; nunca se
/// proyecta `AplicacionPago` como objeto principal, porque un pago de
/// $50,000 repartido en dos facturas aparecería como $100,000.
class PagoProyectado {
  const PagoProyectado({
    required this.pago,
    required this.clienteNombre,
    required this.cuentaFinancieraNombre,
    required this.aplicaciones,
    required this.estadoComplemento,
    required this.complementoVigenteUuid,
  });

  final PagoData pago;
  final String clienteNombre;

  /// Cuenta financiera que recibió el dinero.
  ///
  /// NO vive en `Pago`: el dominio la guarda en el `Ingreso` que el
  /// propio Pago genera (relación 1:1 por FK). Se resuelve por ahí, en
  /// lote. `null` cuando el Pago no la capturó — nunca se infiere de
  /// `cuentaBancariaDestino`, que es texto libre.
  final String? cuentaFinancieraNombre;

  final List<AplicacionProyectada> aplicaciones;
  final EstadoComplementoPago estadoComplemento;

  /// UUID del complemento vigente, si lo hay — para poder navegar a él.
  final String? complementoVigenteUuid;

  int get importe => pago.montoTotal;

  /// Lo aplicado según el propio Pago (campo del dominio), no una suma
  /// recalculada: si divergiera de las aplicaciones sería un bug del
  /// dominio, y Reportes debe mostrarlo, no taparlo.
  int get aplicado => pago.montoAplicado;

  int get porAplicar => pago.montoTotal - pago.montoAplicado;

  int get documentosCubiertos => aplicaciones.length;
}

/// Análisis de Pagos del periodo.
class AnalisisPagos {
  const AnalisisPagos({
    required this.rango,
    required this.pagos,
    required this.importeRecibido,
    required this.importeAplicado,
    required this.importePorAplicar,
    required this.clientesQuePagaron,
    required this.complementosPendientes,
    required this.complementosRegistrados,
  });

  final RangoPeriodo rango;

  /// Un elemento por Pago, ya ordenados (más reciente primero).
  final List<PagoProyectado> pagos;

  final int importeRecibido;
  final int importeAplicado;

  /// Dinero recibido que todavía no se aplicó a ninguna Cuenta. El
  /// dominio lo permite explícitamente (un Pago sin aplicaciones es un
  /// estado válido), así que la cifra es real y no un error.
  final int importePorAplicar;

  final int clientesQuePagaron;
  final int complementosPendientes;
  final int complementosRegistrados;

  int get pagosRecibidos => pagos.length;
}

/// Proyecta los Pagos del periodo con sus aplicaciones y el estado real
/// de su Complemento.
///
/// Sin N+1: cinco consultas de universo y todo resuelto contra mapas.
/// Reutiliza `listarTodasLasAplicacionesActivas` justamente porque la
/// alternativa (`listarAplicacionesPorPago` por fila) es el N+1 que el
/// repositorio documenta evitar.
class ObtenerAnalisisPagosUseCase {
  ObtenerAnalisisPagosUseCase(
    this._pagoRepository,
    this._cuentaRepository,
    this._complementoRepository,
    this._clienteRepository,
    this._ingresoRepository,
    this._cuentaFinancieraRepository,
    this._servicioEventualRepository,
  );

  final PagoRepository _pagoRepository;
  final CuentaPorCobrarRepository _cuentaRepository;
  final ComplementoPagoRepository _complementoRepository;
  final ClienteRepository _clienteRepository;
  final IngresoRepository _ingresoRepository;
  final CuentaFinancieraRepository _cuentaFinancieraRepository;
  final ServicioEventualRepository _servicioEventualRepository;

  Future<AnalisisPagos> ejecutar({required RangoPeriodo rango, String? clienteId, String? formaPago}) async {
    final desde = DateTime(rango.inicio.year, rango.inicio.month, rango.inicio.day);
    final hasta = DateTime(rango.fin.year, rango.fin.month, rango.fin.day, 23, 59, 59, 999);

    // Sólo Pagos vigentes: uno cancelado no es dinero recibido.
    final pagos = await _pagoRepository.listar(
      estatus: EstatusPago.registrado.name,
      clienteId: clienteId,
      formaPago: formaPago,
      rangoInicio: desde,
      rangoFin: hasta,
    );
    final aplicaciones = await _pagoRepository.listarTodasLasAplicacionesActivas();
    final cuentas = await _cuentaRepository.listar();
    final complementos = await _complementoRepository.listar();
    final clientes = await _clienteRepository.listarPorIds(pagos.map((p) => p.clienteId).whereType<String>());
    final nombresEventual = await _servicioEventualRepository
        .nombresSolicitantePorIds(pagos.map((p) => p.servicioEventualId).whereType<String>());
    // El Ingreso automático nace con la MISMA fecha del Pago, así que
    // el mismo rango lo cubre: una consulta, no una por pago.
    final ingresos = await _ingresoRepository.listar(rangoInicio: desde, rangoFin: hasta);
    final cuentasFinancieras = await _cuentaFinancieraRepository.listar();
    final nombreCuentaFinanciera = {for (final c in cuentasFinancieras) c.id: c.nombre};
    final cuentaFinancieraPorPago = {
      for (final i in ingresos)
        if (i.pagoId != null && i.cuentaFinancieraId != null)
          i.pagoId!: nombreCuentaFinanciera[i.cuentaFinancieraId!],
    };

    final cuentaPorId = {for (final c in cuentas) c.id: c};
    final aplicacionesPorPago = <String, List<AplicacionPagoData>>{};
    for (final a in aplicaciones) {
      aplicacionesPorPago.putIfAbsent(a.pagoId, () => []).add(a);
    }
    final complementosPorPago = <String, List<ComplementoPagoData>>{};
    for (final c in complementos) {
      complementosPorPago.putIfAbsent(c.pagoId, () => []).add(c);
    }

    final proyectados = <PagoProyectado>[];
    var importeRecibido = 0;
    var importeAplicado = 0;
    var pendientes = 0;
    var registrados = 0;
    final clientesQuePagaron = <String>{};

    for (final pago in pagos) {
      final suyas = aplicacionesPorPago[pago.id] ?? const <AplicacionPagoData>[];
      final cuentasDelPago = [
        for (final a in suyas)
          if (cuentaPorId[a.cuentaPorCobrarId] != null) cuentaPorId[a.cuentaPorCobrarId]!,
      ];
      final historico = complementosPorPago[pago.id] ?? const <ComplementoPagoData>[];
      final vigente = complementoVigente(historico);

      final estado = !pagoRequiereComplemento(cuentasDelPago)
          ? EstadoComplementoPago.noAplica
          : (complementoPendienteDePago(cuentasDelPago: cuentasDelPago, complementosDelPago: historico)
              ? EstadoComplementoPago.pendiente
              : EstadoComplementoPago.registrado);

      if (estado == EstadoComplementoPago.pendiente) pendientes++;
      if (estado == EstadoComplementoPago.registrado) registrados++;

      importeRecibido += pago.montoTotal;
      importeAplicado += pago.montoAplicado;
      clientesQuePagaron.add(claveContraparte(contraparteDePago(pago)));

      proyectados.add(PagoProyectado(
        pago: pago,
        clienteNombre: nombreContraparte(
          contraparteDePago(pago),
          nombresCliente: {for (final e in clientes.entries) e.key: e.value.nombreComercial},
          nombresServicioEventual: nombresEventual,
        ),
        cuentaFinancieraNombre: cuentaFinancieraPorPago[pago.id],
        aplicaciones: [
          for (final a in suyas)
            AplicacionProyectada(
              aplicacion: a,
              cuentaPorCobrarId: a.cuentaPorCobrarId,
              folioDocumento: cuentaPorId[a.cuentaPorCobrarId]?.folioDocumento,
              monto: a.monto,
            ),
        ],
        estadoComplemento: estado,
        complementoVigenteUuid: vigente?.uuid,
      ));
    }

    proyectados.sort((a, b) => b.pago.fechaPago.compareTo(a.pago.fechaPago));

    return AnalisisPagos(
      rango: rango,
      pagos: proyectados,
      importeRecibido: importeRecibido,
      importeAplicado: importeAplicado,
      importePorAplicar: importeRecibido - importeAplicado,
      clientesQuePagaron: clientesQuePagaron.length,
      complementosPendientes: pendientes,
      complementosRegistrados: registrados,
    );
  }
}
