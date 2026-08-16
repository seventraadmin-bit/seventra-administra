import 'package:riseg_one/core/database/app_database.dart';

import '../usecases/eliminar_egreso_fisicamente_usecase.dart';

/// Dinero pagado por RISEG (Etapa 4K.1) — captura manual, y desde las
/// Etapas 10/6D también generado automáticamente por `Compra`
/// (`Compra.egresoId`) y `PagoNomina` (`PagoNomina.egresoId`), ambas
/// `onDelete: restrict` — un Egreso de esos orígenes nunca se elimina
/// físicamente de forma aislada (ver `eliminarFisicamente`).
abstract interface class EgresoRepository {
  Future<EgresoData?> obtenerPorId(String id);

  Future<List<EgresoData>> listar({
    String? estatus,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    DateTime? rangoInicio,
    DateTime? rangoFin,
  });

  Future<List<EgresoEventoData>> listarEventos(String egresoId);

  Future<EgresoData> crear({
    required String folioEgreso,
    required int monto,
    required DateTime fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    required String formaPago,
    String? beneficiario,
    required String concepto,
    String? observaciones,
    String? actorUsuarioId,
  });

  /// Corrige metadatos administrativos — nunca `monto`.
  Future<EgresoData> corregir({
    required String egresoId,
    DateTime? fecha,
    String? categoriaFinancieraId,
    String? servicioId,
    String? sucursalId,
    String? areaId,
    String? cuentaCaja,
    String? formaPago,
    String? beneficiario,
    String? concepto,
    String? observaciones,
    required String motivo,
    String? actorUsuarioId,
  });

  /// Corrige exclusivamente el `monto` de un Egreso ya existente,
  /// conservando folio/id — nunca cancela ni crea uno nuevo (Etapa 15:
  /// única consumidora real es la corrección de partidas de una
  /// `Compra`, cuando el total cambia). Deliberadamente separado de
  /// [corregir] (metadatos) para no diluir esa regla ya establecida
  /// ("nunca monto") en el resto del proyecto — este método es la única
  /// puerta explícita para la excepción real.
  Future<EgresoData> corregirMonto({
    required String egresoId,
    required int nuevoMonto,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<EgresoData> cancelar({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  });

  Future<AttachmentData> adjuntarComprobante({
    required String egresoId,
    required String originalFileName,
    required String storedFileName,
    required String path,
    required String mimeType,
    required int sizeBytes,
    String? actorUsuarioId,
  });

  /// Suma de `monto` de Egresos `registrado` en el rango dado —
  /// consulta base para reportes (Resolución 5 de Marlon).
  Future<int> totalEgresos({DateTime? rangoInicio, DateTime? rangoFin});

  /// Suma de `monto` de Egresos `registrado` en el rango, agrupada por
  /// `categoriaFinancieraId` — Etapa 12A (Reportes). La llave `null`
  /// agrupa los Egresos sin categoría asignada.
  Future<Map<String?, int>> totalPorCategoria({DateTime? rangoInicio, DateTime? rangoFin});

  /// Resumen de solo lectura para el mensaje de confirmación dinámico
  /// de la UI antes de pedir el motivo — ver el doc comment de
  /// `ResumenEliminacionEgreso`.
  Future<ResumenEliminacionEgreso> obtenerResumenEliminacionFisica(String egresoId);

  /// Eliminación física extraordinaria (Etapa 15, Usuario Maestro) —
  /// ver el doc comment de la implementación para las condiciones
  /// exactas de elegibilidad.
  Future<EliminarEgresoFisicamenteResultado> eliminarFisicamente({
    required String egresoId,
    required String motivo,
    String? actorUsuarioId,
  });
}
