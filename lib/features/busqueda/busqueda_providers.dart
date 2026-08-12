import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compras/compras_providers.dart';
import '../inventario/inventario_providers.dart';
import '../organizacion/organizacion_providers.dart';
import '../personal/personal_providers.dart';
import '../telefonia/telefonia_providers.dart';
import '../usuarios/usuarios_providers.dart';
import '../vehiculos/vehiculos_providers.dart';
import 'domain/usecases/buscar_articulos_usecase.dart';
import 'domain/usecases/buscar_clientes_usecase.dart';
import 'domain/usecases/buscar_compras_usecase.dart';
import 'domain/usecases/buscar_empleados_usecase.dart';
import 'domain/usecases/buscar_global_usecase.dart';
import 'domain/usecases/buscar_lineas_telefonicas_usecase.dart';
import 'domain/usecases/buscar_servicios_usecase.dart';
import 'domain/usecases/buscar_usuarios_usecase.dart';
import 'domain/usecases/buscar_vehiculos_usecase.dart';

/// Providers de Búsqueda global (Etapa 14A) — solo compone
/// repositorios ya existentes de sus dominios propios, nunca declara
/// un repositorio nuevo (mismo criterio que Reportes/Dashboard).
final buscarEmpleadosUseCaseProvider = Provider<BuscarEmpleadosUseCase>((ref) {
  return BuscarEmpleadosUseCase(ref.watch(empleadoRepositoryProvider));
});

final buscarClientesUseCaseProvider = Provider<BuscarClientesUseCase>((ref) {
  return BuscarClientesUseCase(ref.watch(clienteRepositoryProvider));
});

final buscarServiciosUseCaseProvider = Provider<BuscarServiciosUseCase>((ref) {
  return BuscarServiciosUseCase(ref.watch(servicioRepositoryProvider));
});

final buscarArticulosUseCaseProvider = Provider<BuscarArticulosUseCase>((ref) {
  return BuscarArticulosUseCase(ref.watch(articuloRepositoryProvider));
});

final buscarComprasUseCaseProvider = Provider<BuscarComprasUseCase>((ref) {
  return BuscarComprasUseCase(ref.watch(compraRepositoryProvider));
});

final buscarVehiculosUseCaseProvider = Provider<BuscarVehiculosUseCase>((ref) {
  return BuscarVehiculosUseCase(ref.watch(vehiculoRepositoryProvider));
});

/// Nunca depende de `EquipoTelefonicoRepository` — regla dura, ver el
/// doc comment de `BuscarLineasTelefonicasUseCase`.
final buscarLineasTelefonicasUseCaseProvider = Provider<BuscarLineasTelefonicasUseCase>((ref) {
  return BuscarLineasTelefonicasUseCase(ref.watch(lineaTelefonicaRepositoryProvider));
});

final buscarUsuariosUseCaseProvider = Provider<BuscarUsuariosUseCase>((ref) {
  return BuscarUsuariosUseCase(ref.watch(usuarioRepositoryProvider));
});

final buscarGlobalUseCaseProvider = Provider<BuscarGlobalUseCase>((ref) {
  return BuscarGlobalUseCase(
    ref.watch(buscarEmpleadosUseCaseProvider),
    ref.watch(buscarClientesUseCaseProvider),
    ref.watch(buscarServiciosUseCaseProvider),
    ref.watch(buscarArticulosUseCaseProvider),
    ref.watch(buscarComprasUseCaseProvider),
    ref.watch(buscarVehiculosUseCaseProvider),
    ref.watch(buscarLineasTelefonicasUseCaseProvider),
    ref.watch(buscarUsuariosUseCaseProvider),
  );
});
