import 'package:riseg_one/features/finanzas/domain/usecases/obtener_complementos_pendientes_usecase.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/resolver_nombres_contraparte_usecase.dart';

import 'formato_moneda_notificacion.dart';
import 'resultado_notificacion.dart';
import 'package:riseg_one/features/finanzas/domain/contraparte_cobro.dart';

/// Complementos de pago pendientes — séptima categoría del Centro de
/// notificaciones (autorizada explícitamente por Marlon en la etapa
/// "Complemento dependiente del Pago real"; el alcance de la Etapa 14B
/// era de 6 categorías fijas).
///
/// La obligación nace de un **Pago real**, nunca de una fecha del
/// calendario comercial: un Pago registrado, con al menos una aplicación
/// activa a una Cuenta por cobrar PPD-con-complemento, que todavía no
/// tiene Complemento vigente.
///
/// **No reimplementa la fórmula**: delega en
/// `ObtenerComplementosPendientesUseCase`, que a su vez usa
/// `complemento_pago_derivado.dart`. Una sola definición de "pendiente"
/// en todo el sistema.
///
/// Deliberadamente **sin noción de vencido**: no existe una regla de
/// plazo fiscal en el sistema, y Marlon decidió no modelarla como
/// preferencia comercial por cliente. Mostrar una fecha límite
/// inexistente sería inventarla.
class ObtenerNotificacionesComplementosUseCase {
  ObtenerNotificacionesComplementosUseCase(this._obtenerPendientes, this._resolverNombres);

  final ObtenerComplementosPendientesUseCase _obtenerPendientes;
  final ResolverNombresContraparteUseCase _resolverNombres;

  Future<List<ResultadoNotificacion>> ejecutar({DateTime? hoy}) async {
    final proyeccion = await _obtenerPendientes.ejecutar();
    if (proyeccion.pendientes.isEmpty) return const [];

    final nombres = await _resolverNombres.paraPagos([for (final p in proyeccion.pendientes) p.pago]);

    return [
      for (final pendiente in proyeccion.pendientes)
        ResultadoNotificacion(
          id: pendiente.pago.id,
          titulo: nombres.de(contraparteDePago(pendiente.pago)),
          // Folio, fecha REAL del pago y monto — los tres hechos que
          // permiten reconocer de qué pago se trata sin abrir nada.
          subtitulo: '${pendiente.pago.folioPago} · '
              '${_fechaCorta(pendiente.pago.fechaPago)} · '
              '${formatoMonedaNotificacion(pendiente.pago.montoTotal)}',
          // Al contexto fiscal correcto: Complementos, nunca a la etapa
          // comercial del Servicio.
          ruta: '/finanzas/complementos',
          // Sin plazo real no hay forma honesta de decir "urgente".
          urgente: false,
        ),
    ];
  }

  String _fechaCorta(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }
}
