// Etapa 20 (Dashboard v2) — Parte 8/16: Tiempos Extra debe mostrarse en
// el Dashboard como puramente informativo. El monto de un TiempoExtra
// YA está incluido en `Egreso` (vía `TiempoExtra.egresoId`, Etapa
// Tiempos Extra) — esta prueba confirma con BD real que
// `ObtenerResumenFinancieroUseCase.totalEgresos`/`resultadoOperativo`
// (la fuente real de "Resultado operativo" del Dashboard) lo cuenta
// EXACTAMENTE UNA VEZ, y que `ObtenerResumenTiemposExtraUseCase.
// gastoTotal` reporta ese MISMO monto como una vista informativa
// aparte — nunca una segunda suma independiente que, sumada a Egresos,
// duplicaría el gasto real.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';
import 'package:riseg_one/core/codigos/generar_codigo_usecase.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/database/seed/seed_ids.dart';
import 'package:riseg_one/features/compras/data/repositories/compra_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/ingreso_repository_impl.dart';
import 'package:riseg_one/features/finanzas/domain/usecases/obtener_resumen_financiero_usecase.dart';
import 'package:riseg_one/features/inventario/data/repositories/articulo_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/inventario_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/catalogo_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/cliente_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/crear_servicio_usecase.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/guardar_servicio_resultado.dart';
import 'package:riseg_one/features/organizacion/domain/usecases/servicio_validator.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/obtener_resumen_tiempos_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/domain/usecases/registrar_tiempo_extra_usecase.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/vacante_cobertura_reader.dart';

void main() {
  test(
    'un TiempoExtra registrado cuenta UNA sola vez en Egresos/Resultado operativo — '
    'el gastoTotal informativo de Tiempos Extra reporta el mismo monto, nunca uno adicional',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      final empleadoRepo = EmpleadoRepositoryImpl(db, asignacionServicioRepo);
      final servicioRepo = ServicioRepositoryImpl(db, asignacionServicioRepo);
      final clienteRepo = ClienteRepositoryImpl(db);
      final catalogoRepo = CatalogoRepositoryImpl(db);
      final egresoRepo = EgresoRepositoryImpl(db);
      final ingresoRepo = IngresoRepositoryImpl(db);
      final codigoSecuencia = CodigoSecuenciaService(db);

      final deudaRepo = DeudaRepositoryImpl(db, egresoRepo);
      final articuloRepo = ArticuloRepositoryImpl(db);
      final inventarioRepo = InventarioRepositoryImpl(db);
      final compraRepo = CompraRepositoryImpl(db, inventarioRepo, articuloRepo, egresoRepo, deudaRepo);
      final tiempoExtraRepo = TiempoExtraRepositoryImpl(db, egresoRepo, deudaRepo, codigoSecuencia, empleadoRepo, servicioRepo);
      final registrar = RegistrarTiempoExtraUseCase(tiempoExtraRepo, empleadoRepo, servicioRepo, deudaRepo, VacanteCoberturaReader(db));
      final resumenFinanciero = ObtenerResumenFinancieroUseCase(ingresoRepo, egresoRepo, compraRepo);
      final resumenTiemposExtra = ObtenerResumenTiemposExtraUseCase(tiempoExtraRepo, servicioRepo);

      final cliente = await clienteRepo.crear(ClienteCompanion.insert(codigo: 'CLI-000001', nombreComercial: 'Sportium'));
      final servicioCreado = await CrearServicioUseCase(
        servicioRepo,
        GenerarCodigoUseCase(codigoSecuencia),
        ServicioValidator(clienteRepo, catalogoRepo),
      ).ejecutar(
        clienteId: cliente.id,
        borrador: ServicioBorrador(nombre: 'Vigilancia Sportium', tipoServicioId: SeedIds.tipoServicioVigilanciaFija, fechaInicio: DateTime(2026, 1, 1)),
      );
      final servicioId = (servicioCreado as GuardarServicioExitoso).servicio.id;

      Future<String> crearEmpleado(int numero, String nombre) async {
        final n = numero.toString().padLeft(2, '0');
        final empleado = await db.into(db.empleado).insertReturning(
              EmpleadoCompanion.insert(
                numeroEmpleado: numero,
                nombres: nombre,
                apellidoPaterno: 'Apellido$n',
                sexo: 'masculino',
                fechaNacimiento: DateTime(1990, 1, 1),
                curp: 'PEXJ900101HDFXXX$n',
                rfc: 'PEXJ900101$n',
                nss: '100000000$n',
                estadoCivil: 'soltero',
                fechaIngreso: DateTime(2025, 1, 1),
                aniosExperienciaSeguridad: 3,
              ),
            );
        return empleado.id;
      }

      final empleadoAusenteId = await crearEmpleado(1, 'Monica');
      final empleadoCubreId = await crearEmpleado(2, 'Juan');

      // Antes de registrar: Egresos en 0, sin datos de Tiempos Extra.
      final antes = await resumenFinanciero.ejecutar();
      expect(antes.totalEgresos, 0);

      final resultado = await registrar.ejecutar(
        fecha: DateTime(2026, 9, 3),
        servicioId: servicioId,
        origenCobertura: OrigenCoberturaTiempoExtra.ausenciaEmpleado.name,
        empleadoAusenteId: empleadoAusenteId,
        motivoAusencia: MotivoAusenciaTiempoExtra.faltaInjustificada.name,
        empleadoCubreId: empleadoCubreId,
        turnoId: SeedIds.modalidadTurno24x24,
        montoTiempoExtra: 50000,
        formaPago: 'efectivo',
      );
      expect(resultado, isA<RegistrarTiempoExtraExitoso>());

      final despues = await resumenFinanciero.ejecutar();
      final tiemposExtra = await resumenTiemposExtra.ejecutar();

      // El Egreso automático sube Egresos/baja el Resultado operativo
      // EXACTAMENTE en $500.00 (50000 centavos) — nunca el doble.
      expect(despues.totalEgresos, 50000, reason: 'el TiempoExtra debe contarse en Egresos exactamente una vez');
      expect(despues.resultadoOperativo, -50000);

      // El bloque informativo de Tiempos Extra reporta el MISMO monto —
      // es una vista distinta del mismo dato, nunca un monto adicional.
      expect(tiemposExtra.gastoTotal, 50000);
      expect(
        tiemposExtra.gastoTotal,
        despues.totalEgresos,
        reason: 'gastoTotal de Tiempos Extra y totalEgresos deben coincidir — es el mismo Egreso, visto dos veces, nunca sumado dos veces',
      );
    },
  );
}
