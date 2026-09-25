import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'env.dart';

/// Resuelve las rutas de almacenamiento de RISEG ONE en el equipo local.
///
/// Cada entorno ([Env]) usa una carpeta de datos separada para que el
/// desarrollo nunca toque la base de datos ni los adjuntos de producción.
class AppPaths {
  AppPaths._(this._root, this.env);

  final String _root;
  final Env env;

  static Future<AppPaths> resolve(Env env) async {
    final supportDir = await getApplicationSupportDirectory();
    final folderName = env.isDev ? 'RISEGONE-dev' : 'RISEGONE';
    final root = p.join(supportDir.path, folderName);
    return AppPaths._(root, env);
  }

  /// Carpeta raíz de datos de la aplicación para este entorno.
  String get rootDir => _root;

  /// Ruta del archivo de base de datos SQLite (Drift).
  String get databaseFile => p.join(_root, 'riseg_one.sqlite');

  /// Raíz de los adjuntos (fotos, comprobantes, PDFs de resguardo, etc.)
  /// — fuente de verdad irremplazable, forma parte del respaldo (Etapa
  /// 14C).
  String get attachmentsDir => p.join(_root, 'attachments');

  /// Raíz donde se guardan los `.zip` de respaldo (Etapa 14C), tanto los
  /// creados manualmente por el Usuario Maestro como el respaldo
  /// preventivo automático que se genera antes de cada restauración.
  String get backupsDir => p.join(_root, 'backups');

  /// Raíz donde se guardan los reportes exportados (Etapa 12D) — a
  /// diferencia de [attachmentsDir], estos documentos no tienen un
  /// dueño de negocio (empleado, vehículo, compra); son generados bajo
  /// demanda desde Reportes, sin persistir ningún `Attachment`. 100%
  /// regenerables desde la base de datos, por eso quedan fuera del
  /// respaldo (Etapa 14C).
  String get reportesDir => p.join(_root, 'reportes');

  /// Raíz donde se guardan los recibos de pago generados en PDF (Etapa
  /// 15) — mismo criterio que [reportesDir]: un recibo es 100%
  /// regenerable desde el `DocumentoPorEmitir` y sus tablas hijas, así
  /// que no tiene dueño en `Attachment` ni forma parte del respaldo
  /// (Etapa 14C).
  String get recibosDir => p.join(_root, 'recibos');

  /// Raíz donde se guardan los PDF de dispersión de Nómina (Etapa 15) —
  /// mismo criterio que [reportesDir]/[recibosDir]: 100% regenerable
  /// desde `Nomina`/`NominaEmpleado` (siempre el snapshot ya guardado,
  /// nunca el dato bancario en vivo del Empleado), sin dueño en
  /// `Attachment`, fuera del respaldo (Etapa 14C).
  String get nominaDispersionDir => p.join(_root, 'nomina_dispersion');

  /// Raíz donde se guardan las Tarjetas fiscales de Empresa generadas en
  /// PDF (Etapa 16) — mismo criterio que [reportesDir]/[recibosDir]:
  /// 100% regenerable desde `Empresa`/`Direccion`/`MedioContacto`, sin
  /// dueño en `Attachment`, fuera del respaldo (Etapa 14C).
  String get datosFiscalesDir => p.join(_root, 'datos_fiscales');

  /// Carpeta de espera de una restauración validada pero aún no aplicada
  /// (Etapa 14C) — [bootstrap] revisa [restorePendingMarkerFile] antes
  /// de abrir la base de datos; si existe, sustituye [databaseFile] y
  /// [attachmentsDir] con el contenido de esta carpeta antes de
  /// continuar el arranque. Nunca se toca mientras la aplicación está
  /// en ejecución con la conexión ya abierta — ver
  /// `PrepararRestauracionUseCase`.
  String get restorePendingDir => p.join(_root, 'restore_pending');

  /// Marcador de una restauración en curso (Etapa 4B).
  ///
  /// Ya no es un simple "hay algo pendiente": guarda en qué **fase** va
  /// la aplicación, para que interrumpir la computadora a medio camino
  /// no deje a nadie adivinando qué archivos son los buenos. Ver
  /// `AplicarRestauracionPendienteUseCase`.
  String get restorePendingMarkerFile => p.join(_root, 'restore_pending.json');

  /// Dónde se aparta el estado ANTERIOR mientras se aplica una
  /// restauración (Etapa 4B).
  ///
  /// La base y los adjuntos que se están reemplazando se **mueven**
  /// aquí, nunca se borran: hasta que el arranque confirma que la base
  /// restaurada abre bien, este es el único camino de vuelta. Sólo se
  /// vacía cuando la restauración queda confirmada.
  String get restoreOldDir => p.join(_root, 'restore_old');

  /// Espacio de trabajo de la recuperación portable (Etapa 4D).
  ///
  /// Aquí vive, sólo mientras dura una operación, lo que un paquete
  /// `.risegbkp` lleva dentro una vez descifrado. Es el único punto del
  /// disco donde ese contenido aparece en claro, así que quien escribe
  /// aquí lo borra al terminar, pase lo que pase. Está separado de
  /// [restorePendingDir] a propósito: eso de allá es estado que debe
  /// sobrevivir a un reinicio; esto de aquí es basura en cuanto la
  /// operación acaba, y el arranque puede vaciarlo sin pensar.
  String get portableStagingDir => p.join(_root, 'portable_staging');
}
