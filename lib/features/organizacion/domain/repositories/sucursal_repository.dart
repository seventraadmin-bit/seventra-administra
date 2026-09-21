import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/features/organizacion/data/tables/sucursal_table.dart';

import '../shared/direccion_input.dart';
import '../shared/horario_input.dart';
import '../usecases/eliminar_sucursal_fisicamente_usecase.dart';

/// Transacción que compone 3 escrituras (Sucursal + nodo raíz de
/// Ubicación + Almacén General) como una sola unidad atómica — es la
/// razón por la que este repositorio existe y no es un passthrough.
///
/// Recibe los tres códigos visibles ya generados por el llamador — este
/// repositorio no genera códigos, solo persiste (ver `CrearSucursalUseCase`,
/// que es quien "solicita códigos").
abstract interface class SucursalRepository {
  Future<SucursalData> crear({
    required String codigoSucursal,
    required String nombre,
    required String tipoSucursalId,
    required String codigoUbicacionRaiz,
    required String codigoAlmacenGeneral,
  });

  Future<SucursalData?> obtenerPorId(String id);

  Future<List<SucursalData>> listarActivas();

  /// Incluye las archivadas. Un listado de personal tiene que poder
  /// nombrar la Sucursal a la que alguien sigue adscrito aunque esa
  /// Sucursal se haya archivado después: mostrar un guion ahí parecería
  /// que la persona no tiene destino. Sólo lectura.
  Future<List<SucursalData>> listarTodas();

  /// Cambia únicamente `estadoOperativo` — una transición de negocio
  /// explícita (acción de botón con confirmación en la UI), no un campo
  /// más del formulario de edición.
  Future<SucursalData> cambiarEstadoOperativo({required String sucursalId, required EstadoOperativoSucursal nuevo});

  /// Dirección con `tipoDireccion = administrativa` u `operativa` de esta
  /// Sucursal, si existe y sigue activa. Una fila archivada equivale a
  /// "sin dirección".
  Future<DireccionData?> obtenerDireccionPrincipal(String sucursalId);

  /// Versión en lote de [obtenerDireccionPrincipal] (Etapa 16, tercera
  /// pasada visual) — una sola consulta `WHERE sucursal_id IN (...)`
  /// para resolver "municipio, estado" de todas las Sucursales del
  /// listado de una vez, nunca una consulta por tarjeta. `ids` vacío
  /// devuelve `{}` sin tocar la base de datos.
  Future<Map<String, DireccionData>> listarDireccionesPrincipales(List<String> sucursalIds);

  /// Los 7 renglones de [HorarioDetalleData] (uno por día, lunes a
  /// domingo) del `Horario` activo de esta Sucursal, o `null` si no se ha
  /// capturado ninguno todavía.
  Future<List<HorarioDetalleData>?> obtenerHorario(String sucursalId);

  /// Guarda el expediente completo (datos generales + dirección
  /// principal + horario) en una sola transacción — mismo patrón que
  /// `EmpresaRepository.guardarExpediente`: `direccionPrincipal`/`horario`
  /// en `null` significa "sección vacía" (archiva lo existente, nunca lo
  /// borra); si no existía, no crea nada.
  Future<SucursalExpedienteRaw> guardarExpediente({
    required String sucursalId,
    required SucursalCompanion datosGenerales,
    required DireccionInput? direccionPrincipal,
    required HorarioSemanalInput? horario,
  });

  /// Eliminación física extraordinaria (Etapa 11D) — ver el doc comment
  /// de la implementación para las condiciones exactas.
  Future<EliminarSucursalFisicamenteResultado> eliminarFisicamente({
    required String sucursalId,
    required String motivo,
    String? actorUsuarioId,
  });
}

/// Resultado crudo de [SucursalRepository.guardarExpediente].
class SucursalExpedienteRaw {
  const SucursalExpedienteRaw({required this.sucursal, this.direccionPrincipal, this.horario});

  final SucursalData sucursal;
  final DireccionData? direccionPrincipal;
  final List<HorarioDetalleData>? horario;
}
