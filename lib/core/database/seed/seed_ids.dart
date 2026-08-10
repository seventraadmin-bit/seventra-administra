/// IDs estables de las filas de catálogo sembradas por la aplicación.
///
/// Deliberadamente hardcodeados (no generados al azar en cada siembra):
/// una futura migración que necesite referenciar, por ejemplo,
/// "Industria = Gobierno" debe poder hacerlo por un ID conocido, no por
/// coincidencia de nombre (frágil si alguien traduce o renombra la fila).
abstract final class SeedIds {
  // TipoSucursal
  static const tipoSucursalOficinaAdministrativa = '00000000-0000-4000-8000-000000000001';
  static const tipoSucursalBaseOperativa = '00000000-0000-4000-8000-000000000002';
  static const tipoSucursalBodega = '00000000-0000-4000-8000-000000000003';

  // Industria
  static const industriaComercio = '00000000-0000-4000-8000-000000000101';
  static const industriaIndustrial = '00000000-0000-4000-8000-000000000102';
  static const industriaRetail = '00000000-0000-4000-8000-000000000103';
  static const industriaGobierno = '00000000-0000-4000-8000-000000000104';
  static const industriaOtro = '00000000-0000-4000-8000-000000000105';

  // TipoServicio
  static const tipoServicioVigilanciaFija = '00000000-0000-4000-8000-000000000201';
  static const tipoServicioRondin = '00000000-0000-4000-8000-000000000202';
  static const tipoServicioEscolta = '00000000-0000-4000-8000-000000000203';
  static const tipoServicioMonitoreo = '00000000-0000-4000-8000-000000000204';

  // Area
  static const areaOperaciones = '00000000-0000-4000-8000-000000000301';
  static const areaRecursosHumanos = '00000000-0000-4000-8000-000000000302';
  static const areaAdministracion = '00000000-0000-4000-8000-000000000303';
  static const areaDireccion = '00000000-0000-4000-8000-000000000304';
  static const areaMonitoreo = '00000000-0000-4000-8000-000000000305';
  static const areaReclutamiento = '00000000-0000-4000-8000-000000000306';

  // Empresa
  static const empresaRiseg = '00000000-0000-4000-8000-000000000401';

  // TipoModalidadTurno
  static const modalidadTurno24x24 = '00000000-0000-4000-8000-000000000501';
  static const modalidadTurno24x48 = '00000000-0000-4000-8000-000000000502';
  static const modalidadTurno12x12 = '00000000-0000-4000-8000-000000000503';
  static const modalidadTurnoNocturno = '00000000-0000-4000-8000-000000000504';
  static const modalidadTurnoDiurno = '00000000-0000-4000-8000-000000000505';
  static const modalidadTurnoMixto = '00000000-0000-4000-8000-000000000506';
  static const modalidadTurnoPersonalizado = '00000000-0000-4000-8000-000000000507';

  // TipoFrecuenciaCobro
  static const frecuenciaCobroMensual = '00000000-0000-4000-8000-000000000601';

  // Banco (Etapa 6A) — lista sujeta a confirmación de Marlon antes del
  // cierre de la etapa; `bancoOtro` siempre existe como categoría de
  // respaldo, mismo criterio que `industriaOtro`.
  static const bancoBbva = '00000000-0000-4000-8000-000000000701';
  static const bancoSantander = '00000000-0000-4000-8000-000000000702';
  static const bancoBanorte = '00000000-0000-4000-8000-000000000703';
  static const bancoHsbc = '00000000-0000-4000-8000-000000000704';
  static const bancoCitibanamex = '00000000-0000-4000-8000-000000000705';
  static const bancoScotiabank = '00000000-0000-4000-8000-000000000706';
  static const bancoBanregio = '00000000-0000-4000-8000-000000000707';
  static const bancoInbursa = '00000000-0000-4000-8000-000000000708';
  static const bancoAzteca = '00000000-0000-4000-8000-000000000709';
  static const bancoAfirme = '00000000-0000-4000-8000-000000000710';
  static const bancoOtro = '00000000-0000-4000-8000-000000000711';
}
