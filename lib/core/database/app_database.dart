import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../../features/organizacion/data/tables/cliente_attachment_table.dart';
import '../../features/organizacion/data/tables/cliente_portal_table.dart';
import '../../features/organizacion/data/tables/cliente_table.dart';
import '../../features/organizacion/data/tables/configuracion_cobro_correo_table.dart';
import '../../features/organizacion/data/tables/configuracion_cobro_etapa_table.dart';
import '../../features/organizacion/data/tables/comercial_evento_table.dart';
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
import '../../features/organizacion/data/tables/servicio_linea_comercial_vigencia_horario_table.dart';
import '../../features/organizacion/data/tables/servicio_table.dart';
import '../../features/organizacion/data/tables/sucursal_table.dart';
import '../../features/organizacion/data/tables/ubicacion_table.dart';
import '../../features/finanzas/data/tables/categoria_financiera_table.dart';
import '../../features/finanzas/data/tables/complemento_pago_attachment_table.dart';
import '../../features/finanzas/data/tables/complemento_pago_table.dart';
import '../../features/finanzas/data/tables/cuenta_financiera_table.dart';
import '../../features/finanzas/data/tables/cuenta_por_cobrar_table.dart';
import '../../features/finanzas/data/tables/deuda_table.dart';
import '../../features/finanzas/data/tables/egreso_attachment_table.dart';
import '../../features/finanzas/data/tables/egreso_fuente_table.dart';
import '../../features/finanzas/data/tables/transferencia_cuenta_table.dart';
import '../../features/finanzas/data/tables/egreso_table.dart';
import '../../features/finanzas/data/tables/ingreso_attachment_table.dart';
import '../../features/finanzas/data/tables/ingreso_table.dart';
import '../../features/finanzas/data/tables/pago_attachment_table.dart';
import '../../features/finanzas/data/tables/pago_table.dart';
import '../../features/personal/data/tables/asignacion_servicio_sueldo_vigencia_table.dart';
import '../../features/personal/data/tables/asignacion_servicio_table.dart';
import '../../features/personal/data/tables/empleado_attachment_table.dart';
import '../../features/personal/data/tables/conciliacion_baja_table.dart';
import '../../features/personal/data/tables/empleado_table.dart';
import '../../features/personal/data/tables/ficha_tecnica_empleado_table.dart';
import '../../features/personal/data/tables/vacante_operativa_table.dart';
import '../../features/descuentos_personal/data/tables/descuento_programado_cuota_table.dart';
import '../../features/descuentos_personal/data/tables/descuento_programado_empleado_table.dart';
import '../../features/descuentos_personal/data/tables/descuento_programado_movimiento_table.dart';
import '../../features/nomina/data/tables/nomina_empleado_ausencia_table.dart';
import '../../features/nomina/data/tables/nomina_empleado_table.dart';
import '../../features/nomina/data/tables/nomina_empleado_tramo_table.dart';
import '../../features/nomina/data/tables/nomina_evento_table.dart';
import '../../features/nomina/data/tables/nomina_table.dart';
import '../../features/servicios_eventuales/data/tables/servicio_eventual_documento_fiscal_table.dart';
import '../../features/servicios_eventuales/data/tables/servicio_eventual_table.dart';
import '../../features/tiempos_extra/data/tables/tiempo_extra_table.dart';
import '../../features/nomina/data/tables/pago_nomina_attachment_table.dart';
import '../../features/nomina/data/tables/pago_nomina_table.dart';
import '../../features/inventario/data/tables/articulo_table.dart';
import '../../features/inventario/data/tables/articulo_unidad_evento_table.dart';
import '../../features/inventario/data/tables/articulo_unidad_table.dart';
import '../../features/inventario/data/tables/articulo_unidad_telefono_table.dart';
import '../../features/inventario/data/tables/articulo_variante_table.dart';
import '../../features/inventario/data/tables/asignacion_attachment_table.dart';
import '../../features/inventario/data/tables/asignacion_table.dart';
import '../../features/inventario/data/tables/categoria_articulo_table.dart';
import '../../features/inventario/data/tables/descuento_inventario_table.dart';
import '../../features/inventario/data/tables/entrega_table.dart';
import '../../features/inventario/data/tables/movimiento_inventario_attachment_table.dart';
import '../../features/inventario/data/tables/movimiento_inventario_table.dart';
import '../../features/telefonia/data/tables/asignacion_linea_telefonica_table.dart';
import '../../features/telefonia/data/tables/equipo_telefonico_table.dart';
import '../../features/telefonia/data/tables/linea_telefonica_equipo_table.dart';
import '../../features/telefonia/data/tables/linea_telefonica_table.dart';
import '../../features/telefonia/data/tables/recarga_linea_telefonica_table.dart';
import '../../features/vehiculos/data/tables/asignacion_vehiculo_table.dart';
import '../../features/vehiculos/data/tables/vehiculo_documento_table.dart';
import '../../features/vehiculos/data/tables/vehiculo_kilometraje_table.dart';
import '../../features/vehiculos/data/tables/vehiculo_mantenimiento_table.dart';
import '../../features/vehiculos/data/tables/vehiculo_table.dart';
import '../../features/boveda/data/tables/boveda_credencial_table.dart';
import '../../features/compras/data/tables/compra_attachment_table.dart';
import '../../features/compras/data/tables/compra_partida_table.dart';
import '../../features/compras/data/tables/compra_table.dart';
import '../../features/usuarios/data/tables/permiso_usuario_table.dart';
import '../../features/usuarios/data/tables/sesion_persistente_table.dart';
import '../../features/usuarios/data/tables/usuario_table.dart';
import '../security/credential_cipher.dart';
import 'migrations/migrar_asignacion_attachment_v29.dart';
import 'migrations/migrar_asignacion_linea_telefonica_v35.dart';
import 'migrations/migrar_asignacion_vehiculo_v31.dart';
import 'migrations/migrar_compra_v37.dart';
import 'migrations/migrar_usuario_v38.dart';
import 'migrations/migrar_permiso_usuario_v39.dart';
import 'migrations/migrar_auditoria_v40.dart';
import 'migrations/migrar_equipos_telefonicos_v41.dart';
import 'migrations/migrar_cambiar_responsable_asignacion_v42.dart';
import 'migrations/migrar_categoria_articulo_aplicacion_v43.dart';
import 'migrations/migrar_articulo_unidad_evento_v44.dart';
import 'migrations/migrar_boveda_v45.dart';
import 'migrations/migrar_sesion_persistente_v46.dart';
import 'migrations/migrar_documento_por_emitir_uuid_v47.dart';
import 'migrations/migrar_configuracion_cobro_etapa_v49.dart';
import 'migrations/migrar_condiciones_personal_linea_comercial_v50.dart';
import 'migrations/migrar_horario_linea_comercial_v51.dart';
import 'migrations/migrar_cliente_portal_v52.dart';
import 'migrations/migrar_compra_eliminacion_fisica_v53.dart';
import 'migrations/migrar_descuento_inventario_nomina_v54.dart';
import 'migrations/migrar_reparacion_descuentos_inventario_v55.dart';
import 'migrations/migrar_vacante_operativa_v56.dart';
import 'migrations/migrar_descuentos_personal_v57.dart';
import 'migrations/migrar_snapshot_baja_empleado_v58.dart';
import 'migrations/migrar_cliente_logo_v59.dart';
import 'migrations/migrar_entrega_inventario_v60.dart';
import 'migrations/migrar_compra_tarjeta_v62.dart';
import 'migrations/migrar_cuenta_financiera_v63.dart';
import 'migrations/migrar_cuenta_por_cobrar_reprogramacion_v64.dart';
import 'migrations/migrar_tiempos_extra_v65.dart';
import 'migrations/migrar_deuda_ciclo_cubierto_v68.dart';
import 'migrations/migrar_deuda_tarjeta_revolvente_v66.dart';
import 'migrations/migrar_deuda_tasa_cat_v67.dart';
import 'migrations/migrar_correccion_tiempo_extra_v70.dart';
import 'migrations/migrar_permisos_granulares_v71.dart';
import 'migrations/migrar_correccion_nomina_v72.dart';
import 'migrations/migrar_correccion_descuento_programado_v73.dart';
import 'migrations/migrar_correccion_cuenta_por_cobrar_v74.dart';
import 'migrations/migrar_origen_financiero_descuento_programado_v75.dart';
import 'migrations/migrar_egreso_origen_tarjeta_v76.dart';
import 'migrations/migrar_correccion_pago_deuda_v77.dart';
import 'migrations/migrar_conciliacion_baja_v83.dart';
import 'migrations/migrar_origen_cobertura_tiempo_extra_v85.dart';
import 'migrations/migrar_recarga_origen_financiero_v86.dart';
import 'migrations/migrar_trazabilidad_comercial_v84.dart';
import 'migrations/migrar_pendiente_recuperacion_v82.dart';
import 'migrations/migrar_telefonia_trazabilidad_v81.dart';
import 'migrations/migrar_vehiculos_origen_financiero_v80.dart';
import 'migrations/migrar_complemento_sustituto_v79.dart';
import 'migrations/migrar_cobranza_eventual_v88.dart';
import 'migrations/migrar_iva_eventual_v89.dart';
import 'migrations/migrar_origen_financiero_multicuenta_v91.dart';
import 'migrations/migrar_receptor_fiscal_eventual_v90.dart';
import 'migrations/migrar_servicios_eventuales_v87.dart';
import 'migrations/migrar_usuarios_permisos_v78.dart';
import 'migrations/migrar_origen_financiero_tiempo_extra_v69.dart';
import 'migrations/migrar_deudas_credito_v61.dart';
import 'migrations/migrar_empleado_v48.dart';
import 'migrations/migrar_linea_telefonica_v34.dart';
import 'migrations/migrar_recarga_linea_telefonica_v36.dart';
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
  ClientePortal,
  ServicioLineaComercial,
  ServicioLineaComercialVigencia,
  ServicioLineaComercialVigenciaHorario,
  ConfiguracionCobro,
  ClienteEvento,
  ServicioEvento,
  ConfiguracionCobroEvento,
  ConfiguracionCobroVigencia,
  ConfiguracionCobroCorreo,
  ConfiguracionCobroEtapa,
  DocumentoPorEmitir,
  DocumentoPorEmitirServicio,
  DocumentoPorEmitirConfiguracion,
  DocumentoPorEmitirHito,
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
  EgresoFuente,
  TransferenciaCuenta,
  TransferenciaCuentaEvento,
  Deuda,
  MovimientoDeuda,
  CuentaFinanciera,
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
  ArticuloUnidadEvento,
  MovimientoInventario,
  MovimientoInventarioAttachment,
  Asignacion,
  DescuentoInventario,
  AsignacionAttachment,
  Entrega,
  Vehiculo,
  VehiculoAttachment,
  AsignacionVehiculo,
  VehiculoKilometraje,
  VehiculoDocumento,
  VehiculoDocumentoAttachment,
  VehiculoMantenimiento,
  VehiculoMantenimientoAttachment,
  VehiculoEvento,
  LineaTelefonicaEvento,
  ConciliacionBaja,
  ConciliacionBajaRenglon,
  LineaTelefonica,
  AsignacionLineaTelefonica,
  LineaTelefonicaEquipo,
  RecargaLineaTelefonica,
  RecargaLineaTelefonicaAttachment,
  EquipoTelefonicoCredencial,
  EquipoTelefonicoEvento,
  Compra,
  CompraPartida,
  CompraPartidaMovimiento,
  CompraAttachment,
  CompraEvento,
  Usuario,
  UsuarioEvento,
  PermisoUsuario,
  EliminacionFisicaEvento,
  BovedaCredencial,
  BovedaCredencialEvento,
  SesionPersistente,
  VacanteOperativa,
  DescuentoProgramadoEmpleado,
  DescuentoProgramadoCuota,
  DescuentoProgramadoMovimiento,
  // Etapa "Tiempos Extra" (cobertura operativa por ausencia).
  TiempoExtra,
  TiempoExtraCostoAdicional,
  // Servicios Eventuales — Rebanada 1 (schemaVersion 87).
  ServicioEventual,
  ServicioEventualParticipante,
  ServicioEventualCobertura,
  ServicioEventualCosto,
  ServicioEventualEvento,
  ServicioEventualDocumentoFiscal,
  ServicioEventualDocumentoFiscalAttachment,
  TiempoExtraEvento,
  NominaEmpleadoAusencia,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {AlmacenClaveCifrado? almacenClaveCifrado}) : _almacenClaveCifrado = almacenClaveCifrado;

  /// Solo se usa dentro de `onUpgrade`, para cifrar contraseñas legadas
  /// de portal al migrar a `schemaVersion` 52 (`migrarClientePortalV52`).
  /// En producción es `null` — `CredentialCipher` usa entonces el
  /// Almacén de Credenciales de Windows real; las pruebas de migración
  /// inyectan una implementación en memoria aquí.
  final AlmacenClaveCifrado? _almacenClaveCifrado;

  @override
  int get schemaVersion => 91;

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
        // Aditiva (Etapa 4H.2): originalmente creaba
        // ConfiguracionCobroReglaEvento aquí — reemplazada por completo
        // en la Etapa 15 (`migrarConfiguracionCobroEtapaV49`) por
        // ConfiguracionCobroEtapa. Este paso ya **no** la crea: mismo
        // criterio exacto que `migrarLineaTelefonicaV34` con
        // `LineaTelefonicaPlan` — cualquier instalación que salte de una
        // versión ≤9 directo a la actual (`to >= 49`) jamás necesita
        // materializarla, porque el paso 49 la reemplazaría en el mismo
        // salto de todos modos.
        if (to >= 10 && from <= 9) {
          // Sin cuerpo — ver el comentario de arriba.
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
        // Aditiva (Etapa 8D): `VehiculoMantenimiento`/
        // `VehiculoMantenimientoAttachment` — ninguna con índice propio,
        // mismo criterio que la Etapa 8C. Tablas enteramente nuevas, así
        // que `from <= 32` es seguro sin acotar un origen exacto. Cierra
        // funcionalmente el dominio Vehículos (8A→8D).
        if (to >= 33 && from <= 32) {
          await m.createTable(vehiculoMantenimiento);
          await m.createTable(vehiculoMantenimientoAttachment);
        }
        // Aditiva (Etapa 9A): funda el dominio Telefonía —
        // `LineaTelefonica`/`LineaTelefonicaPlan` (`LineaTelefonicaPlan`
        // retirada en la Etapa 9C, ver `migrarRecargaLineaTelefonicaV36`)
        // + índice único parcial de `LineaTelefonica.numero`
        // (`migrarLineaTelefonicaV34`, mismo criterio que
        // `migrarVehiculoV30`). Tablas enteramente nuevas, así que
        // `from <= 33` es seguro sin acotar un origen exacto.
        if (to >= 34 && from <= 33) {
          await migrarLineaTelefonicaV34(this, m);
        }
        // Aditiva (Etapa 9B): `AsignacionLineaTelefonica`/
        // `LineaTelefonicaEquipo` + índice único parcial de
        // AsignacionLineaTelefonica. Tablas enteramente nuevas, así que
        // `from <= 34` es seguro sin acotar un origen exacto.
        if (to >= 35 && from <= 34) {
          await migrarAsignacionLineaTelefonicaV35(this, m);
        }
        // Etapa 9C: confirma que la operación real de Telefonía es
        // prepago — retira `LineaTelefonicaPlan` (9A, sin uso funcional
        // real) y funda `RecargaLineaTelefonica`/
        // `RecargaLineaTelefonicaAttachment`. Tablas nuevas enteramente
        // aditivas, así que `from <= 35` es seguro sin acotar un origen
        // exacto.
        if (to >= 36 && from <= 35) {
          await migrarRecargaLineaTelefonicaV36(this, m);
        }
        // Aditiva (Etapa 10): funda el dominio Compras — `Compra`/
        // `CompraPartida`/`CompraPartidaMovimiento`/`CompraAttachment`/
        // `CompraEvento`. Tablas enteramente nuevas, así que
        // `from <= 36` es seguro sin acotar un origen exacto.
        if (to >= 37 && from <= 36) {
          await migrarCompraV37(this, m);
        }
        // Aditiva (Etapa 11A): funda el dominio Usuarios — `Usuario`
        // (cuenta de acceso, sin FK a `Empleado`) y `UsuarioEvento`
        // (historial administrativo append-only). Tablas enteramente
        // nuevas, así que `from <= 37` es seguro sin acotar un origen
        // exacto. `PermisoUsuario` llega en la Etapa 11B.
        if (to >= 38 && from <= 37) {
          await migrarUsuarioV38(this, m);
        }
        // Aditiva (Etapa 11B): `PermisoUsuario` — permisos dinámicos por
        // Usuario. Tabla enteramente nueva, así que `from <= 38` es
        // seguro sin acotar un origen exacto.
        if (to >= 39 && from <= 38) {
          await migrarPermisoUsuarioV39(this, m);
        }
        // Aditiva (Etapa 11D): `actorUsuarioId` en las 15 tablas de
        // evento/ledger del proyecto + `EliminacionFisicaEvento`. Todas
        // las tablas afectadas ya existen desde antes de schemaVersion
        // 39, así que `from <= 39` es seguro sin acotar un origen
        // exacto.
        if (to >= 40 && from <= 39) {
          await migrarAuditoriaV40(this, m);
        }
        // Aditiva (Etapa 9D): `imei2`/`actorUsuarioId` en 3 tablas ya
        // existentes de Inventario/Telefonía + `EquipoTelefonicoCredencial`/
        // `EquipoTelefonicoEvento`, enteramente nuevas.
        if (to >= 41 && from <= 40) {
          await migrarEquiposTelefonicosV41(this, m);
        }
        // Aditiva (Etapa 9D, ajuste posterior): `Asignacion.actorUsuarioId`
        // — `Asignacion` existe desde schemaVersion 28, muy anterior a
        // 42, así que `from <= 41` es seguro sin acotar un origen exacto.
        if (to >= 42 && from <= 41) {
          await migrarCambiarResponsableAsignacionV42(this, m);
        }
        // Aditiva (Etapa 9D, segundo ajuste posterior):
        // `CategoriaArticulo.aplicacionEspecializada` — `CategoriaArticulo`
        // existe desde la Etapa 7A, muy anterior a 43, así que `from <=
        // 42` es seguro sin acotar un origen exacto.
        if (to >= 43 && from <= 42) {
          await migrarCategoriaArticuloAplicacionV43(this, m);
        }
        // Aditiva: `ArticuloUnidadEvento`, tabla enteramente nueva —
        // bitácora de `CorregirIdentidadUnidadUseCase`.
        if (to >= 44 && from <= 43) {
          await migrarArticuloUnidadEventoV44(this, m);
        }
        // Aditiva (Etapa 14D): `BovedaCredencial`/`BovedaCredencialEvento`,
        // tablas enteramente nuevas — Bóveda de Accesos del Maestro.
        if (to >= 45 && from <= 44) {
          await migrarBovedaV45(this, m);
        }
        // Aditiva (Etapa 15): `SesionPersistente`, tabla enteramente
        // nueva — "Recuérdame en este equipo".
        if (to >= 46 && from <= 45) {
          await migrarSesionPersistenteV46(this, m);
        }
        // Estructural (Etapa 15, corrección CFDI real): elimina
        // `serieFiscal`, elimina `folioFiscal` (fusionado en `uuid`,
        // con `COALESCE` para no perder datos ya capturados), en
        // `DocumentoPorEmitir` y `CuentaPorCobrar`.
        if (to >= 47 && from <= 46) {
          await migrarDocumentoPorEmitirUuidV47(this, m);
        }
        // Aditiva (Etapa 15): `Empleado.bancoOtroDescripcion` — nombre
        // del banco cuando `bancoId` apunta a la fila catálogo `'OTRO'`.
        if (to >= 48 && from <= 47) {
          await migrarEmpleadoV48(this, m);
        }
        // Estructural (Etapa 15, ampliación "flujo posterior a la
        // emisión"): reemplaza `ConfiguracionCobroReglaEvento` (catálogo
        // fijo de 3 eventos) por `ConfiguracionCobroEtapa` (colección
        // dinámica de etapas de sistema + personalizadas), migrando cada
        // fila existente sin perder ninguna captura real, y agrega
        // `DocumentoPorEmitirHito` (tabla enteramente nueva).
        if (to >= 49 && from <= 48) {
          await migrarConfiguracionCobroEtapaV49(this, m);
        }
        // Aditiva (Etapa 15, rediseño "Condiciones de Personal"):
        // sueldo/bono de referencia pasan de `Servicio` (global) a
        // `ServicioLineaComercialVigencia` (por perfil contratado);
        // `AsignacionServicio` gana `lineaComercialId`. Incluye
        // migración asistida en el caso trivial (1 sola línea vigente
        // hoy + sueldo global capturado) — ver el doc comment del
        // archivo para el criterio exacto.
        if (to >= 50 && from <= 49) {
          await migrarCondicionesPersonalLineaComercialV50(this, m);
        }
        // Aditiva (Etapa 15, Horario personalizado de línea comercial):
        // tabla enteramente nueva `ServicioLineaComercialVigenciaHorario`.
        if (to >= 51 && from <= 50) {
          await migrarHorarioLineaComercialV51(this, m);
        }
        // Aditiva+estructural (Etapa 15, portal único del Cliente): funda
        // `ClientePortal` — única fuente de verdad nueva de portales,
        // antes duplicados en cada `ConfiguracionCobroVigencia`. Migra
        // los portales legados (cifrando cualquier contraseña en texto
        // plano) sin tocar los correos — ver el doc comment del archivo.
        if (to >= 52 && from <= 51) {
          await migrarClientePortalV52(this, m, cipher: CredentialCipher(almacen: _almacenClaveCifrado));
        }
        // Aditiva (Etapa 15, bug real COM-000021): estructura el motivo
        // de cancelación/eliminación física de `Compra` — ver el doc
        // comment del archivo de migración.
        if (to >= 53 && from <= 52) {
          await migrarCompraEliminacionFisicaV53(this, m);
        }
        // Aditiva (Etapa 15, prueba funcional Inventario + Personal +
        // Nómina): activa "Pendiente → Aplicado" de DescuentoInventario
        // — ver el doc comment del archivo de migración.
        if (to >= 54 && from <= 53) {
          await migrarDescuentoInventarioNominaV54(this, m);
        }
        // REPARACIÓN (Etapa 15, bug real): la instalación real de
        // desarrollo ya había migrado a 54 con la forma anterior de
        // `migrarDescuentoInventarioNominaV54` (sin
        // `descuentos_inventario_pendiente_revision`, agregada después
        // sin subir de versión) — Drift nunca vuelve a correr
        // `onUpgrade` si `user_version` ya coincide con `schemaVersion`,
        // así que esa instalación se quedó con la columna faltante. Ver
        // el doc comment del archivo de migración para la causa raíz
        // completa.
        if (to >= 55 && from <= 54) {
          await migrarReparacionDescuentosInventarioV55(this, m);
        }
        // Aditiva (Etapa 15, rediseño del Dashboard gerencial): tabla
        // nueva `VacanteOperativa` — ver el doc comment del archivo de
        // migración.
        if (to >= 56 && from <= 55) {
          await migrarVacanteOperativaV56(this, m);
        }
        // Aditiva (Etapa 15, "Descuentos Programados al Personal" —
        // préstamos + cobro de botas): 3 tablas nuevas + 2 columnas en
        // NominaEmpleado + 2 filas de CodigoSecuencia — ver el doc
        // comment del archivo de migración.
        if (to >= 57 && from <= 56) {
          await migrarDescuentosPersonalV57(this, m);
        }
        // Aditiva (Etapa 15, rediseño de Personal/Bajas): snapshot de
        // puesto/servicio/turno al momento de la baja en `Empleado` y
        // en `EmpleadoPeriodoLaboral` — ver el doc comment del archivo
        // de migración para el backfill real de bajas ya existentes.
        if (to >= 58 && from <= 57) {
          await migrarSnapshotBajaEmpleadoV58(this, m);
        }
        // Aditiva (Etapa 16, evolución visual del Design System):
        // `Cliente.logoAttachmentId` — ver el doc comment del archivo
        // de migración.
        if (to >= 59 && from <= 58) {
          await migrarClienteLogoV59(this, m);
        }
        // Aditiva ("Entrega múltiple de Inventario a Personal"): tabla
        // nueva `Entrega` (cabecera documental que agrupa varias
        // Asignacion de un mismo acto de entrega) + columna
        // `Asignacion.entregaId` (nullable — toda Asignacion legacy y
        // toda la que siga creando "Asignar artículo" individual queda
        // sin agrupar, sin romperse) + fila de CodigoSecuencia
        // (`entrega` → `ENT`) — ver el doc comment del archivo de
        // migración.
        if (to >= 60 && from <= 59) {
          await migrarEntregaInventarioV60(this, m);
        }
        // Aditiva (Etapa 19, "Deudas y crédito empresarial"): tablas
        // nuevas `Deuda` (identidad propia con saldo — nunca una
        // `CategoriaFinanciera` más) + `MovimientoDeuda` (historial
        // append-only con saldo explícito por línea) + fila de
        // CodigoSecuencia (`deuda` → `DEU`) — ver el doc comment del
        // archivo de migración.
        if (to >= 61 && from <= 60) {
          await migrarDeudasCreditoV61(this, m);
        }
        // Aditiva (Etapa 19B, "Compra ↔ Tarjeta de crédito ↔ Deuda"):
        // `MovimientoDeuda.compraId` (vínculo determinista al cargo que
        // una Compra pagada con tarjeta genera) + `Compra.deudaId`
        // (qué tarjeta la financió) — ambas columnas nuevas y nullable,
        // sin backfill: ninguna Compra/MovimientoDeuda existente tiene
        // qué reconstruir. Ver el doc comment del archivo de migración.
        if (to >= 62 && from <= 61) {
          await migrarCompraTarjetaV62(this, m);
        }
        // Aditiva (Etapa 19C, "Posición de caja, flujo real y
        // proyección de compromisos"): tabla nueva `CuentaFinanciera`
        // (Banco/Efectivo, sin saldoActual persistido — siempre
        // derivado) + `Ingreso.cuentaFinancieraId`/
        // `Egreso.cuentaFinancieraId` (nullable, restrict) + fila de
        // CodigoSecuencia (`cuenta_financiera` → `CTA`) — ver el doc
        // comment del archivo de migración.
        if (to >= 63 && from <= 62) {
          await migrarCuentaFinancieraV63(this, m);
        }
        // Aditiva (Etapa 19D, "Calendario financiero y planeación de
        // liquidez"): `CuentaPorCobrar.fechaCobroReprogramada`
        // (nullable) — nunca toca `fechaVencimiento`. Ver el doc
        // comment del archivo de migración.
        if (to >= 64 && from <= 63) {
          await migrarCuentaPorCobrarReprogramacionV64(this, m);
        }
        // Aditiva (Etapa "Tiempos Extra" — cobertura operativa por
        // ausencia): tablas nuevas `TiempoExtra`/
        // `TiempoExtraCostoAdicional`/`TiempoExtraEvento` +
        // `NominaEmpleadoAusencia` + fila de catálogo
        // `TipoModalidadTurno` ("12X24") + fila de CodigoSecuencia
        // (`tiempoExtra` → `TEX`) — ver el doc comment del archivo de
        // migración.
        if (to >= 65 && from <= 64) {
          await migrarTiemposExtraV65(this, m);
        }
        // Estructural (Etapa "Tarjeta de crédito como línea revolvente"):
        // `Deuda.importeOriginal`/`fechaOrigen` pasan a nullable (no
        // aplican a una TDC) + columnas nuevas `fechaSaldoInicial`/
        // `tarjetaReglaFechaPago`/`tarjetaDiasDespuesCorte` — con
        // backfill fiel a partir de datos ya existentes (nunca
        // inventados). Ver el doc comment del archivo de migración.
        if (to >= 66 && from <= 65) {
          await migrarDeudaTarjetaRevolventeV66(this, m);
        }
        // Aditiva (Etapa "Tasa fija/variable y CAT para TDC", caso real
        // Konfío Empresarial): 7 columnas nuevas en `Deuda` para
        // modelar la tasa ordinaria de una tarjeta como fija o variable
        // (referencia/diferencial/tratamiento de IVA) sin colapsarla a
        // un porcentaje falso, más un CAT opcional — ver el doc
        // comment del archivo de migración.
        if (to >= 67 && from <= 66) {
          await migrarDeudaTasaCatV67(this, m);
        }
        // Aditiva (Etapa "Dashboard: posición financiera + ciclo de
        // TDC"): 1 columna nueva en `Deuda`,
        // `tarjetaVencimientoCubiertoHasta` — permite conciliar, al
        // incorporar una TDC ya en uso, un ciclo de pago cubierto ANTES
        // de capturar sus saldos reales (sin generar Egreso/
        // MovimientoDeuda) y avanza automáticamente al registrar un
        // pago real — ver el doc comment del archivo de migración y de
        // la columna en `deuda_table.dart`.
        if (to >= 68 && from <= 67) {
          await migrarDeudaCicloCubiertoV68(this, m);
        }
        // Aditiva (Etapa "Origen financiero unificado — TiempoExtra,
        // Egresos manuales, TDC"): 6 columnas nuevas —
        // `MovimientoDeuda.tiempoExtraId`/`costoAdicionalId`,
        // `TiempoExtra.deudaId`, `TiempoExtraCostoAdicional.formaPago`/
        // `egresoId`/`deudaId` — ver el doc comment del archivo de
        // migración.
        if (to >= 69 && from <= 68) {
          await migrarOrigenFinancieroTiempoExtraV69(this, m);
        }
        // Etapa "corrección real de Tiempo Extra": aditiva
        // (`TiempoExtraEvento.estadoAnterior`/`estadoNuevo`) + datos
        // (reemplaza `personal.gestionarTiemposExtra` por 3 permisos
        // separados, sin quitar acceso a quien ya lo tenía) — ver el
        // doc comment del archivo de migración.
        if (to >= 70 && from <= 69) {
          await migrarCorreccionTiempoExtraV70(this, m);
        }
        // Etapa "1 — Modelo de permisos granular y consistente": de
        // datos, sin cambio de esquema — reemplaza/estrecha varios
        // códigos amplios de `PermisoUsuario` por facultades más finas,
        // conservador con todo usuario que ya tenía el código viejo
        // (ver el doc comment del archivo de migración).
        if (to >= 71 && from <= 70) {
          await migrarPermisosGranularesV71(this, m);
        }
        // Etapa 4 ("Nómina — corrección, cancelación y trazabilidad
        // integral"): aditiva — `NominaEvento.estadoAnterior`/
        // `estadoNuevo` + `Nomina.motivoCancelacionCodigo`/`Detalle`/
        // `Observaciones` — ver el doc comment del archivo de
        // migración.
        if (to >= 72 && from <= 71) {
          await migrarCorreccionNominaV72(this, m);
        }
        // Etapa 5 ("Descuentos programados — CRUD corregible,
        // trazabilidad y consistencia con Nómina"): aditiva —
        // `DescuentoProgramadoMovimiento.estadoAnterior`/`estadoNuevo`
        // — ver el doc comment del archivo de migración.
        if (to >= 73 && from <= 72) {
          await migrarCorreccionDescuentoProgramadoV73(this, m);
        }
        // Etapa 7 ("Cuentas por cobrar — corrección, cancelación,
        // trazabilidad y consistencia con Agenda/Pagos"): puramente de
        // datos (permisos) — ver el doc comment del archivo de migración.
        if (to >= 74 && from <= 73) {
          await migrarCorreccionCuentaPorCobrarV74(this, m);
        }
        // Etapa "Cierre del ciclo financiero de Descuentos Programados —
        // Préstamo/Botas": puramente aditiva (2 columnas nullable) — ver
        // el doc comment del archivo de migración.
        if (to >= 75 && from <= 74) {
          await migrarOrigenFinancieroDescuentoProgramadoV75(this, m);
        }
        // Etapa "Origen financiero de Egresos manuales: Cuenta vs. TDC":
        // puramente aditiva (2 columnas nullable) — `Egreso.deudaId` y
        // `MovimientoDeuda.egresoGastoId`. Sin backfill: ningún Egreso
        // histórico con `formaPago == 'tarjeta'` guarda en ninguna parte
        // CUÁL tarjeta lo financió — ver el doc comment del archivo de
        // migración.
        if (to >= 76 && from <= 75) {
          await migrarEgresoOrigenTarjetaV76(this, m);
        }
        // Etapa 9 ("Deudas y crédito: corrección y cancelación
        // individual de pagos"): puramente aditiva (2 columnas nullable
        // en `MovimientoDeuda` — `movimientoOrigenId` y
        // `tarjetaVencimientoCubiertoAnterior`). El valor nuevo
        // `reversionPago` del enum no requiere migración: `tipo` es
        // texto libre. Ver el doc comment del archivo de migración.
        if (to >= 77 && from <= 76) {
          await migrarCorreccionPagoDeudaV77(this, m);
        }
        // Etapa "Usuarios, permisos y UX de seguridad": aditiva
        // (`Usuario.empleadoId`/`debeCambiarPassword`) + datos (fragmenta
        // `usuarios.administrar` en facultades separables, sin quitar
        // acceso a nadie) — ver el doc comment del archivo de migración.
        if (to >= 78 && from <= 77) {
          await migrarUsuariosPermisosV78(this, m);
        }

        // Complemento de pago sustituto (schemaVersion 79): retira el
        // UNIQUE de columna sobre `pago_id` y lo reemplaza por un
        // índice único PARCIAL sobre los vigentes, para que un
        // Complemento cancelado deje de bloquear a su sustituto — ver
        // el doc comment del archivo de migración.
        if (to >= 79 && from <= 78) {
          await migrarComplementoSustitutoV79(this, m);
        }

        // Vehículos: ciclo de vida, origen financiero y trazabilidad
        // (schemaVersion 80) — `VehiculoEvento`, origen financiero dual
        // del mantenimiento (`egresoId`/`deudaId`) y su anulación.
        // Puramente aditiva, SIN backfill del gasto histórico (ver el
        // doc comment del archivo de migración).
        if (to >= 80 && from <= 79) {
          await migrarVehiculosOrigenFinancieroV80(this, m);
        }
        if (to >= 81 && from <= 80) {
          await migrarTelefoniaTrazabilidadV81(this, m);
        }
        if (to >= 82 && from <= 81) {
          await migrarPendienteRecuperacionV82(this, m);
        }
        if (to >= 83 && from <= 82) {
          await migrarConciliacionBajaV83(this, m);
        }
        if (to >= 84 && from <= 83) {
          await migrarTrazabilidadComercialV84(this, m);
        }
        // Estructural (Etapa "Tiempo Extra: origen de cobertura"):
        // `TiempoExtra.empleadoAusenteId`/`motivoAusencia` pasan a
        // nullable + 3 columnas nuevas (`origenCobertura`,
        // `vacanteOperativaId`, `descripcionOrigen`). Todo lo
        // histórico queda clasificado como `ausenciaEmpleado` — que es
        // lo que era por construcción del esquema anterior, no una
        // inferencia. Ver el doc comment del archivo de migración.
        if (to >= 85 && from <= 84) {
          await migrarOrigenCoberturaTiempoExtraV85(this, m);
        }
        // Aditiva (Etapa "Cierre integral de Telefonía — recargas"):
        // origen financiero real de `RecargaLineaTelefonica`
        // (`formaPago`/`egresoId`/`deudaId`) + FK inversa
        // `MovimientoDeuda.recargaLineaTelefonicaId`. Cero efecto
        // retroactivo sobre balances — ver el doc comment del archivo.
        if (to >= 86 && from <= 85) {
          await migrarRecargaOrigenFinancieroV86(this, m);
        }
        // Servicios Eventuales (Rebanada 1): núcleo nuevo + la
        // generalización de Cuenta por cobrar/Pago a un origen dual.
        if (to >= 87 && from <= 86) {
          await migrarServiciosEventualesV87(this, m);
        }
        if (to >= 88 && from <= 87) {
          await migrarCobranzaEventualV88(this, m);
        }
        if (to >= 89 && from <= 88) {
          await migrarIvaEventualV89(this, m);
        }
        // El receptor fiscal del eventual, separado del solicitante.
        if (to >= 90 && from <= 89) {
          await migrarReceptorFiscalEventualV90(this, m);
        }
        // Origen financiero multicuenta + transferencias entre cuentas.
        if (to >= 91 && from <= 90) {
          await migrarOrigenFinancieroMulticuentaV91(this, m);
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
