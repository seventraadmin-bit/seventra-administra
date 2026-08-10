import 'package:riseg_one/features/organizacion/domain/repositories/servicio_repository.dart';
import 'package:riseg_one/features/personal/domain/repositories/empleado_repository.dart';

import '../repositories/articulo_repository.dart';
import '../repositories/inventario_repository.dart';

/// Resultado mínimo de un Artículo — la búsqueda contextual nunca
/// expone `ArticuloData` crudo a la UI, mismo criterio que
/// `EmpleadoOpcion` (Etapa 7B).
class ArticuloResultadoBusqueda {
  const ArticuloResultadoBusqueda({required this.id, required this.folio, required this.nombre});
  final String id;
  final String folio;
  final String nombre;
}

class UnidadResultadoBusqueda {
  const UnidadResultadoBusqueda({
    required this.articuloId,
    required this.codigo,
    required this.numeroSerie,
    required this.articuloNombre,
  });
  final String articuloId;
  final String codigo;
  final String numeroSerie;
  final String articuloNombre;
}

class EmpleadoResultadoBusqueda {
  const EmpleadoResultadoBusqueda({required this.id, required this.numeroEmpleado, required this.nombreCompleto});
  final String id;
  final int numeroEmpleado;
  final String nombreCompleto;
}

class ServicioResultadoBusqueda {
  const ServicioResultadoBusqueda({required this.id, required this.codigo, required this.nombre});
  final String id;
  final String codigo;
  final String nombre;
}

/// Resultado agrupado por tipo — la UI decide cómo presentar cada
/// grupo, la búsqueda solo resuelve coincidencias.
class ResultadoBusquedaInventario {
  const ResultadoBusquedaInventario({
    required this.articulos,
    required this.unidades,
    required this.empleados,
    required this.servicios,
  });

  final List<ArticuloResultadoBusqueda> articulos;
  final List<UnidadResultadoBusqueda> unidades;
  final List<EmpleadoResultadoBusqueda> empleados;
  final List<ServicioResultadoBusqueda> servicios;

  bool get vacio => articulos.isEmpty && unidades.isEmpty && empleados.isEmpty && servicios.isEmpty;

  static const vacia = ResultadoBusquedaInventario(articulos: [], unidades: [], empleados: [], servicios: []);
}

const _maximoResultadosPorGrupo = 8;

/// Búsqueda contextual de Inventario (Etapa 7D) — un solo cuadro de
/// texto resuelve, a la vez, Artículo (nombre/folio), unidad
/// serializada (código `UNI-######`/número de serie), Empleado
/// (nombre/número) y Servicio (nombre/código). Coincidencia simple por
/// substring, sin distinguir mayúsculas — deliberadamente sin
/// relevancia/ranking sofisticado ("sin complicar la operación").
///
/// Dependencia cruzada a `personal`/`organizacion` (lectura) — mismo
/// patrón ya establecido por `ObtenerEmpleadosResponsablesServicioUseCase`
/// (Etapa 7B): vive en Inventario porque "buscar en todo Inventario"
/// es una pregunta de Inventario, la UI nunca importa los repositorios
/// de Personal/Organización directamente.
class BuscarInventarioUseCase {
  BuscarInventarioUseCase(
    this._articuloRepository,
    this._inventarioRepository,
    this._empleadoRepository,
    this._servicioRepository,
  );

  final ArticuloRepository _articuloRepository;
  final InventarioRepository _inventarioRepository;
  final EmpleadoRepository _empleadoRepository;
  final ServicioRepository _servicioRepository;

  Future<ResultadoBusquedaInventario> ejecutar(String consulta) async {
    final termino = consulta.trim().toLowerCase();
    if (termino.isEmpty) return ResultadoBusquedaInventario.vacia;

    final articulosTodos = await _articuloRepository.listar();
    final articulos = articulosTodos
        .where((a) => a.nombre.toLowerCase().contains(termino) || a.folio.toLowerCase().contains(termino))
        .take(_maximoResultadosPorGrupo)
        .map((a) => ArticuloResultadoBusqueda(id: a.id, folio: a.folio, nombre: a.nombre))
        .toList();

    final unidadesTodas = await _inventarioRepository.listarTodasUnidades();
    final articulosPorId = {for (final a in articulosTodos) a.id: a};
    final unidades = unidadesTodas
        .where((u) => u.codigo.toLowerCase().contains(termino) || u.numeroSerie.toLowerCase().contains(termino))
        .take(_maximoResultadosPorGrupo)
        .map(
          (u) => UnidadResultadoBusqueda(
            articuloId: u.articuloId,
            codigo: u.codigo,
            numeroSerie: u.numeroSerie,
            articuloNombre: articulosPorId[u.articuloId]?.nombre ?? u.articuloId,
          ),
        )
        .toList();

    final empleadosTodos = await _empleadoRepository.listar();
    final empleados = empleadosTodos
        .where((e) {
          final nombreCompleto = [e.nombres, e.apellidoPaterno, e.apellidoMaterno]
              .whereType<String>()
              .join(' ')
              .toLowerCase();
          return nombreCompleto.contains(termino) || e.numeroEmpleado.toString().contains(termino);
        })
        .take(_maximoResultadosPorGrupo)
        .map(
          (e) => EmpleadoResultadoBusqueda(
            id: e.id,
            numeroEmpleado: e.numeroEmpleado,
            nombreCompleto:
                [e.nombres, e.apellidoPaterno, e.apellidoMaterno].whereType<String>().where((p) => p.trim().isNotEmpty).join(' '),
          ),
        )
        .toList();

    final serviciosTodos = await _servicioRepository.listar();
    final servicios = serviciosTodos
        .where(
          (s) =>
              s.servicio.nombre.toLowerCase().contains(termino) || s.servicio.codigo.toLowerCase().contains(termino),
        )
        .take(_maximoResultadosPorGrupo)
        .map((s) => ServicioResultadoBusqueda(id: s.servicio.id, codigo: s.servicio.codigo, nombre: s.servicio.nombre))
        .toList();

    return ResultadoBusquedaInventario(articulos: articulos, unidades: unidades, empleados: empleados, servicios: servicios);
  }
}
