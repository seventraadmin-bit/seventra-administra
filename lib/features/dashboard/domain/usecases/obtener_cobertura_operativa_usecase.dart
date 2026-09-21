import 'package:riseg_one/features/organizacion/data/tables/servicio_table.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_comercial_repository.dart';
import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/data/tables/vacante_operativa_table.dart' show EstatusVacanteOperativa;
import 'package:riseg_one/features/personal/domain/repositories/vacante_operativa_repository.dart';

/// Cobertura de UNA línea comercial (perfil/puesto) dentro de un
/// Servicio — el detalle de Parte E ("cuando un servicio tiene varias
/// líneas/perfiles, debe mostrarse cuál está sin cubrir"). Nunca se
/// suma un perfil contra otro — cada línea es su propio
/// requerido/cubierto, igual que a nivel Servicio.
class CoberturaLinea {
  const CoberturaLinea({required this.lineaComercialId, required this.puestoNombre, required this.requerido, required this.cubierto});

  final String lineaComercialId;
  final String puestoNombre;
  final int requerido;
  final int cubierto;

  int get vacantes => requerido - cubierto < 0 ? 0 : requerido - cubierto;
  double get porcentaje => requerido == 0 ? 100 : (cubierto / requerido * 100).clamp(0, 100);
  bool get completo => vacantes == 0;
}

/// Cobertura de UN Servicio activo — la fila de la tabla "Cobertura
/// operativa" (Parte D del pedido).
///
/// [requerido]/[cubierto] se derivan en vivo de
/// `ServicioLineaComercialVigencia.cantidadElementos` (por línea/perfil
/// vigente hoy) vs. `AsignacionServicio` vigentes con esa
/// `lineaComercialId` — nunca contando empleados sueltos. [cubierto]
/// nunca excede [requerido] por línea (Invariante U: "personal extra
/// puede existir, pero no aumenta artificialmente la cobertura sobre
/// 100%"). [lineas] es el mismo cálculo desglosado por perfil (Parte
/// E) — la suma de sus `requerido`/`cubierto` es exactamente
/// [requerido]/[cubierto].
class CoberturaServicio {
  const CoberturaServicio({
    required this.servicioId,
    required this.servicioNombre,
    required this.requerido,
    required this.cubierto,
    required this.lineas,
    this.vacanteMasAntigua,
  });

  final String servicioId;
  final String servicioNombre;
  final int requerido;
  final int cubierto;
  final List<CoberturaLinea> lineas;

  /// Antigüedad de la vacante abierta más antigua de ESTE Servicio,
  /// según la bitácora `VacanteOperativa` — `null` si no hay ninguna
  /// vacante rastreada (cobertura completa, o el déficit existe pero
  /// nunca pasó por un evento de `AsignacionServicio` que lo registrara
  /// — ver la limitación documentada en el doc comment de
  /// `VacanteOperativa`). Nunca se inventa una duración donde no hay
  /// dato real.
  final Duration? vacanteMasAntigua;

  /// Déficit real — SIEMPRE `requerido - cubierto` (nunca negativo),
  /// derivado del snapshot en vivo, nunca del conteo de la bitácora de
  /// vacantes (que puede tener huecos documentados) — así la invariante
  /// "vacantes = requeridos - cubiertos" se cumple siempre por
  /// construcción.
  int get vacantes => requerido - cubierto < 0 ? 0 : requerido - cubierto;

  /// `100` cuando no hay ningún requerimiento vigente (nada que
  /// cubrir) — nunca división por cero.
  double get porcentaje => requerido == 0 ? 100 : (cubierto / requerido * 100).clamp(0, 100);

  bool get completo => vacantes == 0;
}

/// Resumen agregado de cobertura operativa — Parte C.1/C.2/C.3 y Parte
/// D del pedido. Solo Servicios `activo` participan (Parte D: "mostrar
/// cada servicio activo"; un Servicio `terminado`/`suspendido`/
/// `cotizado` no aporta ni resta cobertura).
class ResumenCoberturaOperativa {
  const ResumenCoberturaOperativa({
    required this.serviciosActivos,
    required this.servicios,
    required this.totalRequerido,
    required this.totalCubierto,
    this.vacanteMasAntigua,
  });

  final int serviciosActivos;
  final List<CoberturaServicio> servicios;
  final int totalRequerido;
  final int totalCubierto;

  /// La más antigua entre TODAS las vacantes rastreadas de todos los
  /// Servicios activos — `null` si no hay ninguna rastreada.
  final Duration? vacanteMasAntigua;

