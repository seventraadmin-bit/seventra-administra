import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/compras/domain/repositories/compra_repository.dart';
import 'package:riseg_one/features/finanzas/domain/repositories/pago_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/articulo_repository.dart';
import 'package:riseg_one/features/inventario/domain/repositories/inventario_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/cliente_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/vacante_operativa_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/linea_telefonica_repository.dart';
import 'package:riseg_one/features/telefonia/domain/repositories/recarga_linea_telefonica_repository.dart';

const _tamanoLista = 5;

/// Un Pago reciente ya con el nombre del Cliente resuelto — Etapa 13.
class PagoReciente {
  const PagoReciente({required this.pago, required this.clienteNombre});

  final PagoData pago;
  final String clienteNombre;
}

/// Un movimiento de Inventario reciente ya con el nombre del Artículo
/// resuelto — Etapa 13.
class MovimientoReciente {
  const MovimientoReciente({required this.movimiento, required this.articuloNombre});

  final MovimientoInventarioData movimiento;
  final String articuloNombre;
}

/// Una recarga reciente ya con el código de la Línea resuelto — Etapa
/// 13. El destino histórico (empleado/servicio) se resuelve en la
/// pantalla contra los mismos catálogos que ya carga
/// `ObtenerResumenTelefoniaUseCase` cuando aplica, no aquí.
class RecargaReciente {
  const RecargaReciente({required this.recarga, required this.lineaCodigo, this.destino});

  final RecargaLineaTelefonicaData recarga;
  final String lineaCodigo;
  final DestinoHistoricoRecarga? destino;
}

/// Un evento de vacante (apertura o cobertura) dentro del periodo —
/// Parte N: "vacante abierta"/"vacante cubierta" como eventos de
/// negocio de la Actividad reciente. Sin nombre de puesto (requeriría
/// una segunda consulta por línea comercial solo para 5 filas
/// truncadas) — el nombre del Servicio ya identifica el evento sin
/// ambigüedad para este propósito.
class VacanteReciente {
  const VacanteReciente({required this.servicioNombre, required this.abierta, required this.fecha});

  final String servicioNombre;

  /// `true` = evento de apertura, `false` = evento de cobertura.
  final bool abierta;
  final DateTime fecha;
}

/// Actividad reciente del Dashboard (Etapa 13) — listas cortas (5
/// filas), nunca un log de auditoría. Cada campo `null` cuando el
/// llamador no incluyó esa sección (sin autorización).
///
/// Personal (altas/bajas), Nómina y Vehículos (mantenimientos) NO
/// viven aquí — ya son listas dentro de los DTOs de Reportes
/// (`ResumenPersonalReportes`/`ResumenNominaReportes`/
/// `ResumenVehiculosReportes.detalleMantenimientos`) que el Dashboard
/// ya pide para otras zonas; reutilizarlas ahí evita repetir la
/// consulta.
class ActividadRecienteDashboard {
  const ActividadRecienteDashboard({
    this.comprasRecientes,
    this.pagosRecientes,
    this.movimientosRecientes,
    this.recargasRecientes,
    this.vacantesRecientes,
  });

  final List<CompraData>? comprasRecientes;
  final List<PagoReciente>? pagosRecientes;
  final List<MovimientoReciente>? movimientosRecientes;
  final List<RecargaReciente>? recargasRecientes;
  final List<VacanteReciente>? vacantesRecientes;
}

/// Compone 6 repositorios ya existentes, cada uno gateado por su
/// propio permiso — nunca se consulta uno sin su `incluirXxx`.
/// `CompraRepository.listar`/`InventarioRepository.listarMovimientos`
/// ya vienen ordenados desc por fecha (solo se truncan); las recargas
/// no vienen ordenadas y se ordenan aquí en Dart antes de truncar.
/// `ArticuloRepository`/`ClienteRepository`/`LineaTelefonicaRepository`
/// solo resuelven nombres/códigos para las 5 filas ya truncadas — mismo
/// patrón de mapa `id → nombre` ya usado en Reportes (12A/12C), nunca
/// N+1.
class ObtenerActividadRecienteUseCase {
  ObtenerActividadRecienteUseCase(
    this._compraRepository,
    this._pagoRepository,
    this._clienteRepository,
    this._inventarioRepository,
    this._articuloRepository,
    this._recargaRepository,
    this._lineaTelefonicaRepository,
    this._vacanteOperativaRepository,
    this._servicioRepository,
  );

