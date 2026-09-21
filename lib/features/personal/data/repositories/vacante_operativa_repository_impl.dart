import 'package:drift/drift.dart';
import 'package:riseg_one/core/database/app_database.dart';

import '../../domain/repositories/vacante_operativa_repository.dart';
import '../tables/vacante_operativa_table.dart' show EstatusVacanteOperativa;

class VacanteOperativaRepositoryImpl implements VacanteOperativaRepository {
  VacanteOperativaRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<VacanteOperativaData>> listarAbiertas() {
    return (_db.select(_db.vacanteOperativa)
          ..where((t) => t.estatus.equals(EstatusVacanteOperativa.abierta.name))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaApertura)]))
        .get();
  }

  @override
  Future<List<VacanteOperativaData>> listarAbiertasPorServicio(String servicioId) {
    return (_db.select(_db.vacanteOperativa)
          ..where((t) => t.servicioId.equals(servicioId) & t.estatus.equals(EstatusVacanteOperativa.abierta.name))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaApertura)]))
        .get();
  }

  @override
  Future<List<VacanteOperativaData>> listarPorLinea(String lineaComercialId) {
    return (_db.select(_db.vacanteOperativa)
          ..where((t) => t.lineaComercialId.equals(lineaComercialId))
          ..orderBy([(t) => OrderingTerm.desc(t.fechaApertura)]))
        .get();
  }

  @override
  Future<List<VacanteOperativaData>> listarRecientes({required DateTime rangoInicio, required DateTime rangoFin}) {
    return (_db.select(_db.vacanteOperativa)
          ..where(
            (t) =>
                t.fechaApertura.isBetweenValues(rangoInicio, rangoFin) |
                (t.fechaCobertura.isNotNull() & t.fechaCobertura.isBetweenValues(rangoInicio, rangoFin)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.fechaApertura)]))
        .get();
  }

  @override
  Future<Duration?> promedioDuracionCobertura() async {
    final cubiertas = await (_db.select(_db.vacanteOperativa)..where((t) => t.estatus.equals(EstatusVacanteOperativa.cubierta.name))).get();
    if (cubiertas.isEmpty) return null;
    final totalMs = cubiertas.fold<int>(0, (acc, v) => acc + v.fechaCobertura!.difference(v.fechaApertura).inMilliseconds);
    return Duration(milliseconds: totalMs ~/ cubiertas.length);
  }

  @override
  Future<void> sincronizarLinea({
    required String servicioId,
    required String lineaComercialId,
    required int requerido,
    required int cubierto,
    required DateTime fecha,
    required String motivoApertura,
    String? asignacionOrigenId,
    String? asignacionCoberturaId,
  }) async {
    final abiertas = await (_db.select(_db.vacanteOperativa)
          ..where((t) => t.lineaComercialId.equals(lineaComercialId) & t.estatus.equals(EstatusVacanteOperativa.abierta.name))
          ..orderBy([(t) => OrderingTerm.asc(t.fechaApertura)]))
        .get();

    // Invariante: el déficit nunca es negativo — un exceso de cobertura
    // (más asignados que `cantidadElementos`) no genera vacantes en
    // negativo ni las "adelanta".
    final deficitCrudo = requerido - cubierto;
    final deficit = deficitCrudo < 0 ? 0 : deficitCrudo;

    if (deficit > abiertas.length) {
      final faltan = deficit - abiertas.length;
      for (var i = 0; i < faltan; i++) {
        await _db.into(_db.vacanteOperativa).insert(
              VacanteOperativaCompanion.insert(
                servicioId: servicioId,
                lineaComercialId: lineaComercialId,
                fechaApertura: fecha,
                motivoApertura: motivoApertura,
                // Solo la primera fila de este lote se asocia a la
                // asignación real que la originó — nunca se inventa una
                // atribución para el resto (en la práctica, cada evento
                // real mueve el déficit de una unidad a la vez).
                asignacionOrigenId: Value(i == 0 ? asignacionOrigenId : null),
              ),
            );
      }
    } else if (deficit < abiertas.length) {
      final aCerrar = abiertas.length - deficit;
      for (var i = 0; i < aCerrar; i++) {
        final vacante = abiertas[i];
        await (_db.update(_db.vacanteOperativa)..where((t) => t.id.equals(vacante.id))).write(
          VacanteOperativaCompanion(
            estatus: Value(EstatusVacanteOperativa.cubierta.name),
            fechaCobertura: Value(fecha),
            asignacionCoberturaId: Value(i == 0 ? asignacionCoberturaId : null),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
  }
}
