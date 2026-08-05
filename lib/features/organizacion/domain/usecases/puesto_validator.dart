import 'package:riseg_one/features/organizacion/data/tables/puesto_table.dart';

import '../repositories/area_repository.dart';
import 'puesto_errors.dart';

/// Datos de Puesto tal como llegan del formulario — sin validar, todo
/// crudo. `areaId` vacío significa "sin seleccionar", igual que `tipo`
/// y `nivelJerarquico` nulos.
class PuestoBorrador {
  const PuestoBorrador({
    required this.nombre,
    required this.areaId,
    required this.tipo,
    required this.nivelJerarquico,
    this.descripcion,
  });

  final String nombre;
  final String areaId;
  final TipoPuesto? tipo;
  final int? nivelJerarquico;
  final String? descripcion;
}

/// Puesto ya validado y normalizado (recortado) — listo para persistir.
class PuestoValidado {
  const PuestoValidado({
    required this.nombre,
    required this.areaId,
    required this.tipo,
    required this.nivelJerarquico,
    this.descripcion,
  });

  final String nombre;
  final String areaId;
  final TipoPuesto tipo;
  final int nivelJerarquico;
  final String? descripcion;
}

/// Validación compartida entre alta y edición de Puesto — nunca
/// duplicada entre `CrearPuestoUseCase` y `ActualizarPuestoUseCase`.
///
/// A diferencia de `DireccionValidator` (puro, sin dependencias), este
/// validador necesita confirmar que el Área exista y esté activa, así
/// que depende de `AreaRepository` — la UI nunca es la única responsable
/// de ofrecer solo Áreas activas en su selector; la regla también se
/// aplica aquí, en dominio, sin importar qué mandó la pantalla.
class PuestoValidator {
  PuestoValidator(this._areaRepository);

  final AreaRepository _areaRepository;

  static const nivelMinimo = 1;
  static const nivelMaximo = 10;

  Future<({PuestoValidado? resultado, List<ErrorCampoPuesto> errores})> validar(PuestoBorrador borrador) async {
    final errores = <ErrorCampoPuesto>[];

    final nombre = borrador.nombre.trim();
    if (nombre.isEmpty) {
      errores.add(const ErrorCampoPuesto(campo: CampoPuesto.nombre, codigo: CodigoErrorPuesto.requerido));
    }

    final areaId = borrador.areaId.trim();
    if (areaId.isEmpty) {
      errores.add(const ErrorCampoPuesto(campo: CampoPuesto.area, codigo: CodigoErrorPuesto.requerido));
    } else {
      final area = await _areaRepository.obtenerPorId(areaId);
      if (area == null) {
        errores.add(const ErrorCampoPuesto(campo: CampoPuesto.area, codigo: CodigoErrorPuesto.noExiste));
      } else if (!area.activo) {
        errores.add(const ErrorCampoPuesto(campo: CampoPuesto.area, codigo: CodigoErrorPuesto.inactiva));
      }
    }

    if (borrador.tipo == null) {
      errores.add(const ErrorCampoPuesto(campo: CampoPuesto.tipo, codigo: CodigoErrorPuesto.requerido));
    }

    final nivel = borrador.nivelJerarquico;
    if (nivel == null) {
      errores.add(const ErrorCampoPuesto(campo: CampoPuesto.nivelJerarquico, codigo: CodigoErrorPuesto.requerido));
    } else if (nivel < nivelMinimo || nivel > nivelMaximo) {
      errores.add(const ErrorCampoPuesto(campo: CampoPuesto.nivelJerarquico, codigo: CodigoErrorPuesto.fueraDeRango));
    }

    if (errores.isNotEmpty) {
      return (resultado: null, errores: errores);
    }

    final descripcionNormalizada = borrador.descripcion?.trim();

    return (
      resultado: PuestoValidado(
        nombre: nombre,
        areaId: areaId,
        tipo: borrador.tipo!,
        nivelJerarquico: nivel!,
        descripcion: (descripcionNormalizada == null || descripcionNormalizada.isEmpty)
            ? null
            : descripcionNormalizada,
      ),
      errores: const <ErrorCampoPuesto>[],
    );
  }
}
