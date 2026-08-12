import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';

import 'formato_moneda_notificacion.dart';
import 'resultado_notificacion.dart';

/// Pagos recibidos hoy — Etapa 14B. Ventana deliberadamente simple
/// (solo el día de hoy, se resetea cada día) — reutiliza
/// `PagoRepository.listar(rangoInicio, rangoFin)` tal cual (ya filtra
/// por `fechaPago`), cero cambios al repositorio.
class ObtenerNotificacionesPagosUseCase {
  ObtenerNotificacionesPagosUseCase(this._pagoRepository, this._clienteRepository);

  final PagoRepository _pagoRepository;
  final ClienteRepository _clienteRepository;

  Future<List<ResultadoNotificacion>> ejecutar({DateTime? hoy}) async {
    final referencia = hoy ?? DateTime.now();
    final inicioDia = DateTime(referencia.year, referencia.month, referencia.day);
    final finDia = DateTime(referencia.year, referencia.month, referencia.day, 23, 59, 59);

    final pagos = await _pagoRepository.listar(estatus: 'registrado', rangoInicio: inicioDia, rangoFin: finDia);
    if (pagos.isEmpty) return const [];

    final clientes = await _clienteRepository.listarActivos();
    final nombrePorCliente = {for (final c in clientes) c.id: c.nombreComercial};

    return [
      for (final pago in pagos)
        ResultadoNotificacion(
          id: pago.id,
          titulo: nombrePorCliente[pago.clienteId] ?? pago.clienteId,
          subtitulo: formatoMonedaNotificacion(pago.montoTotal),
          ruta: '/finanzas/pagos',
          urgente: false,
        ),
    ];
  }
}
