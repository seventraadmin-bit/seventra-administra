import 'package:riseg_one/core/database/app_database.dart';

/// Estado derivado del próximo mantenimiento programado (Etapa 8D) —
/// nunca notificaciones automáticas (instrucción explícita de Marlon:
/// "solo alertas derivadas"), solo una clasificación calculada en el
/// momento de consultar.
enum EstadoProximoMantenimiento { alDia, proximo, vencido }

/// El próximo mantenimiento derivado — `estado` es el peor de los dos
/// criterios que apliquen (fecha/kilometraje): si cualquiera de los dos
/// está vencido, el conjunto se considera vencido; si no, "próximo" si
/// cualquiera de los dos está dentro de su umbral. Modela
/// independientemente los casos de prueba "próximo por fecha" y
/// "próximo por km" (punto 11) sin duplicar la función.
class ProximoMantenimientoVehiculo {
  const ProximoMantenimientoVehiculo({required this.fecha, required this.kilometraje, required this.estado});

  final DateTime? fecha;
  final int? kilometraje;
  final EstadoProximoMantenimiento estado;
}

/// Umbrales por defecto (Etapa 8D) — mismo criterio que el umbral de 30
/// días ya confirmado por Marlon para documentos (Etapa 8C): un valor
/// razonable, no configuración administrable todavía. `1000` km es un
/// margen típico de aviso previo a un servicio; ambos ajustables sin
/// migración si Marlon los quiere distintos.
const umbralDiasProximoMantenimiento = 30;
const umbralKilometrajeProximoMantenimiento = 1000;

/// Deriva el próximo mantenimiento de un Vehículo (Etapa 8D, punto 5) —
/// [historialOrdenadoDesc] ya viene ordenado descendente por `fecha`
/// (mismo orden de `VehiculoMantenimientoRepository.listarPorVehiculo`);
/// se toma la fila más reciente que tenga programado `proximoFecha` y/o
/// `proximoKilometraje`. `null` si ninguna fila tiene nada programado
/// ("sin próximo mantenimiento programado" en la UI).
ProximoMantenimientoVehiculo? calcularProximoMantenimiento(
  List<VehiculoMantenimientoData> historialOrdenadoDesc,
  int? kilometrajeActual, {
  DateTime? hoy,
  int umbralDias = umbralDiasProximoMantenimiento,
  int umbralKilometraje = umbralKilometrajeProximoMantenimiento,
}) {
  VehiculoMantenimientoData? conProximo;
  for (final registro in historialOrdenadoDesc) {
    if (registro.proximoMantenimientoFecha != null || registro.proximoMantenimientoKilometraje != null) {
      conProximo = registro;
      break;
    }
  }
  if (conProximo == null) return null;

  final fecha = conProximo.proximoMantenimientoFecha;
  final km = conProximo.proximoMantenimientoKilometraje;
  var estado = EstadoProximoMantenimiento.alDia;

  if (fecha != null) {
    final referencia = hoy ?? DateTime.now();
    final hoySoloFecha = DateTime(referencia.year, referencia.month, referencia.day);
    final fechaSoloFecha = DateTime(fecha.year, fecha.month, fecha.day);
    final dias = fechaSoloFecha.difference(hoySoloFecha).inDays;
    if (dias < 0) {
      estado = EstadoProximoMantenimiento.vencido;
    } else if (dias <= umbralDias) {
      estado = EstadoProximoMantenimiento.proximo;
    }
  }

  if (km != null && kilometrajeActual != null && estado != EstadoProximoMantenimiento.vencido) {
    final restante = km - kilometrajeActual;
    if (restante <= 0) {
      estado = EstadoProximoMantenimiento.vencido;
    } else if (restante <= umbralKilometraje) {
      estado = EstadoProximoMantenimiento.proximo;
    }
  } else if (km != null && kilometrajeActual != null && km - kilometrajeActual <= 0) {
    estado = EstadoProximoMantenimiento.vencido;
  }

  return ProximoMantenimientoVehiculo(fecha: fecha, kilometraje: km, estado: estado);
}
