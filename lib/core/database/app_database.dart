import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../../features/organizacion/data/tables/cliente_attachment_table.dart';
import '../../features/organizacion/data/tables/cliente_table.dart';
import '../../features/organizacion/data/tables/configuracion_cobro_correo_table.dart';
import '../../features/organizacion/data/tables/configuracion_cobro_regla_evento_table.dart';
import '../../features/organizacion/data/tables/configuracion_cobro_table.dart';
import '../../features/organizacion/data/tables/configuracion_cobro_vigencia_table.dart';
import '../../features/organizacion/data/tables/contacto_table.dart';
import '../../features/organizacion/data/tables/documento_por_emitir_attachment_table.dart';
import '../../features/organizacion/data/tables/documento_por_emitir_table.dart';
import '../../features/organizacion/data/tables/empresa_attachment_table.dart';
import '../../features/organizacion/data/tables/empresa_table.dart';
import '../../features/organizacion/data/tables/entidad_fiscal_table.dart';
import '../../features/organizacion/data/tables/puesto_table.dart';
import '../../features/organizacion/data/tables/servicio_linea_comercial_table.dart';
import '../../features/organizacion/data/tables/servicio_linea_comercial_vigencia_table.dart';
import '../../features/organizacion/data/tables/servicio_table.dart';
import '../../features/organizacion/data/tables/sucursal_table.dart';
import '../../features/organizacion/data/tables/ubicacion_table.dart';
import '../../features/finanzas/data/tables/categoria_financiera_table.dart';
import '../../features/finanzas/data/tables/complemento_pago_attachment_table.dart';
import '../../features/finanzas/data/tables/complemento_pago_table.dart';
import '../../features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import '../../features/finanzas/data/tables/egreso_attachment_table.dart';
import '../../features/finanzas/data/tables/egreso_table.dart';
import '../../features/finanzas/data/tables/ingreso_attachment_table.dart';
import '../../features/finanzas/data/tables/ingreso_table.dart';
import '../../features/finanzas/data/tables/pago_attachment_table.dart';
import '../../features/finanzas/data/tables/pago_table.dart';
import '../../features/personal/data/tables/asignacion_servicio_sueldo_vigencia_table.dart';
import '../../features/personal/data/tables/asignacion_servicio_table.dart';
import '../../features/personal/data/tables/empleado_attachment_table.dart';
import '../../features/personal/data/tables/empleado_table.dart';
import '../../features/personal/data/tables/ficha_tecnica_empleado_table.dart';
import '../../features/nomina/data/tables/nomina_empleado_table.dart';
import '../../features/nomina/data/tables/nomina_empleado_tramo_table.dart';
import '../../features/nomina/data/tables/nomina_evento_table.dart';
import '../../features/nomina/data/tables/nomina_table.dart';
import '../../features/nomina/data/tables/pago_nomina_attachment_table.dart';
import '../../features/nomina/data/tables/pago_nomina_table.dart';
import '../../features/inventario/data/tables/articulo_table.dart';
import '../../features/inventario/data/tables/articulo_unidad_table.dart';
import '../../features/inventario/data/tables/articulo_unidad_telefono_table.dart';
import '../../features/inventario/data/tables/articulo_variante_table.dart';
import '../../features/inventario/data/tables/asignacion_attachment_table.dart';
import '../../features/inventario/data/tables/asignacion_table.dart';
import '../../features/inventario/data/tables/categoria_articulo_table.dart';
import '../../features/inventario/data/tables/descuento_inventario_table.dart';
import '../../features/inventario/data/tables/movimiento_inventario_attachment_table.dart';
import '../../features/inventario/data/tables/movimiento_inventario_table.dart';
import '../../features/vehiculos/data/tables/asignacion_vehiculo_table.dart';
import '../../features/vehiculos/data/tables/vehiculo_documento_table.dart';
import '../../features/vehiculos/data/tables/vehiculo_kilometraje_table.dart';
import '../../features/vehiculos/data/tables/vehiculo_table.dart';
import 'migrations/migrar_asignacion_attachment_v29.dart';
import 'migrations/migrar_asignacion_vehiculo_v31.dart';
import 'migrations/migrar_vehiculo_v30.dart';
import 'migrations/migrar_asignacion_servicio_v21.dart';
import 'migrations/migrar_asignacion_v28.dart';
import 'migrations/migrar_cliente_contacto_v4.dart';
import 'migrations/migrar_empleado_v21.dart';
import 'migrations/migrar_empleado_v23.dart';
import 'migrations/migrar_ficha_tecnica_empleado_v22.dart';
import 'migrations/migrar_servicio_v24.dart';
import 'migrations/migrar_codigos_area_v3.dart';
import 'migrations/migrar_direccion_v5.dart';
import 'migrations/migrar_attachment_v13.dart';
import 'migrations/migrar_attachment_v15.dart';
import 'migrations/migrar_attachment_v16.dart';
import 'migrations/migrar_attachment_v17.dart';
import 'migrations/migrar_attachment_v18.dart';
import 'migrations/migrar_cuenta_por_cobrar_v14.dart';
import 'migrations/migrar_direccion_v18.dart';
import 'migrations/migrar_empleado_v19.dart';
import 'migrations/migrar_empleado_v20.dart';
import 'migrations/migrar_documento_por_emitir_v12.dart';
import 'migrations/migrar_servicio_v6.dart';
import 'migrations/migrar_servicio_v7.dart';
import 'seed/seed_data.dart';
import 'tables/attachment_table.dart';
import 'tables/catalogos_tables.dart';
import 'tables/codigo_secuencia_table.dart';
import 'tables/direccion_table.dart';
import 'tables/horario_table.dart';
import 'tables/medio_contacto_table.dart';

