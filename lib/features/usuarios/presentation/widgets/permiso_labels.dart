import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:riseg_one/core/permissions/modulos_permiso.dart';

/// Nombre humano de un módulo del catálogo de permisos — nunca se
/// muestra el código técnico (`'personal'`, `'nomina'`, ...) al
/// usuario administrativo. Reutiliza las etiquetas ya existentes del
/// sidebar donde el módulo coincide 1:1 con un destino del Shell;
/// `'nomina'`/`'usuarios'`/los subdominios de Etapa 1 (Ingresos,
/// Egresos, Clientes, ...) son la excepción — ninguno es una ruta de
/// primer nivel propia (ver el doc comment de `ModuloPermiso.codigo`).
String moduloPermisoLabel(AppLocalizations l10n, String codigo) {
  return switch (codigo) {
    'personal' => l10n.modulePersonal,
    'nomina' => l10n.permisoModuloNomina,
    'descuentos' => l10n.permisoModuloDescuentos,
    'finanzas' => l10n.moduleFinanzas,
    'ingresos' => l10n.permisoModuloIngresos,
    'egresos' => l10n.permisoModuloEgresos,
    'deudas' => l10n.permisoModuloDeudas,
    'pagos' => l10n.permisoModuloPagos,
    'cuentasFinancieras' => l10n.permisoModuloCuentasFinancieras,
    'categoriasFinancieras' => l10n.permisoModuloCategoriasFinancieras,
    'cuentaPorCobrar' => l10n.permisoModuloCuentaPorCobrar,
    'compras' => l10n.moduleCompras,
    'inventario' => l10n.moduleInventario,
    'vehiculos' => l10n.moduleVehiculos,
    'telefonia' => l10n.moduleTelefonia,
    'organizacion' => l10n.moduleOrganizacion,
    'comercial' => l10n.moduleComercial,
    'clientes' => l10n.permisoModuloClientes,
    'servicios' => l10n.permisoModuloServicios,
    'configuracionCobro' => l10n.permisoModuloConfiguracionCobro,
    'agendaComercial' => l10n.permisoModuloAgendaComercial,
    'serviciosEventuales' => l10n.permisoModuloServiciosEventuales,
    'reportes' => l10n.moduleReportes,
    'usuarios' => l10n.usuariosListadoTitulo,
    'auditoria' => l10n.configuracionTabAuditoria,
    _ => codigo,
  };
}

String accionBaseLabel(AppLocalizations l10n, AccionBase accion) {
  return switch (accion) {
    AccionBase.ver => l10n.permisoAccionVer,
    AccionBase.crear => l10n.permisoAccionCrear,
    AccionBase.modificar => l10n.permisoAccionModificar,
    AccionBase.archivar => l10n.permisoAccionCancelarArchivar,
    AccionBase.eliminar => l10n.permisoAccionEliminar,
  };
}

