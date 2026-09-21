// Ajuste final de Reportes (Etapa A) — pase de pulido visual/semántico.
//
// Cubre las tres cosas que el pase corrigió y que sí se pueden verificar
// con una aserción, no con el ojo:
//
//  1. Altura adaptativa: una composición de dos categorías ya no ocupa
//     lo mismo que una serie temporal, pero los paneles de una misma
//     fila siguen alineados.
//  2. Paleta categórica: dos categorías distintas nunca comparten color,
//     y el rojo queda fuera de la rotación (es de riesgo, no de
//     categoría).
//  3. "Empleados en nómina" cuenta personas distintas del periodo, que
//     es un universo legítimamente distinto de la plantilla activa de
//     hoy — y por eso se muestran juntas en vez de forzarlas a cuadrar.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:riseg_one/app/theme/app_theme.dart';
import 'package:riseg_one/core/database/app_database.dart';
import 'package:riseg_one/core/design_system/design_system.dart';
import 'package:riseg_one/features/inventario/data/tables/articulo_unidad_table.dart';
import 'package:riseg_one/features/nomina/data/repositories/nomina_repository_impl.dart';
import 'package:riseg_one/features/nomina/data/repositories/pago_nomina_repository_impl.dart';
import 'package:riseg_one/features/descuentos_personal/data/repositories/descuento_programado_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/deuda_repository_impl.dart';
import 'package:riseg_one/features/finanzas/data/repositories/egreso_repository_impl.dart';
import 'package:riseg_one/features/inventario/data/repositories/asignacion_repository_impl.dart';
import 'package:riseg_one/features/organizacion/data/repositories/servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/asignacion_servicio_repository_impl.dart';
import 'package:riseg_one/features/personal/data/repositories/empleado_repository_impl.dart';
import 'package:riseg_one/features/reportes/domain/usecases/clasificar_egresos_por_origen_usecase.dart';
import 'package:riseg_one/features/reportes/domain/usecases/obtener_resumen_nomina_usecase.dart';
import 'package:riseg_one/features/reportes/presentation/widgets/analitica_labels.dart';
import 'package:riseg_one/features/reportes/presentation/widgets/paneles_analiticos.dart';
import 'package:riseg_one/features/tiempos_extra/data/repositories/tiempo_extra_repository_impl.dart';
import 'package:riseg_one/core/codigos/codigo_secuencia_service.dart';