part 'app_database.g.dart';

/// Tabla mínima usada únicamente para comprobar que Drift funciona de
/// extremo a extremo en esta etapa. No es una tabla de negocio.
///
/// `schemaVersion` NO se guarda aquí: Drift ya lo gestiona internamente
/// mediante [AppDatabase.schemaVersion] y su tabla interna de versiones.
class AppMetadata extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get installationId => text()();

  DateTimeColumn get installedAt => dateTime()();

  DateTimeColumn get lastOpenedAt => dateTime()();

  TextColumn get appVersion => text()();
}

@DriftDatabase(tables: [
  AppMetadata,
  CodigoSecuencia,
  TipoSucursal,
  Industria,
  TipoServicio,
  Area,
  TipoModalidadTurno,
  TipoFrecuenciaCobro,
  Banco,
  Direccion,
  MedioContacto,
  Attachment,
  Horario,
  HorarioDetalle,
  Empresa,
  Sucursal,
  Ubicacion,
  Puesto,
  Cliente,
  Contacto,
  Servicio,
  EntidadFiscal,
  ServicioLineaComercial,
  ServicioLineaComercialVigencia,
  ConfiguracionCobro,
  ConfiguracionCobroVigencia,
  ConfiguracionCobroCorreo,
  ConfiguracionCobroReglaEvento,
  DocumentoPorEmitir,
  DocumentoPorEmitirServicio,
  DocumentoPorEmitirConfiguracion,
  DocumentoPorEmitirLinea,
  DocumentoPorEmitirCorreo,
  DocumentoPorEmitirCorreoEnvio,
  DocumentoPorEmitirEvento,
  CuentaPorCobrar,
  CuentaPorCobrarEvento,
  Pago,
  AplicacionPago,
  PagoEvento,
  ComplementoPago,
  ComplementoPagoEvento,
  CategoriaFinanciera,
  Ingreso,
  IngresoEvento,
  Egreso,
  EgresoEvento,
  Empleado,
  EmpleadoEvento,
  EmpleadoPeriodoLaboral,
  AsignacionServicio,
  AsignacionServicioSueldoVigencia,
  FichaTecnicaEmpleado,
  EmpresaAttachment,
  ClienteAttachment,
  DocumentoPorEmitirAttachment,
  PagoAttachment,
  ComplementoPagoAttachment,
  IngresoAttachment,
  EgresoAttachment,
  EmpleadoAttachment,
  Nomina,
  NominaEmpleado,
  NominaEmpleadoTramo,
  NominaEvento,
  PagoNomina,
  AplicacionPagoNomina,
  PagoNominaEvento,
  PagoNominaAttachment,
  CategoriaArticulo,
  Articulo,
  ArticuloVariante,
  ArticuloUnidad,
  ArticuloUnidadTelefono,
  MovimientoInventario,
  MovimientoInventarioAttachment,
  Asignacion,
  DescuentoInventario,
  AsignacionAttachment,
  Vehiculo,
  VehiculoAttachment,
  AsignacionVehiculo,
  VehiculoKilometraje,
  VehiculoDocumento,
  VehiculoDocumentoAttachment,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 32;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await runSeed(this);
        await seedTipoModalidadTurno(this);
        await seedTipoFrecuenciaCobro(this);
        await seedBanco(this);
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from == 1) {
          // Crea todas las tablas de la Etapa 4A directo con la forma
          // *actual* de sus clases Dart (incluyendo Cliente/Contacto ya
          // en su forma de la Etapa 4E.1, y Direccion ya con
          // `entidadFiscalId` de la Etapa 4E.2) — nunca necesita pasar
          // también por `migrarClienteContactoV4`/`migrarDireccionV5`
          // más abajo.
          await _createEtapa4ATables(m);
        }
        // Aditiva (Etapa 4G.1): catálogo TipoModalidadTurno + tablas
        // ServicioLineaComercial/ServicioLineaComercialVigencia — 3
        // tablas completamente nuevas, ninguna existió en ninguna etapa
        // previa, así que `from <= 7` (sin necesidad de acotar un
        // origen exacto) es seguro: ningún otro paso de este `onUpgrade`
        // pudo haberlas creado ya.
        //
        // `seedTipoModalidadTurno` se llama aquí mismo, no dentro de
        // `runSeed()`: `runSeed()` corre sin condiciones para cualquier
        // `to`, incluidas las pruebas de migración que apuntan a
        // versiones nominales históricas (5, 6, 7) — su snapshot físico
        // nunca tuvo esta tabla, así que sembrarla desde `runSeed()`
        // rompería esas pruebas con "no such table" en cuanto `to` deja
        // de ser 8 (recordatorio: `to` refleja el objetivo nominal real
        // pasado a `SchemaVerifier.migrateAndValidate`, no siempre el
        // `schemaVersion` de hoy).
        if (to >= 8 && from <= 7) {
          await m.createTable(tipoModalidadTurno);
          await m.createTable(servicioLineaComercial);
          await m.createTable(servicioLineaComercialVigencia);
          await seedTipoModalidadTurno(this);
        }
        await runSeed(this);
        // Puramente de datos (sin cambio de tabla): unifica el formato de
        // código de Área. Corre en cualquier instalación que vaya a
        // schemaVersion 3 viniendo de 1 o 2 — nunca en una instalación
        // nueva (`onCreate`), que ya siembra directo con el formato
        // definitivo (ver `_seedArea`).
        if (from <= 2) {
          await migrarCodigosAreaV3(this);
        }
        // Estructural (Etapa 4E.1): retira razonSocial/rfc de Cliente y
        // agrega Contacto.tipo. Solo aplica a instalaciones que ya tenían
        // Cliente/Contacto físicamente creados con la forma anterior
        // (schemaVersion 2 o 3) — una instalación que viene de 1 ya los
        // creó con la forma nueva unas líneas arriba, en este mismo
        // `onUpgrade`.
        if (from == 2 || from == 3) {
          await migrarClienteContactoV4(this, m);
        }
        // Estructural (Etapa 4E.2): EntidadFiscal es tabla nueva, sin
        // relación con la Etapa 4A — se crea para cualquier instalación
        // que todavía no la tenga, sin importar si viene de 1 (que ya
        // creó todo lo demás arriba) o de una versión posterior.
        //
        // Gateada también por `to >= 5`, no solo por `from`: igual que
        // en la Etapa 4E.1 (ver `migrarClienteContactoV4`), una prueba
        // de `SchemaVerifier.migrateAndValidate(db, 4)` sustituye el
        // *objetivo* nominal vía un delegado interno, pero el cuerpo de
        // este `onUpgrade` sigue ejecutándose completo — sin este
        // chequeo, un `from <= 4` se dispararía igual aunque el
        // objetivo real fuera 4, no 5, rompiendo las pruebas de
        // migración que validan explícitamente ese esquema intermedio.
        if (to >= 5 && from <= 4) {
          await m.createTable(entidadFiscal);
        }
        // Recrea Direccion con la quinta pata del arco exclusivo
        // (entidadFiscalId) — requiere que `entidad_fiscal` ya exista
        // (su FK la referencia), por eso corre después del paso
        // anterior. Solo aplica a instalaciones que ya tenían Direccion
        // físicamente creada con la forma anterior (2, 3 o 4) — de 1 ya
        // se creó con la forma nueva arriba. Mismo motivo de `to >= 5`
        // que el paso anterior.
        if (to >= 5 && from >= 2 && from <= 4) {
          await migrarDireccionV5(this, m);
        }
        // Estructural (Etapa 4F.1): vuelve sucursalAdministrativaId
        // nullable en Servicio — requiere recrear la tabla. Solo aplica
        // a instalaciones que ya tenían Servicio físicamente creado con
        // la forma anterior (2, 3, 4 o 5) — de 1 ya se creó con la forma
        // nueva arriba. Mismo motivo de `to >=` que los pasos previos.
        if (to >= 6 && from >= 2 && from <= 5) {
          await migrarServicioV6(this, m);
        }
        // Aditiva (Etapa 4F.2): 4 columnas nuevas nullable en Servicio
        // (entidadFiscalId, responsableInterno, referenciaComercial,
        // referenciaContractual) — sin recreación de tabla.
        //
        // Solo `from == 6`, NUNCA `from <= 6`: `migrarServicioV6` (arriba)
        // recrea la tabla completa vía `m.createTable(servicio)`, que
        // siempre lee la forma *actual* de la clase Dart — hoy esa forma
        // YA incluye las 4 columnas de esta migración. Por eso, para
        // cualquier `from` entre 2 y 5 (que dispara `migrarServicioV6` en
        // este mismo `onUpgrade`), la tabla recreada ya sale con estas 4
        // columnas — volver a agregarlas aquí lanzaría "duplicate column
        // name". Solo una instalación que ya estaba exactamente en
        // schemaVersion 6 (nunca pasó por `migrarServicioV6` en esta
        // corrida) todavía tiene la forma vieja y necesita este paso.
        // Mismo tipo de error de fondo que ya mordió antes con
        // `_createEtapa4ATables`/`_currentSchemaVersion` — cualquier
        // migración futura que agregue una columna a Servicio debe
        // revisar si algún paso anterior ya la recrea por completo.
        if (to >= 7 && from == 6) {
          await migrarServicioV7(this, m);
        }
        // Aditiva (Etapa 4H.1): catálogo TipoFrecuenciaCobro + tablas
        // ConfiguracionCobro/ConfiguracionCobroVigencia/
        // ConfiguracionCobroCorreo — 4 tablas completamente nuevas,
        // mismo motivo que el paso `to >= 8` de arriba (Etapa 4G.1):
        // ninguna existió antes, así que `from <= 8` es seguro sin
        // acotar un origen exacto. `seedTipoFrecuenciaCobro` se llama
        // aquí, no dentro de `runSeed()`, por la misma razón que
        // `seedTipoModalidadTurno`.
        if (to >= 9 && from <= 8) {
          await m.createTable(tipoFrecuenciaCobro);
          await m.createTable(configuracionCobro);
          await m.createTable(configuracionCobroVigencia);
          await m.createTable(configuracionCobroCorreo);
          await seedTipoFrecuenciaCobro(this);
        }
        // Aditiva (Etapa 4H.2): ConfiguracionCobroReglaEvento — tabla
        // completamente nueva, mismo motivo que los pasos `to >= 8`/
        // `to >= 9` de arriba: nunca existió antes, `from <= 9` es
        // seguro sin acotar un origen exacto. Sin siembra (no es un
        // catálogo).
        if (to >= 10 && from <= 9) {
          await m.createTable(configuracionCobroReglaEvento);
        }
        // Aditiva (Etapa 4I.1): DocumentoPorEmitir y sus 4 tablas hijas
        // (Servicio/Configuracion/Linea/Correo) — todas completamente
        // nuevas, mismo motivo que los pasos anteriores: `from <= 10` es
        // seguro sin acotar un origen exacto. El renglón nuevo de
        // `CodigoSecuencia('documento_por_emitir')` se siembra vía
        // `runSeed()` normal (a diferencia de los catálogos de 4G.1/
        // 4H.1): `codigo_secuencia` ya existe desde schemaVersion 1 en
        // todo snapshot histórico, así que no hay riesgo de "no such
        // table" al llamar `runSeed()` sin condiciones.
        if (to >= 11 && from <= 10) {
          await m.createTable(documentoPorEmitir);
          await m.createTable(documentoPorEmitirServicio);
          await m.createTable(documentoPorEmitirConfiguracion);
          await m.createTable(documentoPorEmitirLinea);
          await m.createTable(documentoPorEmitirCorreo);
        }
        // Aditiva+estructural (Etapa 4I.2.1): datos definitivos del
        // documento directamente en `DocumentoPorEmitir` (Corrección
        // explícita de Marlon: nunca una entidad 1:1 separada) + 2
        // tablas nuevas (`DocumentoPorEmitirCorreoEnvio`,
        // `DocumentoPorEmitirEvento`). `migrarDocumentoPorEmitirV12`
        // recrea la tabla completa (SQLite no permite agregar un CHECK
        // de tabla vía `ADD COLUMN`) — ver ese archivo para el detalle.
        //
        // SOLO corre si `from == 11` exacto — NUNCA `from <= 11` (mismo
        // gotcha ya documentado en `migrarServicioV7`, arriba): un
        // origen `from <= 10` ya pasó por el paso `to >= 11` de arriba,
        // que crea `documentoPorEmitir` vía `m.createTable` con la forma
        // *actual* de la clase Dart — que ya incluye estas 9 columnas y
        // su CHECK. Recrearla otra vez ahí lanzaría "table already
        // exists". Las 2 tablas nuevas sí son seguras con `from <= 11`
        // (nunca existieron antes de esta etapa, sin importar el
        // origen).
        if (to >= 12 && from == 11) {
          await migrarDocumentoPorEmitirV12(this, m);
        }
        if (to >= 12 && from <= 11) {
          await m.createTable(documentoPorEmitirCorreoEnvio);
          await m.createTable(documentoPorEmitirEvento);
        }
        // Estructural (Etapa 4I.2.2): Attachment gana el tercer brazo
        // del arco exclusivo (`documentoPorEmitirId`) + `categoria` +
        // `estado` — mismo motivo de recreación que
        // `migrarDocumentoPorEmitirV12` (el CHECK no se puede ampliar
        // vía `ADD COLUMN`). Mismo gotcha de siempre: `from == 1` ya
        // crea `attachment` con la forma *actual* en
        // `_createEtapa4ATables` (arriba en este mismo `onUpgrade`), así
        // que aquí es `from >= 2`, nunca sin acotar.
        if (to >= 13 && from >= 2 && from <= 12) {
          await migrarAttachmentV13(this, m);
        }
        // Aditiva (Etapa 4J.1): `CuentaPorCobrar`/`CuentaPorCobrarEvento`
        // — 2 tablas completamente nuevas, `from <= 13` es seguro sin
        // acotar un origen exacto (nunca existieron antes de esta
        // etapa). El backfill (Resolución F de Marlon) corre después de
        // crear las tablas, en su propia transacción — genera una
        // Cuenta por cobrar para cualquier `DocumentoPorEmitir` que ya
        // esté en `procesadoAceptado` sin una.
        if (to >= 14 && from <= 13) {
          await m.createTable(cuentaPorCobrar);
          await m.createTable(cuentaPorCobrarEvento);
          await migrarCuentaPorCobrarV14(this);
        }
        // Aditiva (Etapa 4J.2): `Pago`/`AplicacionPago`/`PagoEvento` —
        // 3 tablas completamente nuevas, `from <= 14` es seguro sin
        // acotar un origen exacto. Se crean *antes* de
        // `migrarAttachmentV15` a propósito: `Attachment` gana una FK
        // hacia `pago` en ese paso, y `PRAGMA foreign_key_check` (que
        // esa migración corre al final) necesita que la tabla destino
        // ya exista.
        if (to >= 15 && from <= 14) {
          await m.createTable(pago);
          await m.createTable(aplicacionPago);
          await m.createTable(pagoEvento);
        }
        // Estructural (Etapa 4J.2): Attachment gana el cuarto brazo del
        // arco exclusivo (`pagoId`, comprobante de pago) — mismo motivo
        // de recreación que `migrarAttachmentV13` (el CHECK no se puede
        // ampliar vía `ADD COLUMN`). Mismo gotcha de siempre: `from ==
        // 1` ya crea `attachment` con la forma *actual* en
        // `_createEtapa4ATables` (arriba en este mismo `onUpgrade`), así
        // que aquí es `from >= 2`, nunca sin acotar.
        if (to >= 15 && from >= 2 && from <= 14) {
          await migrarAttachmentV15(this, m);
        }
        // Aditiva (Etapa 4J.3): `ComplementoPago`/`ComplementoPagoEvento`
        // — 2 tablas completamente nuevas, `from <= 15` es seguro sin
        // acotar un origen exacto. Se crean *antes* de
        // `migrarAttachmentV16` por el mismo motivo que `pago` antes de
        // `migrarAttachmentV15`: esa migración agrega una FK hacia
        // `complemento_pago` y corre `PRAGMA foreign_key_check` al final.
        if (to >= 16 && from <= 15) {
          await m.createTable(complementoPago);
          await m.createTable(complementoPagoEvento);
        }
        // Estructural (Etapa 4J.3): Attachment gana el quinto brazo del
        // arco exclusivo (`complementoPagoId`, PDF/XML del Complemento
        // de pago) — mismo motivo de recreación que
        // `migrarAttachmentV13`/`migrarAttachmentV15`. Mismo gotcha de
        // siempre: `from == 1` ya crea `attachment` con la forma
        // *actual* en `_createEtapa4ATables` (arriba en este mismo
        // `onUpgrade`), así que aquí es `from >= 2`, nunca sin acotar.
        if (to >= 16 && from >= 2 && from <= 15) {
          await migrarAttachmentV16(this, m);
        }
        // Aditiva (Etapa 4K.1): `CategoriaFinanciera`/`Ingreso`/
        // `IngresoEvento`/`Egreso`/`EgresoEvento` — 5 tablas
        // completamente nuevas, `from <= 16` es seguro sin acotar un
        // origen exacto. Se crean *antes* de `migrarAttachmentV17` por
        // el mismo motivo que en 4J.2/4J.3: esa migración agrega FKs
        // hacia `ingreso`/`egreso` y corre `PRAGMA foreign_key_check`
        // al final.
        if (to >= 17 && from <= 16) {
          await m.createTable(categoriaFinanciera);
          await m.createTable(ingreso);
          await m.createTable(ingresoEvento);
          await m.createTable(egreso);
          await m.createTable(egresoEvento);
        }
        // Estructural (Etapa 4K.1): Attachment gana el sexto y séptimo
        // brazo del arco exclusivo (`ingresoId`/`egresoId`) — mismo
        // motivo de recreación que las tres veces anteriores. Mismo
        // gotcha de siempre: `from == 1` ya crea `attachment` con la
        // forma *actual* en `_createEtapa4ATables` (arriba en este
        // mismo `onUpgrade`), así que aquí es `from >= 2`, nunca sin
        // acotar.
        if (to >= 17 && from >= 2 && from <= 16) {
          await migrarAttachmentV17(this, m);
        }
        // Aditiva (Etapa 5A): `Empleado`/`EmpleadoEvento` — el
        // expediente del empleado, tablas raíz completamente nuevas,
        // `from <= 17` es seguro sin acotar un origen exacto. Se crean
        // *antes* de `migrarDireccionV18` (agrega una FK hacia
        // `empleado`) y de crear las tablas puente de Attachment (una
        // de ellas, `EmpleadoAttachment`, también la referencia).
        if (to >= 18 && from <= 17) {
          await m.createTable(empleado);
          await m.createTable(empleadoEvento);
        }
        // Estructural (Etapa 5A): Direccion gana la sexta pata del arco
        // exclusivo (`empleadoId`, domicilio del Empleado) — mismo
        // motivo de recreación que `migrarDireccionV5` (el CHECK no se
        // puede ampliar vía `ADD COLUMN`). Mismo gotcha de siempre:
        // `from == 1` ya crea `direccion` con la forma *actual* en
        // `_createEtapa4ATables`, así que aquí es `from >= 2`, nunca
        // sin acotar.
        if (to >= 18 && from >= 2 && from <= 17) {
          await migrarDireccionV18(this, m);
        }
        // Aditiva (Etapa 5A): las 8 tablas puente de Attachment — 7
        // para los dueños que antes vivían como columna directa
        // (Empresa/Cliente/DocumentoPorEmitir/Pago/ComplementoPago/
        // Ingreso/Egreso) + `EmpleadoAttachment`, nueva. Todas
        // completamente nuevas, `from <= 17` es seguro sin acotar un
        // origen exacto. Se crean *antes* de `migrarAttachmentV18`
        // (hace el backfill hacia ellas y corre `PRAGMA
        // foreign_key_check` al final) — mismo motivo que cada
        // extensión anterior del arco.
        if (to >= 18 && from <= 17) {
          await m.createTable(empresaAttachment);
          await m.createTable(clienteAttachment);
          await m.createTable(documentoPorEmitirAttachment);
          await m.createTable(pagoAttachment);
          await m.createTable(complementoPagoAttachment);
          await m.createTable(ingresoAttachment);
          await m.createTable(egresoAttachment);
          await m.createTable(empleadoAttachment);
        }
        // Estructural (Etapa 5A): Attachment deja de tener columnas de
        // dueño — cada uno migra a su tabla puente (ver el doc comment
        // de esa tabla y de `migrarAttachmentV18`). Mismo gotcha de
        // siempre: `from == 1` ya crea `attachment` angosta en
        // `_createEtapa4ATables`, así que aquí es `from >= 2`, nunca
        // sin acotar.
        if (to >= 18 && from >= 2 && from <= 17) {
          await migrarAttachmentV18(this, m);
        }
        // Aditiva (Etapa 5B): 13 columnas nullable de Perfil
        // psicológico/Estudio socioeconómico/Antidoping en `Empleado`
        // — sin `CHECK`/`UNIQUE`, así que `ALTER TABLE ADD COLUMN`
        // basta, sin recrear la tabla. Mismo gotcha exacto de siempre,
        // pero en su variante estricta: `from == 18`, **nunca** `from
        // <= 18` — cualquier origen `from <= 17` ya crea `empleado` vía
        // `m.createTable(empleado)` (bloque `to >= 18` arriba), que
        // para cuando existe este bloque ya lee la forma *actual* de
        // la clase Dart, la cual YA incluye estas 13 columnas. Ver el
        // doc comment de `migrarEmpleadoV19` para el detalle completo.
        if (to >= 19 && from == 18) {
          await migrarEmpleadoV19(this, m);
        }
        // Aditiva (Etapa 5C): tabla nueva `EmpleadoPeriodoLaboral`
        // (historial de periodos cerrados, nunca contiene el periodo
        // vigente — ver su doc comment) + 3 columnas nullable de baja
        // del periodo laboral vigente en `Empleado`. La tabla se crea
        // para cualquier `from <= 19` (nunca existió antes, sin
        // gotcha). Las columnas de `Empleado` sí llevan el gotcha en su
        // variante de rango (`from == 18 || from == 19`, nunca `from <=
        // 17`) — ver el doc comment de `migrarEmpleadoV20` para el
        // detalle completo.
        if (to >= 20 && from <= 19) {
          await migrarEmpleadoV20(this, m, from);
        }
        // Aditiva (Etapa 5D): tabla nueva `AsignacionServicio` (relación
        // Personal↔Servicio) + su índice único parcial. Tabla enteramente
        // nueva — segura para cualquier `from <= 20`, sin gotcha.
        if (to >= 21 && from <= 20) {
          await migrarAsignacionServicioV21(this, m);
        }
        // Aditiva (Etapa 5D): `codigoPostalFiscal` en `Empleado`. Gotcha
        // de rango extendido a 3 valores — ver el doc comment de
        // `migrarEmpleadoV21` para el detalle completo.
        if (to >= 21 && from <= 20) {
          await migrarEmpleadoV21(this, m, from);
        }
        // Aditiva (Etapa 5E): tabla nueva `FichaTecnicaEmpleado`
        // (historial append-only de fichas técnicas generadas). Tabla
        // enteramente nueva — segura para cualquier `from <= 21`, sin
        // gotcha. El renglón nuevo de `CodigoSecuencia('ficha_tecnica')`
        // se siembra vía `runSeed()` normal, arriba en este mismo
        // `onUpgrade`.
        if (to >= 22 && from <= 21) {
          await migrarFichaTecnicaEmpleadoV22(this, m);
        }
        // Aditiva (Etapa 6A): catálogo Banco — tabla completamente
        // nueva, `from <= 22` es seguro sin acotar un origen exacto.
        // Corre antes de `migrarEmpleadoV23` porque `Empleado.bancoId`
        // la referencia.
        if (to >= 23 && from <= 22) {
          await m.createTable(banco);
          await seedBanco(this);
        }
        // Estructural (Etapa 6A): `numeroEmpleado` reemplaza
        // `codigoEmpleado` + datos bancarios + condición laboral
        // administrativa. Gotcha de rango exacto de siempre: `from ==
        // 18` a `from == 22` — un origen `from <= 17` ya crea
        // `empleado` con la forma *actual* en el bloque `to >= 18` de
        // arriba, que para cuando se ejecuta ya incluye estas columnas.
        if (to >= 23 && from >= 18 && from <= 22) {
          await migrarEmpleadoV23(this, m);
        }
        // Aditiva (Etapa 6B): tabla nueva `AsignacionServicioSueldoVigencia`
        // (historial de sueldo/bono por asignación) — tabla enteramente
        // nueva, segura para cualquier `from <= 23`, sin gotcha. Requiere
        // que `asignacion_servicio` ya exista (su FK la referencia) — el
        // paso que la crea (`migrarAsignacionServicioV21`, arriba) siempre
        // corre antes en esta misma cadena secuencial de `onUpgrade`.
        if (to >= 24 && from <= 23) {
          await m.createTable(asignacionServicioSueldoVigencia);
        }
        // Estructural (Etapa 6B): agrega `sueldoMensualReferenciaPersonal`/
        // `bonoMensualReferenciaPersonal` a `Servicio` — requiere recrear
        // la tabla porque ambas llevan `CHECK` (ver el doc comment de
        // `migrarServicioV24`: `ALTER TABLE ... ADD COLUMN` no agrega
        // restricciones de tabla).
        //
        // Gotcha de rango, mismo criterio que `migrarServicioV6`/
        // `migrarServicioV7`: `from == 1` y `from` 2 a 5 ya obtienen la
        // forma *actual* (incluye estas 2 columnas) vía
        // `_createEtapa4ATables`/`migrarServicioV6` (ambos usan
        // `m.createTable(servicio)`, que siempre lee la clase Dart de
        // hoy) — solo `from` 6 a 23 tiene la forma física anterior y
        // necesita este paso.
        if (to >= 24 && from >= 6 && from <= 23) {
          await migrarServicioV24(this, m);
        }
        // Aditiva (Etapa 6C): tablas nuevas del motor de Nómina
        // (Nomina/NominaEmpleado/NominaEmpleadoTramo/NominaEvento) —
        // ninguna existió antes, `from <= 24` es seguro sin acotar un
        // origen exacto. El renglón nuevo de `CodigoSecuencia('nomina')`
        // se siembra vía `runSeed()` normal, arriba en este mismo
        // `onUpgrade`.
        if (to >= 25 && from <= 24) {
          await m.createTable(nomina);
          await m.createTable(nominaEmpleado);
          await m.createTable(nominaEmpleadoTramo);
          await m.createTable(nominaEvento);
        }
        // Aditiva (Etapa 6D): tablas nuevas de pagos de Nómina
        // (PagoNomina/AplicacionPagoNomina/PagoNominaEvento/
        // PagoNominaAttachment) — ninguna existió antes, `from <= 25`
        // es seguro sin acotar un origen exacto. `PagoNomina.egresoId`
        // referencia a `Egreso` (tabla ya existente) sin tocar su
        // esquema — la FK nace en la tabla nueva a propósito, porque un
        // `UNIQUE` agregado por `ALTER TABLE ... ADD COLUMN` no es
        // soportado por SQLite. El renglón nuevo de
        // `CodigoSecuencia('pago_nomina')` se siembra vía `runSeed()`
        // normal, arriba en este mismo `onUpgrade`.
        if (to >= 26 && from <= 25) {
          await m.createTable(pagoNomina);
          await m.createTable(aplicacionPagoNomina);
          await m.createTable(pagoNominaEvento);
          await m.createTable(pagoNominaAttachment);
        }
        // Aditiva (Etapa 7A): catálogo y existencias de Inventario —
        // ninguna tabla existió antes, `from <= 26` es seguro sin
        // acotar un origen exacto. Los renglones nuevos de
        // `CodigoSecuencia('articulo')`/`CodigoSecuencia('articulo_unidad')`
        // se siembran vía `runSeed()` normal, arriba en este mismo
        // `onUpgrade`.
        if (to >= 27 && from <= 26) {
          await m.createTable(categoriaArticulo);
          await m.createTable(articulo);
          await m.createTable(articuloVariante);
          await m.createTable(articuloUnidad);
          await m.createTable(articuloUnidadTelefono);
          await m.createTable(movimientoInventario);
          await m.createTable(movimientoInventarioAttachment);
        }
        // Aditiva (Etapa 7B): `Asignacion` (relación Inventario↔
        // Empleado/Servicio) + su índice único parcial —
        // `migrarAsignacionV28` corre en su propia transacción con
        // verificación de FK/integridad (mismo criterio que
        // `migrarAsignacionServicioV21`, Etapa 5D). `DescuentoInventario`/
        // `AsignacionAttachment` son puramente aditivas, sin índice
        // propio, y requieren que `asignacion` ya exista (ambas la
        // referencian) — por eso corren después.
        if (to >= 28 && from <= 27) {
          await migrarAsignacionV28(this, m);
          await m.createTable(descuentoInventario);
          await m.createTable(asignacionAttachment);
        }
        // Estructural (Etapa 7C): `AsignacionAttachment` gana llave
        // primaria compuesta — ver el doc comment de
        // `migrarAsignacionAttachmentV29`. Gotcha de rango exacto de
        // siempre: `from <= 27` ya crea la tabla con la forma *actual*
        // en el bloque `to >= 28` de arriba, así que aquí es `from ==
        // 28` exacto, nunca `from <= 28`.
        if (to >= 29 && from == 28) {
          await migrarAsignacionAttachmentV29(this, m);
        }
        // Aditiva (Etapa 8A): fundación del dominio Vehículos — nueva,
        // independiente de Inventario, + sus 2 índices únicos parciales
        // (`migrarVehiculoV30`, con verificación de FK/integridad,
        // mismo criterio que `migrarAsignacionV28`). Tablas enteramente
        // nuevas, así que `from <= 29` es seguro sin acotar un origen
        // exacto. `CodigoSecuencia('vehiculo')` se siembra vía
        // `runSeed()` normal, arriba en este mismo `onUpgrade`.
        if (to >= 30 && from <= 29) {
          await migrarVehiculoV30(this, m);
        }
        // Aditiva (Etapa 8B): `AsignacionVehiculo` (relación
        // Vehículo↔Empleado/Servicio) + su índice único parcial, y
        // `VehiculoKilometraje` (ledger, sin índice propio) —
        // `migrarAsignacionVehiculoV31`, mismo criterio que
        // `migrarVehiculoV30`. Tablas enteramente nuevas, así que
        // `from <= 30` es seguro sin acotar un origen exacto.
        if (to >= 31 && from <= 30) {
          await migrarAsignacionVehiculoV31(this, m);
        }
        // Aditiva (Etapa 8C): `VehiculoDocumento`/
        // `VehiculoDocumentoAttachment` — ninguna con índice propio, así
        // que a diferencia de 8A/8B basta `m.createTable` directo (sin
        // migración dedicada), mismo criterio que `DescuentoInventario`/
        // `AsignacionAttachment` en 7B. Tablas enteramente nuevas, así
        // que `from <= 31` es seguro sin acotar un origen exacto.
        if (to >= 32 && from <= 31) {
          await m.createTable(vehiculoDocumento);
          await m.createTable(vehiculoDocumentoAttachment);
        }
      },
      // SQLite no aplica FOREIGN KEY por defecto (viene apagado). Sin esto,
      // todas las FK declaradas en las tablas de la Etapa 4A eran solo
      // documentación — nunca se rechazaba una referencia inválida ni se
      // revertía una transacción por violarla. Se encontró al preparar la
      // prueba de atomicidad de la Etapa 4B.
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Tablas agregadas por la Etapa 4A (Fundamentos de Organización) —
  /// puramente aditivo, no toca `AppMetadata`.
  Future<void> _createEtapa4ATables(Migrator m) async {
    await m.createTable(codigoSecuencia);
    await m.createTable(tipoSucursal);
    await m.createTable(industria);
    await m.createTable(tipoServicio);
    await m.createTable(area);
    await m.createTable(direccion);
    await m.createTable(medioContacto);
    await m.createTable(attachment);
    await m.createTable(horario);
    await m.createTable(horarioDetalle);
    await m.createTable(empresa);
    await m.createTable(sucursal);
    await m.createTable(cliente);
    await m.createTable(contacto);
    await m.createTable(servicio);
    await m.createTable(ubicacion);
    await m.createTable(puesto);
    await m.createIndex(idxDireccionClienteTipoPrincipal);
    await m.createIndex(idxDireccionCliente);
    await m.createIndex(idxEmpresaActivaUnica);
    await m.createIndex(idxContactoClienteTipoPrincipalActivo);
  }

  /// Garantiza que exista exactamente un renglón de metadata de instalación.
  ///
  /// Si es la primera vez que se abre la aplicación, lo crea con un
  /// identificador de instalación nuevo. En cualquier otro caso, actualiza
  /// `lastOpenedAt` y `appVersion` y devuelve el renglón resultante.
  ///
  /// Sirve, en esta etapa, únicamente para comprobar que Drift funciona de
  /// extremo a extremo (lectura, inserción y actualización).
  Future<AppMetadataData> ensureMetadata({required String appVersion}) async {
    final existing = await select(appMetadata).getSingleOrNull();
    final now = DateTime.now();

    if (existing == null) {
      final id = await into(appMetadata).insert(
        AppMetadataCompanion.insert(
          installationId: _generateInstallationId(),
          installedAt: now,
          lastOpenedAt: now,
          appVersion: appVersion,
        ),
      );
      return (select(appMetadata)..where((t) => t.id.equals(id))).getSingle();
    }

    final updated = existing.copyWith(lastOpenedAt: now, appVersion: appVersion);
    await update(appMetadata).replace(updated);
    return updated;
  }

  static String _generateInstallationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Abre (o crea) el archivo de base de datos en [databaseFile].
///
/// Se asegura de que la carpeta contenedora exista antes de abrir la
/// conexión, ya que en una instalación nueva la carpeta de datos de la
/// aplicación todavía no existe.
QueryExecutor openAppDatabaseConnection(String databaseFile) {
  final directory = File(databaseFile).parent;
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  return NativeDatabase.createInBackground(File(databaseFile));
}
