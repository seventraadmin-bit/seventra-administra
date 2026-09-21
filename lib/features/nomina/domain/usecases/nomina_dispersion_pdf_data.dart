import 'package:riseg_one/core/database/app_database.dart';

const _estatusLabel = {'cerrada': 'Cerrada', 'pagada': 'Pagada'};

/// `true` si falta el banco, o si faltan AMBOS identificadores de
/// destino (cuenta/tarjeta y CLABE) — no se puede dispersar sin banco,
/// y hace falta al menos uno de los dos para identificar la cuenta
/// destino (algunos bancos solo piden cuenta/tarjeta, otros solo
/// CLABE — exigir ambos siempre marcaría en falso la mayoría de los
/// casos reales). Única fuente de verdad, compartida entre el PDF de
/// dispersión ([NominaDispersionPdfRenglon.requiereVerificacion]) y la
/// tabla interactiva de "Registrar pago de nómina" (Etapa 15) — ambos
/// deben marcar exactamente los mismos renglones.
bool requiereVerificacionBancaria({
  required String? bancoNombre,
  required String? numeroCuentaTarjeta,
  required String? clabe,
}) {
  final sinBanco = bancoNombre == null || bancoNombre.trim().isEmpty;
  final sinCuenta = numeroCuentaTarjeta == null || numeroCuentaTarjeta.trim().isEmpty;
  final sinClabe = clabe == null || clabe.trim().isEmpty;
  return sinBanco || (sinCuenta && sinClabe);
}

/// Ordena renglones de Nómina Banco → Nombre (Etapa 15) — misma
/// función pura usada por el PDF de dispersión
/// ([construirNominaDispersionPdfData]) y por la tabla interactiva de
/// "Registrar pago de nómina", para que el mismo Empleado se localice
/// en la misma posición relativa entre PDF y pantalla. Los renglones
/// sin banco quedan al final, ordenados por nombre entre sí — nunca se
/// inventa un banco para ordenarlos junto a los demás.
List<NominaEmpleadoData> ordenarRenglonesDispersion(List<NominaEmpleadoData> renglones) {
  final ordenados = [...renglones]..sort((a, b) {
      final bancoA = (a.bancoNombre ?? '').trim();
      final bancoB = (b.bancoNombre ?? '').trim();
      if (bancoA.isEmpty != bancoB.isEmpty) return bancoA.isEmpty ? 1 : -1;
      final cmpBanco = bancoA.toLowerCase().compareTo(bancoB.toLowerCase());
      if (cmpBanco != 0) return cmpBanco;
      return a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase());
    });
  return ordenados;
}

/// Un renglón de la tabla de dispersión — snapshot puro de
/// `NominaEmpleado`, nunca una consulta en vivo contra el expediente
/// del Empleado (Etapa 15: para una Nómina ya cerrada/pagada, el dato
/// bancario correcto es el que existía al momento de generar/actualizar
/// la Nómina, no el actual — si el Empleado corrige después su cuenta
/// en Personal, el PDF de una dispersión ya realizada nunca debe
/// cambiar).
class NominaDispersionPdfRenglon {
  const NominaDispersionPdfRenglon({
    required this.numeroEmpleado,
    required this.nombreCompleto,
    required this.servicioNombre,
    required this.bancoNombre,
    required this.numeroCuentaTarjeta,
    required this.clabe,
    required this.montoFiscal,
    required this.montoNoFiscal,
    required this.totalAPagar,
  });

  final int numeroEmpleado;
  final String nombreCompleto;
  final String? servicioNombre;
  final String? bancoNombre;
  final String? numeroCuentaTarjeta;
  final String? clabe;
  final int montoFiscal;
  final int montoNoFiscal;
  final int totalAPagar;

  /// Ver [requiereVerificacionBancaria] — misma función compartida con
  /// la tabla interactiva de "Registrar pago de nómina".
  bool get requiereVerificacion =>
      requiereVerificacionBancaria(bancoNombre: bancoNombre, numeroCuentaTarjeta: numeroCuentaTarjeta, clabe: clabe);
}

/// Todos los datos, ya reunidos desde el snapshot de `Nomina`/
/// `NominaEmpleado`, para imprimir el PDF de control de dispersión
/// (Etapa 15) — puro respecto a E/S, mismo criterio que
/// `ReciboPagoPdfData`/`FichaTecnicaData`: el use case orquestador reúne
/// esto antes de invocar al renderer.
class NominaDispersionPdfData {
  const NominaDispersionPdfData({
    required this.folio,
    required this.periodoInicio,
    required this.periodoFin,
    required this.fechaPago,
    required this.estatus,
    required this.renglones,
    required this.fechaGeneracion,
  });

  final String folio;
  final DateTime periodoInicio;
  final DateTime periodoFin;
  final DateTime fechaPago;

  /// Nombre estable del enum `EstatusNomina` (`cerrada`/`pagada` — nunca
  /// `borrador`, ver `GenerarNominaDispersionPdfUseCase`).
  final String estatus;

  final List<NominaDispersionPdfRenglon> renglones;
  final DateTime fechaGeneracion;

  String get estatusLabel => _estatusLabel[estatus] ?? estatus;

  int get totalEmpleados => renglones.length;
  int get totalFiscal => renglones.fold(0, (s, r) => s + r.montoFiscal);
  int get totalNoFiscal => renglones.fold(0, (s, r) => s + r.montoNoFiscal);
  int get totalGeneral => renglones.fold(0, (s, r) => s + r.totalAPagar);
  int get totalRequierenVerificacion => renglones.where((r) => r.requiereVerificacion).length;
}

/// Reúne el snapshot de una Nómina y sus renglones en
/// [NominaDispersionPdfData], ya ordenados — Banco, luego Nombre
/// completo (Resolución: una dispersión real se procesa por lotes
/// dentro del mismo banco, así que agrupar por banco reduce el ir y
/// venir entre portales bancarios distintos; es la regla operativa más
/// útil para este documento, más que el orden interno de captura de la
/// Nómina). Los renglones sin banco (`null`/vacío) quedan al final,
/// ordenados por nombre entre sí — nunca se inventa un banco para
/// ordenarlos junto a los demás. Función pura, sin BD ni Flutter,
/// probada de forma aislada.
NominaDispersionPdfData construirNominaDispersionPdfData({
  required NominaData nomina,
  required List<NominaEmpleadoData> renglones,
  required DateTime fechaGeneracion,
}) {
  final ordenados = ordenarRenglonesDispersion(renglones);

  return NominaDispersionPdfData(
    folio: nomina.folio,
    periodoInicio: nomina.fechaInicioPeriodo,
    periodoFin: nomina.fechaFinPeriodo,
    fechaPago: nomina.fechaPagoOrdinaria,
    estatus: nomina.estatus,
    fechaGeneracion: fechaGeneracion,
    renglones: [
      for (final r in ordenados)
        NominaDispersionPdfRenglon(
          numeroEmpleado: r.numeroEmpleado,
          nombreCompleto: r.nombreCompleto,
          servicioNombre: r.servicioNombre,
          bancoNombre: r.bancoNombre,
          numeroCuentaTarjeta: r.numeroCuentaTarjeta,
          clabe: r.clabe,
          montoFiscal: r.montoFiscal,
          montoNoFiscal: r.montoNoFiscal,
          totalAPagar: r.totalAPagar,
        ),
    ],
  );
}