void main() {
  group('Altura adaptativa de paneles', () {
    test('una composición de dos categorías pide menos alto que una de siete', () {
      final dos = RisegCompositionChart.alturaPara(2);
      final siete = RisegCompositionChart.alturaPara(7);

      expect(dos, lessThan(siete), reason: 'el alto sale del contenido, no de una constante');
      expect(dos, lessThan(alturaSerieTemporal),
          reason: 'era exactamente el defecto: media tarjeta vacía junto a una gráfica temporal');
    });

    test('nunca se encoge por debajo de lo legible ni crece sin tope', () {
      expect(RisegCompositionChart.alturaPara(0), 72);
      expect(RisegCompositionChart.alturaPara(1), greaterThanOrEqualTo(72));
      expect(RisegCompositionChart.alturaPara(60), 260, reason: 'a partir del tope la leyenda desplaza dentro de su tarjeta');
      expect(RisegAgingBars.alturaPara(0), 72);
      expect(RisegAgingBars.alturaPara(40), 260);
    });

    test('las barras de antigüedad piden más alto con detalle que sin él', () {
      expect(
        RisegAgingBars.alturaPara(3, conDetalle: true),
        greaterThan(RisegAgingBars.alturaPara(3, conDetalle: false)),
      );
    });

    test('la fila comparte la altura del panel más exigente — la alineación no se pierde', () {
      final alto = alturaDeFila([
        RisegCompositionChart.alturaPara(2),
        alturaSerieTemporal,
        RisegCompositionChart.alturaPara(5),
      ]);

      expect(alto, alturaSerieTemporal);
      expect(alturaDeFila([]), 72, reason: 'una fila sin paneles no puede devolver 0 y colapsar la tarjeta');
    });

    test('una fila de puros paneles chicos NO se estira a la altura de una gráfica', () {
      final alto = alturaDeFila([
        RisegCompositionChart.alturaPara(2),
        RisegCompositionChart.alturaPara(2),
      ]);

      expect(alto, lessThan(alturaSerieTemporal));
    });

    test('los bloques de texto miden por renglón, no por constante', () {
      expect(alturaRenglonesHecho(1), lessThan(alturaRenglonesHecho(8)));
      expect(alturaDatosCompactos(1), lessThan(alturaDatosCompactos(5)));
      expect(alturaRenglonesHecho(0), 72);
      expect(alturaDatosCompactos(0), 72);
    });
  });

  group('Paleta categórica', () {
    /// Corre [cuerpo] con un `BuildContext` cuyo tema ya está asentado.
    ///
    /// El `pumpAndSettle` NO es decorativo: `MaterialApp` envuelve el tema
    /// en un `AnimatedTheme`, así que al cambiar de claro a oscuro el
    /// primer frame todavía reporta el tema anterior. Leer la paleta en
    /// ese frame daba la paleta equivocada — lo detectó esta misma
    /// prueba.
    Future<void> conTema(WidgetTester tester, {required bool oscuro, required void Function(BuildContext) cuerpo}) async {
      late BuildContext capturado;
      await tester.pumpWidget(
        MaterialApp(
          theme: oscuro ? AppTheme.dark() : AppTheme.light(),
          home: Builder(
            builder: (context) {
              capturado = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      cuerpo(capturado);
    }

    for (final oscuro in [false, true]) {
      final tema = oscuro ? 'oscuro' : 'claro';

      testWidgets('en tema $tema ningún par de categorías comparte color', (tester) async {
        await conTema(tester, oscuro: oscuro, cuerpo: (context) {
          final paleta = context.paletaCategorica;
          expect(paleta.toSet(), hasLength(paleta.length), reason: 'colores repetidos dentro de la propia paleta');
          expect(paleta.length, greaterThanOrEqualTo(6));
        });
      });

      testWidgets('en tema $tema el rojo NO está en la rotación categórica', (tester) async {
        await conTema(tester, oscuro: oscuro, cuerpo: (context) {
          // El rojo significa riesgo/vencido/desfavorable. Usarlo como
          // "categoría 5" haría que un dato neutro se leyera como alarma.
          expect(context.paletaCategorica, isNot(contains(context.colors.error)));
        });
      });

      testWidgets('en tema $tema todos los orígenes de gasto son distinguibles entre sí', (tester) async {
        await conTema(tester, oscuro: oscuro, cuerpo: (context) {
          final colores = [for (final origen in OrigenEgreso.values) colorOrigenEgreso(context, origen)];
          expect(colores.toSet(), hasLength(OrigenEgreso.values.length),
              reason: 'antes cuatro orígenes caían en variantes del mismo azul');
        });
      });

      testWidgets('en tema $tema los ocho estados de unidad son distinguibles entre sí', (tester) async {
        await conTema(tester, oscuro: oscuro, cuerpo: (context) {
          final colores = [
            for (final estatus in EstatusArticuloUnidad.values) colorEstatusUnidad(context, estatus.name),
          ];
          expect(colores.toSet(), hasLength(EstatusArticuloUnidad.values.length),
              reason: 'antes tres estados compartían el mismo rojo y dos el mismo ámbar');
        });
      });

      testWidgets('en tema $tema "perdido" es el único estado en rojo', (tester) async {
        await conTema(tester, oscuro: oscuro, cuerpo: (context) {
          final enRojo = [
            for (final estatus in EstatusArticuloUnidad.values)
              if (colorEstatusUnidad(context, estatus.name) == context.colors.error) estatus,
          ];
          expect(enRojo, [EstatusArticuloUnidad.perdido]);
        });
      });

      testWidgets('en tema $tema dos categorías consecutivas (motivos de baja 50/50) no coinciden', (tester) async {
        await conTema(tester, oscuro: oscuro, cuerpo: (context) {
          // El caso reportado: "Renuncia" e "Inasistencias" al 50 % se
          // pintaban del mismo azul.
          expect(context.colorCategorico(0), isNot(context.colorCategorico(1)));
          expect(context.colorCategorico(1), isNot(context.colorCategorico(2)));
        });
      });

      testWidgets('en tema $tema la paleta es cíclica y nunca revienta con un índice grande', (tester) async {
        await conTema(tester, oscuro: oscuro, cuerpo: (context) {
          final paleta = context.paletaCategorica;
          expect(context.colorCategorico(paleta.length), paleta.first);
          expect(context.colorCategorico(999), isNotNull);
        });
      });
    }

    testWidgets('la paleta clara y la oscura no son la misma', (tester) async {
      late List<Color> clara;
      await conTema(tester, oscuro: false, cuerpo: (context) => clara = context.paletaCategorica);
      late List<Color> oscura;
      await conTema(tester, oscuro: true, cuerpo: (context) => oscura = context.paletaCategorica);

      expect(clara, isNot(oscura), reason: 'los mismos matices, aclarados para el lienzo oscuro');
      expect(clara, hasLength(oscura.length));
    });
  });

  group('Empleados en nómina vs plantilla activa', () {
    late AppDatabase db;
    late ObtenerResumenNominaUseCase obtenerResumen;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final egresoRepo = EgresoRepositoryImpl(db);
      final asignacionServicioRepo = AsignacionServicioRepositoryImpl(db);
      final secuencias = CodigoSecuenciaService(db);
      final descuentoRepo = DescuentoProgramadoRepositoryImpl(db, egresoRepo, secuencias);
      final nominaRepo = NominaRepositoryImpl(
        db,
        AsignacionRepositoryImpl(db),
        descuentoRepo,
        TiempoExtraRepositoryImpl(
          db,
          egresoRepo,
          DeudaRepositoryImpl(db, egresoRepo),
          secuencias,
          EmpleadoRepositoryImpl(db, asignacionServicioRepo),
          ServicioRepositoryImpl(db, asignacionServicioRepo),
        ),
        PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo),
      );
      obtenerResumen = ObtenerResumenNominaUseCase(nominaRepo, PagoNominaRepositoryImpl(db, egresoRepo, descuentoRepo));
    });

    tearDown(() => db.close());

    var consecutivo = 0;

    Future<EmpleadoData> crearEmpleado() async {
      final n = (++consecutivo).toString().padLeft(2, '0');
      return db.into(db.empleado).insertReturning(
            EmpleadoCompanion.insert(
              numeroEmpleado: consecutivo,
              nombres: 'Empleado',
              apellidoPaterno: 'De prueba $n',
              sexo: 'masculino',
              fechaNacimiento: DateTime(1990, 1, 1),
              curp: 'CUXA900101HDFXXX$n',
              rfc: 'CUXA900101A$n',
              nss: '1234567$n',
              estadoCivil: 'soltero',
              fechaIngreso: DateTime(2024, 1, 1),
              aniosExperienciaSeguridad: 3,
            ),
          );
    }

    Future<String> crearNomina({required int mes, required String tipoPeriodo, required String folio}) async {
      final nomina = await db.into(db.nomina).insertReturning(
            NominaCompanion.insert(
              folio: folio,
              anio: 2026,
              mes: mes,
              tipoPeriodo: tipoPeriodo,
              fechaInicioPeriodo: DateTime(2026, mes, tipoPeriodo == 'primeraQuincena' ? 1 : 16),
              fechaFinPeriodo: DateTime(2026, mes, tipoPeriodo == 'primeraQuincena' ? 15 : 28),
              fechaPagoOrdinaria: DateTime(2026, mes, tipoPeriodo == 'primeraQuincena' ? 15 : 28),
              estatus: const Value('cerrada'),
            ),
          );
      return nomina.id;
    }

    Future<void> agregarRenglon(String nominaId, EmpleadoData empleado) async {
      await db.into(db.nominaEmpleado).insert(
            NominaEmpleadoCompanion.insert(
              nominaId: nominaId,
              empleadoId: empleado.id,
              numeroEmpleado: empleado.numeroEmpleado,
              nombreCompleto: '${empleado.nombres} ${empleado.apellidoPaterno}',
              fuenteSueldoUtilizada: 'servicio',
              diasPagables: 15,
              sueldoMensualUtilizado: 1000000,
              sueldoQuincenalReferencia: 500000,
              pagoPorDia: 33333,
              importeBase: 500000,
              totalAPagar: 500000,
            ),
          );
    }

    test('la misma persona en dos nóminas del periodo cuenta UNA vez', () async {
      final ana = await crearEmpleado();
      final beto = await crearEmpleado();
      final carla = await crearEmpleado();

      final primera = await crearNomina(mes: 3, tipoPeriodo: 'primeraQuincena', folio: 'NOM-000001');
      final segunda = await crearNomina(mes: 3, tipoPeriodo: 'segundaQuincena', folio: 'NOM-000002');

      await agregarRenglon(primera, ana);
      await agregarRenglon(primera, beto);
      await agregarRenglon(segunda, ana); // misma persona, segunda quincena
      await agregarRenglon(segunda, carla);

      final resumen = await obtenerResumen.ejecutar(
        rangoInicio: DateTime(2026, 3, 1),
        rangoFin: DateTime(2026, 3, 31),
      );

      expect(resumen.nominas, hasLength(2));
      expect(resumen.empleadosDistintosEnPeriodo, 3,
          reason: 'son 4 renglones pero 3 personas — la cifra es de personas, no de renglones');
      expect(
        resumen.nominas.fold<int>(0, (a, n) => a + n.empleadosIncluidos),
        4,
        reason: 'el conteo por nómina sigue siendo de renglones, y eso no cambia',
      );
    });

    test('sin nóminas en el periodo la cifra es cero, no nula', () async {
      final resumen = await obtenerResumen.ejecutar(
        rangoInicio: DateTime(2026, 7, 1),
        rangoFin: DateTime(2026, 7, 31),
      );

      expect(resumen.nominas, isEmpty);
      expect(resumen.empleadosDistintosEnPeriodo, 0);
    });

    test('una persona dada de baja después del cierre sigue contando en la nómina del periodo', () async {
      final ana = await crearEmpleado();
      final nomina = await crearNomina(mes: 3, tipoPeriodo: 'primeraQuincena', folio: 'NOM-000003');
      await agregarRenglon(nomina, ana);

      // Baja posterior al periodo de la nómina: la plantilla activa de
      // hoy baja a 0, pero el renglón histórico NO se toca.
      await (db.update(db.empleado)..where((t) => t.id.equals(ana.id))).write(
        EmpleadoCompanion(
          estatus: const Value('baja'),
          fechaBaja: Value(DateTime(2026, 4, 10)),
          motivoBaja: const Value('renuncia'),
        ),
      );

      final resumen = await obtenerResumen.ejecutar(
        rangoInicio: DateTime(2026, 3, 1),
        rangoFin: DateTime(2026, 3, 31),
      );

      expect(resumen.empleadosDistintosEnPeriodo, 1,
          reason: 'la nómina es una foto congelada; recalcularla desde Personal la falsearía');
      final activos = await (db.select(db.empleado)..where((t) => t.estatus.equals('activo'))).get();
      expect(activos, isEmpty, reason: 'y la plantilla activa de hoy, correctamente, ya no la incluye');
    });
  });
}
