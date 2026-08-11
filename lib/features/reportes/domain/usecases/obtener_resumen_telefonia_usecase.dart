import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/asignacion_linea_telefonica_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_equipo_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/recarga_linea_telefonica_repository.dart';

class RecargaPorClave {
  const RecargaPorClave({required this.clave, required this.total});
  final String clave;
  final int total;
}

/// Resumen de Telefonía para el bloque "Operación" de Reportes (Etapa
/// 12C). **Regla dura, sin excepción para Maestro**: este caso de uso
/// nunca importa `EquipoTelefonicoRepository`/
/// `RevelarCredencialEquipoTelefonicoUseCase`/`CredentialCipher` — ni
/// para contraseña ni para correo. La atribución de recargas por
/// Servicio/Empleado es histórica (a quién correspondía la línea el
/// día de la recarga, vía `listarConDestinoEnRango`) — un cambio de
/// responsable posterior nunca reescribe una recarga ya atribuida.
class ResumenTelefoniaReportes {
  const ResumenTelefoniaReportes({
    required this.equiposPorEstatus,
    required this.lineasPorEstatus,
    required this.lineasSinEquipo,
    required this.lineasSinAsignacion,
    required this.totalRecargasEnPeriodo,
    required this.recargasPorServicio,
    required this.recargasPorEmpleado,
    required this.recargasSinAtribucion,
  });

  /// Snapshots — a la fecha de hoy.
  final Map<String, int> equiposPorEstatus;
  final Map<String, int> lineasPorEstatus;
  final int lineasSinEquipo;
  final int lineasSinAsignacion;

  /// Del periodo consultado.
  final int totalRecargasEnPeriodo;
  final List<RecargaPorClave> recargasPorServicio;
  final List<RecargaPorClave> recargasPorEmpleado;
  final int recargasSinAtribucion;
}

class ObtenerResumenTelefoniaUseCase {
  ObtenerResumenTelefoniaUseCase(
    this._inventarioRepository,
    this._lineaRepository,
    this._lineaEquipoRepository,
    this._asignacionLineaRepository,
    this._recargaRepository,
    this._empleadoRepository,
    this._servicioRepository,
  );

  final InventarioRepository _inventarioRepository;
  final LineaTelefonicaRepository _lineaRepository;
  final LineaTelefonicaEquipoRepository _lineaEquipoRepository;
  final AsignacionLineaTelefonicaRepository _asignacionLineaRepository;
  final RecargaLineaTelefonicaRepository _recargaRepository;
  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;

  Future<ResumenTelefoniaReportes> ejecutar({DateTime? rangoInicio, DateTime? rangoFin}) async {
    final equipos = await _inventarioRepository.listarUnidadesTelefono();
    final equiposPorEstatus = <String, int>{};
    for (final equipo in equipos) {
      equiposPorEstatus[equipo.estatus] = (equiposPorEstatus[equipo.estatus] ?? 0) + 1;
    }

    final lineas = await _lineaRepository.listar(soloActivos: false);
    final lineasPorEstatus = <String, int>{};
    for (final linea in lineas) {
      lineasPorEstatus[linea.estatus] = (lineasPorEstatus[linea.estatus] ?? 0) + 1;
    }

    final equipoActualPorLinea = await _lineaEquipoRepository.obtenerActualesPorTodasLasLineas();
    final asignacionActivaPorLinea = await _asignacionLineaRepository.obtenerActivasPorTodasLasLineas();
    final lineasSinEquipo = lineas.where((l) => !equipoActualPorLinea.containsKey(l.id)).length;
    final lineasSinAsignacion = lineas.where((l) => !asignacionActivaPorLinea.containsKey(l.id)).length;

    final totalRecargas = await _recargaRepository.totalPorRango(desde: rangoInicio, hasta: rangoFin);
    final recargasConDestino = await _recargaRepository.listarConDestinoEnRango(desde: rangoInicio, hasta: rangoFin);

    final empleados = await _empleadoRepository.listarParaReporte();
    final nombrePorEmpleado = {for (final e in empleados) e.id: e.nombreCompleto};
    final servicios = await _servicioRepository.listar();
    final nombrePorServicio = {for (final s in servicios) s.servicio.id: s.servicio.nombre};

    final porServicio = <String, int>{};
    final porEmpleado = <String, int>{};
    var sinAtribucion = 0;
    for (final fila in recargasConDestino) {
      final destino = fila.destino;
      if (destino?.servicioId != null) {
        final nombre = nombrePorServicio[destino!.servicioId] ?? destino.servicioId!;
        porServicio[nombre] = (porServicio[nombre] ?? 0) + fila.recarga.importe;
      } else if (destino?.empleadoId != null) {
        final nombre = nombrePorEmpleado[destino!.empleadoId] ?? destino.empleadoId!;
        porEmpleado[nombre] = (porEmpleado[nombre] ?? 0) + fila.recarga.importe;
      } else {
        sinAtribucion += fila.recarga.importe;
      }
    }

    List<RecargaPorClave> aLista(Map<String, int> mapa) =>
        [for (final entrada in mapa.entries) RecargaPorClave(clave: entrada.key, total: entrada.value)]
          ..sort((a, b) => b.total.compareTo(a.total));

    return ResumenTelefoniaReportes(
      equiposPorEstatus: equiposPorEstatus,
      lineasPorEstatus: lineasPorEstatus,
      lineasSinEquipo: lineasSinEquipo,
      lineasSinAsignacion: lineasSinAsignacion,
      totalRecargasEnPeriodo: totalRecargas,
      recargasPorServicio: aLista(porServicio),
      recargasPorEmpleado: aLista(porEmpleado),
      recargasSinAtribucion: sinAtribucion,
    );
  }
}