/// Etiqueta humana de un código especial (`'nomina.cerrar'`, ...) —
/// cae al propio código solo si aparece uno nuevo en el catálogo sin
/// registrar aquí todavía (nunca debería pasar en producción, pero es
/// preferible a un `throw` en una pantalla administrativa).
String permisoEspecialLabel(AppLocalizations l10n, String codigo) {
  return switch (codigo) {
    'personal.cambiarSueldo' => l10n.permisoPersonalCambiarSueldo,
    'tiempoExtra.crear' => l10n.permisoTiempoExtraCrear,
    'tiempoExtra.corregir' => l10n.permisoTiempoExtraCorregir,
    'tiempoExtra.cancelar' => l10n.permisoTiempoExtraCancelar,
    'nomina.cerrar' => l10n.permisoNominaCerrar,
    'nomina.registrarPago' => l10n.permisoNominaRegistrarPago,
    'nomina.corregirPago' => l10n.permisoNominaCorregirPago,
    'nomina.cancelarPago' => l10n.permisoNominaCancelarPago,
    'nomina.corregir' => l10n.permisoNominaCorregir,
    'nomina.cancelar' => l10n.permisoNominaCancelar,
    'descuentos.ver' => l10n.permisoDescuentosVer,
    'descuentos.crear' => l10n.permisoDescuentosCrear,
    'descuentos.corregir' => l10n.permisoDescuentosCorregir,
    'descuentos.cancelar' => l10n.permisoDescuentosCancelar,
    'compras.corregir' => l10n.permisoComprasCorregir,
    'compras.cancelar' => l10n.permisoComprasCancelar,
    'inventario.corregir' => l10n.permisoInventarioCorregir,
    'inventario.ajustarExistencia' => l10n.permisoInventarioAjustarExistencia,
    'vehiculos.operar' => l10n.permisoVehiculosOperar,
    'vehiculos.cancelar' => l10n.permisoVehiculosCancelar,
    'telefonia.verCredenciales' => l10n.permisoTelefoniaVerCredenciales,
    'telefonia.recargar' => l10n.permisoTelefoniaRecargar,
    'ingresos.crear' => l10n.permisoIngresosCrear,
    'ingresos.corregir' => l10n.permisoIngresosCorregir,
    'ingresos.cancelar' => l10n.permisoIngresosCancelar,
    'egresos.crear' => l10n.permisoEgresosCrear,
    'egresos.corregir' => l10n.permisoEgresosCorregir,
    'egresos.cancelar' => l10n.permisoEgresosCancelar,
    'deudas.crear' => l10n.permisoDeudasCrear,
    'deudas.registrarPago' => l10n.permisoDeudasRegistrarPago,
    'deudas.corregirPago' => l10n.permisoDeudasCorregirPago,
    'deudas.cancelarPago' => l10n.permisoDeudasCancelarPago,
    'deudas.corregir' => l10n.permisoDeudasCorregir,
    'deudas.cancelar' => l10n.permisoDeudasCancelar,
    'pagos.registrar' => l10n.permisoPagosRegistrar,
    'pagos.corregir' => l10n.permisoPagosCorregir,
    'pagos.cancelar' => l10n.permisoPagosCancelar,
    'pagos.cancelarAplicacion' => l10n.permisoPagosCancelarAplicacion,
    'cuentasFinancieras.crear' => l10n.permisoCuentasFinancierasCrear,
    'cuentasFinancieras.corregir' => l10n.permisoCuentasFinancierasCorregir,
    'cuentasFinancieras.cambiarEstatus' => l10n.permisoCuentasFinancierasCambiarEstatus,
    'categoriasFinancieras.crear' => l10n.permisoCategoriasFinancierasCrear,
    'categoriasFinancieras.corregir' => l10n.permisoCategoriasFinancierasCorregir,
    'categoriasFinancieras.archivar' => l10n.permisoCategoriasFinancierasArchivar,
    'cuentaPorCobrar.corregir' => l10n.permisoCuentaPorCobrarCorregir,
    'cuentaPorCobrar.reprogramarCobro' => l10n.permisoCuentaPorCobrarReprogramarCobro,
    'cuentaPorCobrar.cancelar' => l10n.permisoCuentaPorCobrarCancelar,
    'clientes.crear' => l10n.permisoClientesCrear,
    'clientes.corregir' => l10n.permisoClientesCorregir,
    'clientes.archivar' => l10n.permisoClientesArchivar,
    'servicios.crear' => l10n.permisoServiciosCrear,
    'servicios.corregir' => l10n.permisoServiciosCorregir,
    'configuracionCobro.crear' => l10n.permisoConfiguracionCobroCrear,
    'configuracionCobro.corregir' => l10n.permisoConfiguracionCobroCorregir,
    'agendaComercial.crear' => l10n.permisoAgendaComercialCrear,
    'agendaComercial.corregir' => l10n.permisoAgendaComercialCorregir,
    'serviciosEventuales.crear' => l10n.permisoServiciosEventualesCrear,
    'serviciosEventuales.corregir' => l10n.permisoServiciosEventualesCorregir,
    'serviciosEventuales.cancelar' => l10n.permisoServiciosEventualesCancelar,
    'serviciosEventuales.pagar' => l10n.permisoServiciosEventualesPagar,
    'serviciosEventuales.revertirPago' => l10n.permisoServiciosEventualesRevertirPago,
    'serviciosEventuales.cobrar' => l10n.permisoServiciosEventualesCobrar,
    'serviciosEventuales.facturar' => l10n.permisoServiciosEventualesFacturar,
    'usuarios.administrar' => l10n.permisoUsuariosAdministrar,
    'usuarios.otorgarPermisos' => l10n.permisoUsuariosOtorgarPermisos,
    'usuarios.resetearPassword' => l10n.permisoUsuariosResetearPassword,
    'auditoria.ver' => l10n.permisoAuditoriaVer,
    _ => codigo,
  };
}

/// Etiqueta de un permiso cualquiera — resuelve tanto una acción base
/// (`personal.ver`) como un permiso especial (`deudas.corregirPago`),
/// sin que el llamador tenga que saber de cuál se trata (Etapa
/// "Usuarios, permisos y UX de seguridad"). El buscador y el selector la
/// usan para todo el catálogo de forma uniforme.
///
/// Quién manda es el CATÁLOGO, no la forma del código: `'ingresos.crear'`
/// tiene forma de acción base y sin embargo su módulo lo declara en
/// `accionesEspeciales`, con etiqueta propia ("Registrar ingreso").
/// Resolverlo por la forma devolvía un "Crear" genérico para Ingresos,
/// Egresos, Deudas, Compras… y además hacía que el buscador del selector
/// no encontrara el permiso por su nombre real (bug encontrado por la
/// suite al reescribir la prueba responsive del diálogo de permisos).
String permisoLabel(AppLocalizations l10n, String codigo) {
  final esEspecial = modulosPermiso.any((m) => m.accionesEspeciales.contains(codigo));
  if (!esEspecial) {
    final partes = codigo.split('.');
    if (partes.length == 2) {
      final accion = AccionBase.values.where((a) => a.name == partes[1]).firstOrNull;
      if (accion != null) return accionBaseLabel(l10n, accion);
    }
  }
  return permisoEspecialLabel(l10n, codigo);
}

/// Nombre humano de una plantilla de permisos (Etapa "Usuarios,
/// permisos y UX de seguridad"). Las plantillas viven en código
/// (`plantillas_permiso.dart`) y NO son roles: solo precargan casillas.
String plantillaPermisoLabel(AppLocalizations l10n, String codigo) {
  return switch (codigo) {
    'recursosHumanos' => l10n.permisosPlantillaRecursosHumanos,
    'nomina' => l10n.permisosPlantillaNomina,
    'tesoreria' => l10n.permisosPlantillaTesoreria,
    'comercial' => l10n.permisosPlantillaComercial,
    'operaciones' => l10n.permisosPlantillaOperaciones,
    'compras' => l10n.permisosPlantillaCompras,
    'consulta' => l10n.permisosPlantillaConsulta,
    _ => codigo,
  };
}

/// Alias legible de [moduloPermisoLabel] para el selector.
String moduloLabel(AppLocalizations l10n, String codigo) => moduloPermisoLabel(l10n, codigo);

/// Etiqueta del grupo visual (`grupoVisual` de `ModuloPermiso`) — cuando
/// un módulo no pertenece a ningún grupo, la clave ES su propio código,
/// así que se reutiliza su etiqueta de módulo.
String grupoLabel(AppLocalizations l10n, String clave) => moduloPermisoLabel(l10n, clave);