  final CompraRepository _compraRepository;
  final PagoRepository _pagoRepository;
  final ClienteRepository _clienteRepository;
  final InventarioRepository _inventarioRepository;
  final ArticuloRepository _articuloRepository;
  final RecargaLineaTelefonicaRepository _recargaRepository;
  final LineaTelefonicaRepository _lineaTelefonicaRepository;
  final VacanteOperativaRepository _vacanteOperativaRepository;
  final ServicioRepository _servicioRepository;

  Future<ActividadRecienteDashboard> ejecutar({
    required bool incluirCompras,
    required bool incluirPagos,
    required bool incluirInventario,
    required bool incluirTelefonia,
    required bool incluirComercial,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  }) async {
    final comprasRecientes = incluirCompras
        ? (await _compraRepository.listar(estatus: 'registrada', desde: rangoInicio, hasta: rangoFin)).take(_tamanoLista).toList()
        : null;

    List<PagoReciente>? pagosRecientes;
    if (incluirPagos) {
      final pagos = (await _pagoRepository.listar(estatus: 'registrado', rangoInicio: rangoInicio, rangoFin: rangoFin))
          .take(_tamanoLista)
          .toList();
      final clientes = await _clienteRepository.listarActivos();
      final nombrePorCliente = {for (final c in clientes) c.id: c.nombreComercial};
      pagosRecientes = [
        for (final pago in pagos) PagoReciente(pago: pago, clienteNombre: nombrePorCliente[pago.clienteId] ?? '—'),
      ];
    }

    List<MovimientoReciente>? movimientosRecientes;
    if (incluirInventario) {
      final movimientos =
          (await _inventarioRepository.listarMovimientos(desde: rangoInicio, hasta: rangoFin)).take(_tamanoLista).toList();
      final articulos = await _articuloRepository.listar(soloActivos: false);
      final nombrePorArticulo = {for (final a in articulos) a.id: a.nombre};
      movimientosRecientes = [
        for (final m in movimientos)
          MovimientoReciente(movimiento: m, articuloNombre: nombrePorArticulo[m.articuloId] ?? m.articuloId),
      ];
    }

    List<RecargaReciente>? recargasRecientes;
    if (incluirTelefonia) {
      final recargas = await _recargaRepository.listarConDestinoEnRango(desde: rangoInicio, hasta: rangoFin);
      final ordenadas = [...recargas]..sort((a, b) => b.recarga.fecha.compareTo(a.recarga.fecha));
      final truncadas = ordenadas.take(_tamanoLista).toList();
      final lineas = await _lineaTelefonicaRepository.listar(soloActivos: false);
      final codigoPorLinea = {for (final l in lineas) l.id: l.codigo};
      recargasRecientes = [
        for (final fila in truncadas)
          RecargaReciente(
            recarga: fila.recarga,
            lineaCodigo: codigoPorLinea[fila.recarga.lineaTelefonicaId] ?? fila.recarga.lineaTelefonicaId,
            destino: fila.destino,
          ),
      ];
    }

    List<VacanteReciente>? vacantesRecientes;
    if (incluirComercial && rangoInicio != null && rangoFin != null) {
      final vacantes = await _vacanteOperativaRepository.listarRecientes(rangoInicio: rangoInicio, rangoFin: rangoFin);
      final servicios = await _servicioRepository.listar();
      final nombrePorServicio = {for (final s in servicios) s.servicio.id: s.servicio.nombre};

      final eventos = <VacanteReciente>[];
      for (final v in vacantes) {
        final nombre = nombrePorServicio[v.servicioId] ?? '—';
        if (!v.fechaApertura.isBefore(rangoInicio) && !v.fechaApertura.isAfter(rangoFin)) {
          eventos.add(VacanteReciente(servicioNombre: nombre, abierta: true, fecha: v.fechaApertura));
        }
        final fechaCobertura = v.fechaCobertura;
        if (fechaCobertura != null && !fechaCobertura.isBefore(rangoInicio) && !fechaCobertura.isAfter(rangoFin)) {
          eventos.add(VacanteReciente(servicioNombre: nombre, abierta: false, fecha: fechaCobertura));
        }
      }
      eventos.sort((a, b) => b.fecha.compareTo(a.fecha));
      vacantesRecientes = eventos.take(_tamanoLista).toList();
    }

    return ActividadRecienteDashboard(
      comprasRecientes: comprasRecientes,
      pagosRecientes: pagosRecientes,
      movimientosRecientes: movimientosRecientes,
      recargasRecientes: recargasRecientes,
      vacantesRecientes: vacantesRecientes,
    );
  }
}
