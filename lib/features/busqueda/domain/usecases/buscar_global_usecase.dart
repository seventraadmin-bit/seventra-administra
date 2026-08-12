import 'buscar_articulos_usecase.dart';
import 'buscar_clientes_usecase.dart';
import 'buscar_compras_usecase.dart';
import 'buscar_empleados_usecase.dart';
import 'buscar_lineas_telefonicas_usecase.dart';
import 'buscar_servicios_usecase.dart';
import 'buscar_usuarios_usecase.dart';
import 'buscar_vehiculos_usecase.dart';
import 'resultado_busqueda_entidad.dart';

/// Resultados de Búsqueda global (Etapa 14A) — cada campo es `null`
/// cuando la sesión no tiene el permiso de esa entidad (nunca se
/// calcula ni se consulta en ese caso, guardia real en
/// `BusquedaController`), lista vacía `[]` cuando sí tiene el permiso
/// pero no hubo coincidencias — mismo criterio `null` vs. `[]` que el
/// resto del proyecto usa para `null` vs. `0`.
class ResultadosBusquedaGlobal {
  const ResultadosBusquedaGlobal({
    this.empleados,
    this.clientes,
    this.servicios,
    this.articulos,
    this.compras,
    this.vehiculos,
    this.lineasTelefonicas,
    this.usuarios,
  });

  final List<ResultadoBusquedaEntidad>? empleados;
  final List<ResultadoBusquedaEntidad>? clientes;
  final List<ResultadoBusquedaEntidad>? servicios;
  final List<ResultadoBusquedaEntidad>? articulos;
  final List<ResultadoBusquedaEntidad>? compras;
  final List<ResultadoBusquedaEntidad>? vehiculos;
  final List<ResultadoBusquedaEntidad>? lineasTelefonicas;
  final List<ResultadoBusquedaEntidad>? usuarios;

  bool get sinResultados => [
        empleados,
        clientes,
        servicios,
        articulos,
        compras,
        vehiculos,
        lineasTelefonicas,
        usuarios,
      ].every((grupo) => grupo == null || grupo.isEmpty);
}

/// Compone los 8 `Buscar*UseCase` — nunca importa un repositorio
/// directamente. Cada `incluirXxx` la resuelve el llamador consultando
/// `PermissionService` antes de invocar `ejecutar` (mismo criterio que
/// `ObtenerResumenGeneralUseCase` de Reportes) — este use case solo
/// confía en lo que se le pide.
class BuscarGlobalUseCase {
  BuscarGlobalUseCase(
    this._buscarEmpleados,
    this._buscarClientes,
    this._buscarServicios,
    this._buscarArticulos,
    this._buscarCompras,
    this._buscarVehiculos,
    this._buscarLineasTelefonicas,
    this._buscarUsuarios,
  );

  final BuscarEmpleadosUseCase _buscarEmpleados;
  final BuscarClientesUseCase _buscarClientes;
  final BuscarServiciosUseCase _buscarServicios;
  final BuscarArticulosUseCase _buscarArticulos;
  final BuscarComprasUseCase _buscarCompras;
  final BuscarVehiculosUseCase _buscarVehiculos;
  final BuscarLineasTelefonicasUseCase _buscarLineasTelefonicas;
  final BuscarUsuariosUseCase _buscarUsuarios;

  Future<ResultadosBusquedaGlobal> ejecutar(
    String texto, {
    required bool incluirPersonal,
    required bool incluirComercial,
    required bool incluirInventario,
    required bool incluirCompras,
    required bool incluirVehiculos,
    required bool incluirTelefonia,
    required bool incluirUsuarios,
  }) async {
    return ResultadosBusquedaGlobal(
      empleados: incluirPersonal ? await _buscarEmpleados.ejecutar(texto) : null,
      clientes: incluirComercial ? await _buscarClientes.ejecutar(texto) : null,
      servicios: incluirComercial ? await _buscarServicios.ejecutar(texto) : null,
      articulos: incluirInventario ? await _buscarArticulos.ejecutar(texto) : null,
      compras: incluirCompras ? await _buscarCompras.ejecutar(texto) : null,
      vehiculos: incluirVehiculos ? await _buscarVehiculos.ejecutar(texto) : null,
      lineasTelefonicas: incluirTelefonia ? await _buscarLineasTelefonicas.ejecutar(texto) : null,
      usuarios: incluirUsuarios ? await _buscarUsuarios.ejecutar(texto) : null,
    );
  }
}