  int get totalVacantes => totalRequerido - totalCubierto < 0 ? 0 : totalRequerido - totalCubierto;

  double get porcentajeGlobal => totalRequerido == 0 ? 100 : (totalCubierto / totalRequerido * 100).clamp(0, 100);

  /// Cuántos de [serviciosActivos] están 100% cubiertos — Etapa 15 v1.1:
  /// el % agregado de POSICIONES puede verse peor de lo que realmente
  /// está la operación cuando conviven servicios completos con
  /// servicios vacíos (ej. 5/14 posiciones = 36%, pero 3 de 9 Servicios
  /// ya están completos). Son dos preguntas distintas — nunca se
  /// reemplazan entre sí.
  int get serviciosCompletos => servicios.where((s) => s.completo).length;
}

class ObtenerCoberturaOperativaUseCase {
  ObtenerCoberturaOperativaUseCase(this._servicioRepository, this._servicioComercialRepository, this._vacanteOperativaRepository);

  final ServicioRepository _servicioRepository;
  final ServicioComercialRepository _servicioComercialRepository;
  final VacanteOperativaRepository _vacanteOperativaRepository;

  Future<ResumenCoberturaOperativa> ejecutar({required DateTime hoy}) async {
    final todos = await _servicioRepository.listar();
    final activos = todos.where((s) => s.servicio.estatus == EstatusServicio.activo.name).toList();

    final vacantesAbiertas = await _vacanteOperativaRepository.listarAbiertas();
    final vacantesPorServicio = <String, List<DateTime>>{};
    for (final v in vacantesAbiertas) {
      if (v.estatus != EstatusVacanteOperativa.abierta.name) continue;
      (vacantesPorServicio[v.servicioId] ??= []).add(v.fechaApertura);
    }

    // Batch (Etapa 20): UNA sola consulta compuesta para TODOS los
    // Servicios activos, en vez de una llamada a
    // `listarLineasEnFecha` por Servicio (N+1 real, corregido) —
    // `listarCoberturaPorServicios` es un método dedicado que calcula
    // exactamente lo mismo (misma clasificación de vigencia, misma
    // atribución histórica) sin el costo de N×M consultas.
    final coberturaPorLinea = await _servicioComercialRepository.listarCoberturaPorServicios(
      activos.map((item) => item.servicio.id).toList(),
      hoy,
    );
    final lineasPorServicio = <String, List<CoberturaLinea>>{};
    for (final fila in coberturaPorLinea) {
      final req = fila.requerido;
      final cub = fila.cubierto > req ? req : fila.cubierto; // Invariante U — nunca excede el requerido.
      (lineasPorServicio[fila.servicioId] ??= []).add(
        CoberturaLinea(lineaComercialId: fila.lineaComercialId, puestoNombre: fila.puestoNombre, requerido: req, cubierto: cub),
      );
    }

    final resultado = <CoberturaServicio>[];
    var totalRequerido = 0;
    var totalCubierto = 0;
    DateTime? masAntiguaGlobal;

    for (final item in activos) {
      final lineasCobertura = lineasPorServicio[item.servicio.id] ?? const <CoberturaLinea>[];
      var requerido = 0;
      var cubierto = 0;
      for (final linea in lineasCobertura) {
        requerido += linea.requerido;
        cubierto += linea.cubierto;
      }

      final fechasVacantes = vacantesPorServicio[item.servicio.id];
      DateTime? masAntiguaServicio;
      if (fechasVacantes != null && fechasVacantes.isNotEmpty) {
        masAntiguaServicio = fechasVacantes.reduce((a, b) => a.isBefore(b) ? a : b);
        if (masAntiguaGlobal == null || masAntiguaServicio.isBefore(masAntiguaGlobal)) {
          masAntiguaGlobal = masAntiguaServicio;
        }
      }

      resultado.add(
        CoberturaServicio(
          servicioId: item.servicio.id,
          servicioNombre: item.servicio.nombre,
          requerido: requerido,
          cubierto: cubierto,
          lineas: lineasCobertura,
          vacanteMasAntigua: masAntiguaServicio == null ? null : hoy.difference(masAntiguaServicio),
        ),
      );

      totalRequerido += requerido;
      totalCubierto += cubierto;
    }

    return ResumenCoberturaOperativa(
      serviciosActivos: activos.length,
      servicios: resultado,
      totalRequerido: totalRequerido,
      totalCubierto: totalCubierto,
      vacanteMasAntigua: masAntiguaGlobal == null ? null : hoy.difference(masAntiguaGlobal),
    );
  }
}
