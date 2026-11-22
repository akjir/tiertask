// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'TierTask';

  @override
  String get tier1Name => 'Fokus';

  @override
  String get tier2Name => 'Bereit';

  @override
  String get tier3Name => 'Geplant';

  @override
  String get tier4Name => 'Blockiert';

  @override
  String get tier5Name => 'Irgendwann';

  @override
  String get tier6Name => 'Erledigt';

  @override
  String get emptyFocusHint =>
      'Keine Aufgaben in Fokus. Neue Aufgaben aus Bereit oder Geplant rücken automatisch hierher nach.';

  @override
  String get emptyReadyHint => 'Keine Aufgaben in Bereit.';

  @override
  String get emptyPlannedHint => 'Keine Aufgaben im aktiven Backlog (Geplant).';

  @override
  String get emptyBlockedHint => 'Keine blockierten Aufgaben (Blockiert).';

  @override
  String get emptySomedayHint => 'Keine Ideen in Irgendwann gespeichert.';

  @override
  String get emptyCompletedHint =>
      'Keine erledigten Aufgaben der letzten 30 Tage.';

  @override
  String get actionClose => 'Schließen';

  @override
  String get unconfiguredBannerText =>
      'Lokaler Modus aktiv. Konfiguriere WebDAV für die Synchronisation.';

  @override
  String get actionConfigure => 'Einrichten';

  @override
  String get actionSettings => 'Einstellungen';

  @override
  String get actionRetry => 'Erneut versuchen';

  @override
  String get quickAddPriority => 'Priorität';

  @override
  String get tooltipDowngradeTask => 'Aufgabe herabstufen';

  @override
  String get taskNameLabel => 'Aufgabenname';

  @override
  String get taskNameErrorEmpty => 'Bitte einen Aufgabennamen eingeben.';

  @override
  String get taskNameErrorDuplicate =>
      'Eine Aufgabe mit diesem Namen existiert bereits.';

  @override
  String get taskNoteLabel => 'Notiz';

  @override
  String get taskNoteHint => 'Optionale Notiz oder Beschreibung...';

  @override
  String get subtasksAutoFinishLabel => 'Automatisch abschließen';

  @override
  String get subtasksSectionTitle => 'Unteraufgaben';

  @override
  String get subtaskInputHint => 'Unteraufgabe hinzufügen...';

  @override
  String get tooltipAddSubtask => 'Unteraufgabe hinzufügen';

  @override
  String get tooltipRemoveSubtask => 'Unteraufgabe entfernen';

  @override
  String get quickAddHint => 'Neue Aufgabe...';

  @override
  String get actionAdd => 'Hinzufügen';

  @override
  String get actionCancel => 'Abbrechen';

  @override
  String get actionSave => 'Speichern';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get languageSectionTitle => 'Sprache';

  @override
  String get languageSectionDescription =>
      'Anzeigesprache auswählen. System nutzt Deutsch auf deutschen Systemen und sonst Englisch.';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get themeSectionTitle => 'Erscheinungsbild';

  @override
  String get themeSectionDescription =>
      'Farbschema auswählen. System folgt der Einstellung des Betriebssystems.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get storageModeSectionTitle => 'Speichermodus';

  @override
  String get storageModeSectionDescription =>
      'Wähle aus, ob Aufgaben lokal in einer TDF-Datei, auf einem WebDAV-Server oder an beiden Orten gespeichert werden.';

  @override
  String get storageModeLocal => 'Lokal';

  @override
  String get storageModeWebDav => 'WebDAV';

  @override
  String get storageModeBoth => 'Beides';

  @override
  String get localSectionTitle => 'Lokale TDF-Datei';

  @override
  String get localSectionDescription =>
      'Speichert alle Aufgaben in einer lokalen TDF-Datei auf diesem Gerät.';

  @override
  String get localFilePathHint => 'tiertask.tdf oder t2.tdf';

  @override
  String get resolvedLocalPathLabel => 'Aufgelöster lokaler Dateipfad:';

  @override
  String get webdavSectionTitle => 'WebDAV-Synchronisation';

  @override
  String get webdavSectionDescription =>
      'TierTask speichert alle Aufgaben in einer einzigen TDF-Datei (tiertask.tdf) auf deinem WebDAV-Server. Nutze nach Möglichkeit ein eigenes App-Passwort.';

  @override
  String get serverUrlLabel => 'WebDAV Server-URL';

  @override
  String get serverUrlErrorEmpty => 'Bitte Server-URL eingeben.';

  @override
  String get usernameLabel => 'Benutzername';

  @override
  String get usernameErrorEmpty => 'Bitte Benutzername eingeben.';

  @override
  String get passwordLabel => 'App-Passwort / Passwort';

  @override
  String get tooltipShowPassword => 'Passwort anzeigen';

  @override
  String get tooltipHidePassword => 'Passwort verbergen';

  @override
  String get passwordErrorEmpty => 'Bitte Passwort oder App-Passwort eingeben.';

  @override
  String get filePathLabel => 'TDF-Dateiname / Pfad';

  @override
  String get filePathHint => 'tiertask.tdf oder t2.tdf';

  @override
  String get resolvedEndpointLabel =>
      'Aufgelöster WebDAV-Endpunkt (GET / PUT):';

  @override
  String get credentialsSavedBanner => 'Zugangsdaten lokal gespeichert.';

  @override
  String get connectionSuccessBanner =>
      'Verbindung erfolgreich. TDF-Datei wurde mit WebDAV synchronisiert.';

  @override
  String get actionTestConnectionAndSync =>
      'Verbindung testen / Jetzt synchronisieren';

  @override
  String get errorWebDavNotConfigured =>
      'Bitte zuerst WebDAV in den Einstellungen konfigurieren.';

  @override
  String get errorInvalidServerUrl => 'Ungültige WebDAV-Server-URL.';

  @override
  String get errorAuthFailedLoad =>
      'Authentifizierung fehlgeschlagen. Bitte Benutzername und App-Passwort prüfen.';

  @override
  String get errorLoadMarkdownFailed =>
      'Fehler beim Laden der TDF-Datei vom Server.';

  @override
  String errorNetworkUnreachable(String details) {
    return 'Netzwerkfehler: Server nicht erreichbar ($details).';
  }

  @override
  String get errorTimeoutLoad =>
      'Zeitüberschreitung bei der Verbindung zum WebDAV-Server.';

  @override
  String errorTlsLoad(String details) {
    return 'TLS/SSL-Verbindungsfehler: $details';
  }

  @override
  String errorUnexpectedLoad(String details) {
    return 'Unerwarteter WebDAV-Fehler beim Laden: $details';
  }

  @override
  String get errorAuthFailedSave =>
      'Authentifizierung beim Speichern fehlgeschlagen. Bitte App-Passwort prüfen.';

  @override
  String get errorSaveMarkdownFailed =>
      'Fehler beim Speichern der TDF-Datei auf dem Server.';

  @override
  String errorNetworkSave(String details) {
    return 'Netzwerkfehler beim Speichern ($details).';
  }

  @override
  String get errorTimeoutSave =>
      'Zeitüberschreitung beim Speichern auf dem WebDAV-Server.';

  @override
  String errorTlsSave(String details) {
    return 'TLS/SSL-Fehler beim Speichern: $details';
  }

  @override
  String errorUnexpectedSave(String details) {
    return 'Unerwarteter WebDAV-Fehler beim Speichern: $details';
  }

  @override
  String get errorInvalidLocalFilePath =>
      'Ungültiger lokaler TDF-Dateiname oder Pfad.';

  @override
  String get errorLocalFileTooLarge =>
      'Die TDF-Datei überschreitet die maximal zulässige Größe.';

  @override
  String errorLoadLocalFileFailed(String details) {
    return 'Fehler beim Lesen der lokalen TDF-Datei ($details).';
  }

  @override
  String errorSaveLocalFileFailed(String details) {
    return 'Fehler beim Schreiben der lokalen TDF-Datei ($details).';
  }

  @override
  String get tooltipMenu => 'Menü öffnen';

  @override
  String get tooltipSearch => 'Aufgaben suchen';

  @override
  String get searchHint => 'Aufgaben durchsuchen...';

  @override
  String get drawerLabels => 'Labels';

  @override
  String get labelNameHint => 'Neuer Labelname...';

  @override
  String get emptyLabelsHint => 'Noch keine Labels angelegt.';

  @override
  String get tooltipDeleteLabel => 'Label löschen';

  @override
  String get actionEdit => 'Bearbeiten';

  @override
  String get taskSuspendedLabel => 'Zurückgestellt';

  @override
  String get taskSuspendedUntilLabel => 'Zurückgestellt bis (optional)';

  @override
  String get taskSuspendedErrorInvalid =>
      'Bitte einen gültigen Zeitstempel eingeben (JJJJ-MM-TT oder JJJJ-MM-TT HH:MM).';

  @override
  String get taskSuspendedDisablesConditionsHint =>
      'Zurückgestellt ist aktiv: Die Auswertung aller anderen Bedingungen ist deaktiviert und diese Aufgabe erscheint unter Blockiert.';

  @override
  String get conditionGlobalAnyLabel =>
      'Beliebig (Label-Bedingungen ignorieren)';

  @override
  String get conditionDayGroupTitle => 'Wochentage';

  @override
  String get conditionDayAnyLabel => 'Jeder Tag';

  @override
  String get weekdayMon => 'Mo';

  @override
  String get weekdayTue => 'Di';

  @override
  String get weekdayWed => 'Mi';

  @override
  String get weekdayThu => 'Do';

  @override
  String get weekdayFri => 'Fr';

  @override
  String get weekdaySat => 'Sa';

  @override
  String get weekdaySun => 'So';

  @override
  String get conditionTimeGroupTitle => 'Zeitfenster';

  @override
  String get conditionTimeAnyLabel => 'Jede Uhrzeit';

  @override
  String get conditionTimeStartHint => 'Start (HH:MM)';

  @override
  String get conditionTimeEndHint => 'Ende (HH:MM)';

  @override
  String get conditionTimeErrorInvalid =>
      'Bitte gültige 24-Stunden-Zeiten eingeben (HH:MM).';

  @override
  String get tooltipAddTimeCondition => 'Zeitfenster hinzufügen';

  @override
  String get tooltipRemoveTimeCondition => 'Zeitfenster entfernen';

  @override
  String get conditionLocationGroupTitle => 'Standorte (GPS)';

  @override
  String get conditionLocationAnyLabel => 'Jeder Standort';

  @override
  String get conditionLocationErrorInvalid =>
      'Bitte gültigen Breitengrad, Längengrad und Radius eingeben (z. B. 200m oder 1.5km).';

  @override
  String get taskLabelsSectionTitle => 'Labels';

  @override
  String get taskBlockedBySectionTitle => 'Voraussetzungen';

  @override
  String get taskBlockedBySectionDescription =>
      'Suche nach offenen Aufgaben anhand des Namens und wähle Aufgaben aus, die zuerst erledigt sein müssen.';

  @override
  String get blockedBySearchHint => 'Aufgaben nach Namen suchen...';

  @override
  String get blockedBySearchNoResults => 'Keine passenden Aufgaben gefunden.';

  @override
  String get tooltipClearSearch => 'Suche löschen';

  @override
  String get taskConditionsSectionTitle => 'Aktivierungsbedingungen';

  @override
  String get tooltipPickDate => 'Datum auswählen';

  @override
  String get tooltipPickTime => 'Uhrzeit auswählen';

  @override
  String get themePaletteSectionTitle => 'Farbpalette';

  @override
  String get themePaletteSectionDescription =>
      'Material-3-Farbpalette für Oberflächen und Hervorhebungen auswählen.';

  @override
  String get timeZoneSectionTitle => 'Zeitzone';

  @override
  String get timeZoneSectionDescription =>
      'Wählen Sie, ob die lokale Zeitzone automatisch vom Gerät übernommen oder manuell für Aufgabenbedingungen und Anzeige festgelegt wird.';

  @override
  String get timeZoneModeAutomatic => 'Automatisch';

  @override
  String get timeZoneModeManual => 'Manuell';

  @override
  String get timeZoneOffsetLabel => 'UTC-Verschiebung';

  @override
  String get repeatFlagLabel => 'Wiederholen';

  @override
  String get repeatIntervalLabel => 'Wiederhole alle';

  @override
  String get repeatUnitDays => 'Tage';

  @override
  String get repeatUnitWeeks => 'Wochen';

  @override
  String get repeatUnitMonths => 'Monate';

  @override
  String get repeatErrorInvalid =>
      'Bitte ein Intervall zwischen 1 und 3650 eingeben.';

  @override
  String get tooltipClearInput => 'Text löschen';

  @override
  String get localDirectoryMovedBanner =>
      'Lokales TDF-Verzeichnis geändert und Datei verschoben.';

  @override
  String errorMoveTargetFileExists(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Am Zielpfad existiert bereits eine Datei ($path).';
  }

  @override
  String errorMoveTargetDirectoryExists(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Am Zielpfad existiert bereits ein Ordner mit diesem Namen ($path).';
  }

  @override
  String errorMoveTargetSymlinkExists(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Am Zielpfad existiert bereits ein symbolischer Link ($path).';
  }

  @override
  String errorMoveSourceIsSymlink(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Der Quellpfad ist ein symbolischer Link ($path).';
  }

  @override
  String errorMoveSourceIsDirectory(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Der Quellpfad ist ein Ordner ($path).';
  }

  @override
  String errorMoveTargetDirectoryNotFound(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Das Zielverzeichnis existiert nicht ($path).';
  }

  @override
  String errorMoveTargetNotADirectory(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Der ausgewählte Zielpfad ist kein Ordner ($path).';
  }

  @override
  String errorMovePermissionDenied(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Keine Berechtigung ($path).';
  }

  @override
  String errorMoveReadOnlyFileSystem(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Das Dateisystem ist schreibgeschützt ($path).';
  }

  @override
  String errorMoveDiskFull(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Nicht genügend freier Speicherplatz ($path).';
  }

  @override
  String errorMoveFileLocked(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Die Datei ist gesperrt oder wird von einem anderen Prozess verwendet ($path).';
  }

  @override
  String errorMovePathTooLong(String path) {
    return 'TDF-Datei kann nicht verschoben werden: Der Dateipfad oder Dateiname ist zu lang ($path).';
  }

  @override
  String errorMoveLocalFileFailed(String details) {
    return 'TDF-Datei kann nicht verschoben werden ($details).';
  }

  @override
  String get errorDuplicateWorkspaceFilePath =>
      'Ein anderer Arbeitsbereich verwendet diesen TDF-Dateipfad bereits.';

  @override
  String get tooltipManageWorkspaces =>
      'Arbeitsbereich wechseln oder verwalten';

  @override
  String get workspacesDialogTitle => 'Arbeitsbereiche';

  @override
  String get workspacesDialogDescription =>
      'Wechsle zwischen isolierten Aufgabenbereichen oder erstelle einen neuen Arbeitsbereich mit eigener TDF-Datei.';

  @override
  String get workspaceActiveBadge => 'Aktiv';

  @override
  String get createWorkspaceHint => 'Neuer Arbeitsbereich...';

  @override
  String workspaceSuggestedFileLabel(String fileName) {
    return 'TDF-Datei: $fileName';
  }

  @override
  String get tooltipCreateWorkspace => 'Arbeitsbereich erstellen';

  @override
  String get tooltipRenameWorkspace => 'Arbeitsbereich umbenennen';

  @override
  String get tooltipDeleteWorkspace => 'Arbeitsbereich löschen';

  @override
  String deleteWorkspaceConfirmMessage(String name) {
    return 'Arbeitsbereich „$name“ entfernen? Die TDF-Datei wird nicht gelöscht.';
  }

  @override
  String get actionDelete => 'Löschen';

  @override
  String get errorWorkspaceNameEmpty =>
      'Bitte einen gültigen Namen eingeben (1–128 Zeichen).';

  @override
  String get errorWorkspaceNameDuplicate =>
      'Ein Arbeitsbereich mit diesem Namen existiert bereits.';

  @override
  String get errorWorkspaceCannotDeleteLast =>
      'Der letzte verbleibende Arbeitsbereich kann nicht gelöscht werden.';

  @override
  String get errorWorkspaceMaxExceeded =>
      'Die maximale Anzahl an Arbeitsbereichen (32) ist erreicht.';

  @override
  String get locationSectionTitle => 'Standortbestimmung';

  @override
  String get locationSectionDescription =>
      'Bestimmt den aktuellen Ort und die GPS-Koordinaten, solange die App läuft, um Standortbedingungen auszuwerten.';

  @override
  String get locationOff => 'Aus';

  @override
  String get locationOn => 'An';

  @override
  String get tooltipLocationStatus => 'Standortstatus';

  @override
  String get locationDialogTitle => 'Standortstatus';

  @override
  String get locationStatusSearching => 'Standort wird gesucht...';

  @override
  String get locationStatusFound => 'Standort gefunden';

  @override
  String get locationStatusUnavailable =>
      'Keine Standortinformationen verfügbar';

  @override
  String get locationPlaceLabel => 'Ort';

  @override
  String get locationCoordinatesLabel => 'GPS-Koordinaten';

  @override
  String get locationPlaceUnknown => 'Unbekannter Ort';

  @override
  String get locationSourceLabel => 'Quelle';

  @override
  String get locationSourceGps => 'GPS';

  @override
  String get locationSourceSystem => 'System / Netzwerk';

  @override
  String get locationSourceInternet => 'Internet (GeoIP)';

  @override
  String get actionRefresh => 'Aktualisieren';

  @override
  String get labelNameLabel => 'Labelname';

  @override
  String get labelNameErrorEmpty => 'Bitte einen Labelnamen eingeben.';

  @override
  String get labelNameErrorDuplicate =>
      'Ein Label mit diesem Namen existiert bereits.';

  @override
  String get labelColorSectionTitle => 'Farbe';

  @override
  String get labelColorHint => '#RRGGBB (optional)';

  @override
  String get labelColorErrorInvalid =>
      'Bitte eine gültige Hex-Farbe eingeben (#RRGGBB).';

  @override
  String get labelConditionsSectionDescription =>
      'Schränke ein, wann und wo Aufgaben mit diesem Label standardmäßig aktiv sind.';

  @override
  String get linksSectionTitle => 'Links';

  @override
  String get linkTitleHint => 'Link-Titel (z. B. Dokumentation)';

  @override
  String get linkUriHint => 'URI (z. B. https://example.com)';

  @override
  String get tooltipAddLink => 'Link hinzufügen';

  @override
  String get tooltipRemoveLink => 'Link entfernen';

  @override
  String get tooltipOpenLink => 'Link öffnen';

  @override
  String get tooltipIndicatorNote => 'Notiz';

  @override
  String get linkErrorInvalid =>
      'Bitte sowohl einen Link-Titel als auch eine gültige URI mit Schema eingeben (z. B. https://...).';

  @override
  String get linkErrorMaxExceeded => 'Maximal 20 Links pro Aufgabe erreicht.';

  @override
  String get errorOpenLinkFailed => 'Link konnte nicht geöffnet werden.';

  @override
  String get diagnosticsSectionTitle => 'Diagnoseprotokoll aktivieren';

  @override
  String get diagnosticsSectionDescription =>
      'Zeichnet Laufzeitereignisse auf und sichert Absturzprotokolle lokal in tiertask.log zur Fehlersuche.';

  @override
  String get diagnosticLogButton => 'Diagnoseprotokoll';

  @override
  String get diagnosticLogTitle => 'Diagnoseprotokoll';

  @override
  String get emptyLogHint =>
      'Noch keine Einträge im Diagnoseprotokoll vorhanden.';

  @override
  String get tooltipCopyLog => 'Alles kopieren';

  @override
  String get logCopiedSnackBar =>
      'Diagnoseprotokoll in die Zwischenablage kopiert.';

  @override
  String get logClearedSnackBar => 'Diagnoseprotokoll geleert.';

  @override
  String get actionWipeLocalFile => 'Lokale TDF-Datei zurücksetzen';

  @override
  String get actionWipeRemoteFile => 'Remote-TDF-Datei zurücksetzen';

  @override
  String get wipeLocalDialogTitle => 'Lokale TDF-Datei zurücksetzen';

  @override
  String get wipeRemoteDialogTitle => 'Remote-TDF-Datei zurücksetzen';

  @override
  String wipeLocalDialogDescription(String fileName, String baseName) {
    return 'Dadurch wird die lokale Datei „$fileName“ geleert und als leeres TDF-Dokument neu angelegt. Zur Bestätigung „$baseName“ (Dateiname ohne .tdf) eingeben.';
  }

  @override
  String wipeRemoteDialogDescription(String fileName, String baseName) {
    return 'Dadurch wird die Remote-WebDAV-Datei „$fileName“ geleert und als leeres TDF-Dokument neu angelegt. Zur Bestätigung „$baseName“ (Dateiname ohne .tdf) eingeben.';
  }

  @override
  String get wipeConfirmInputLabel => 'Dateiname ohne .tdf';

  @override
  String get wipeCreateBackupLabel =>
      'Sicherungskopie (.bak / .bak.001+) anlegen, falls Datei vorhanden ist';

  @override
  String get actionWipeConfirm => 'Datei zurücksetzen';

  @override
  String get localFileWipedBanner =>
      'Lokale TDF-Datei wurde geleert und neu angelegt.';

  @override
  String get remoteFileWipedBanner =>
      'Remote-TDF-Datei auf WebDAV wurde geleert und neu angelegt.';

  @override
  String get actionSelectLocalFile => 'Auswählen';

  @override
  String get actionMoveLocalFile => 'Verschieben';

  @override
  String get actionRenameLocalFile => 'Umbenennen';

  @override
  String get selectLocalDialogTitle =>
      'Lokale TDF-Datei auswählen oder neu anlegen';

  @override
  String get selectLocalDialogDescription =>
      'Wähle eine vorhandene TDF-Datei im Speicherverzeichnis aus oder gib einen neuen Dateinamen ein.';

  @override
  String get renameLocalDialogTitle => 'Lokale TDF-Datei umbenennen';

  @override
  String renameLocalDialogDescription(String fileName) {
    return 'Gib einen neuen Dateinamen für „$fileName“ im aktuellen Verzeichnis ein.';
  }

  @override
  String get localFileNameInputLabel => 'Dateiname (.tdf)';

  @override
  String get localFileNameErrorInvalid =>
      'Bitte einen gültigen Dateinamen ohne Pfadtrennzeichen eingeben.';

  @override
  String get localFileSelectedBanner => 'Lokale TDF-Datei ausgewählt.';

  @override
  String get localFileRenamedBanner => 'Lokale TDF-Datei umbenannt.';

  @override
  String get logLevelLabel => 'Minimales Protokoll-Level';

  @override
  String get logLevelDebug => 'Debug';

  @override
  String get logLevelInfo => 'Info';

  @override
  String get logLevelWarn => 'Warnung';

  @override
  String get logLevelError => 'Fehler';

  @override
  String get logStorageLabel => 'Protokollspeicher';

  @override
  String get logStorageLocal => 'Lokal';

  @override
  String get logStorageWebDav => 'WebDAV';

  @override
  String get logStorageBoth => 'Beide';

  @override
  String logMetadataFile(String fileName) {
    return 'Datei: $fileName';
  }

  @override
  String logMetadataStats(String entries, String warnings, String errors) {
    return 'Einträge: $entries | Warnungen: $warnings | Fehler: $errors';
  }

  @override
  String get logFilterAllTags => 'Alle';

  @override
  String get logSyncedSnackBar =>
      'Diagnoseprotokoll mit WebDAV synchronisiert.';

  @override
  String get tooltipPickCustomColor => 'Individuelle Farbe wählen';

  @override
  String get labelColorPickerDialogTitle => 'Individuelle Farbe wählen';

  @override
  String get labelColorBrightnessLabel => 'Helligkeit';

  @override
  String get actionSelectColor => 'Auswählen';

  @override
  String get tooltipTaskEditorAutoFinish =>
      'Schließt die gesamte Aufgabe automatisch ab, sobald alle Unteraufgaben abgehakt sind.';

  @override
  String get drawerLocations => 'Orte';

  @override
  String get emptyLocationsHint => 'Noch keine Orte erstellt.';

  @override
  String get tooltipDeleteLocation => 'Ort löschen';

  @override
  String get locationNameLabel => 'Ortsname';

  @override
  String get locationCoordinatesSectionTitle => 'Koordinaten & Radius';

  @override
  String get locationLatitudeLabel => 'Breitengrad (-90 bis 90)';

  @override
  String get locationLongitudeLabel => 'Längengrad (-180 bis 180)';

  @override
  String get locationRadiusLabel => 'Radius (m/km)';

  @override
  String get locationUseCurrentGpsButton => 'Aktuelle GPS-Position übernehmen';

  @override
  String get locationNameErrorEmpty => 'Bitte einen Ortsnamen eingeben.';

  @override
  String get locationSourceErrorEmpty =>
      'Bitte eine gültige Quelle eingeben oder leer lassen.';

  @override
  String get locationCoordinatesErrorInvalid =>
      'Gültigen Breitengrad (-90..90) und Längengrad (-180..180) eingeben.';

  @override
  String get locationRadiusErrorInvalid =>
      'Gültigen Radius zwischen 0,01m und 100km eingeben.';

  @override
  String get labelScopedSectionTitle => 'Board-Fokus';

  @override
  String get labelScopedSwitchSubtitle =>
      'Aufgaben mit diesem Label ausblenden, solange dieser Filter nicht aktiv ist.';

  @override
  String get taskDueButtonLabel => 'Fällig am (optional)';

  @override
  String pillDuePrefix(String date) {
    return 'Fällig: $date';
  }

  @override
  String get locationSourceTypeLabel => 'Quellentyp';

  @override
  String get locationSourceTypeGps => 'GPS-Koordinaten';

  @override
  String get locationSourceTypeAddress => 'Adresse';

  @override
  String get locationSourceTypePlusCode => 'Google Plus Code';

  @override
  String get locationSourceAddressHint => 'Straße, PLZ, Ort';

  @override
  String get locationSourcePlusCodeHint =>
      'z. B. 9F2PXXH7+F4 oder XXH7+F4 Erfurt';

  @override
  String get locationResolveButton => 'Auflösen';

  @override
  String get locationSelectCandidateTitle => 'Ort auswählen';

  @override
  String get locationResolveErrorNotFound =>
      'Adresse oder Plus Code konnte nicht aufgelöst werden.';

  @override
  String get locationResolveErrorInvalidPlusCode =>
      'Gültigen Plus Code eingeben (z. B. 9F2PXXH7+F4 oder XXH7+F4 Erfurt).';

  @override
  String get tooltipIndicatorConditions => 'Aktivierungsbedingungen';

  @override
  String get taskInfoSuspendedForever => 'Unbegrenzt';

  @override
  String taskInfoSuspendedUntil(String timestamp, String duration) {
    return 'Bis $timestamp ($duration)';
  }

  @override
  String get taskInfoDueLabel => 'Fällig';

  @override
  String taskInfoDueAt(String timestamp, String duration) {
    return '$timestamp ($duration)';
  }

  @override
  String taskInfoDueOverdue(String timestamp) {
    return 'Überfällig ($timestamp)';
  }

  @override
  String taskInfoDurationDaysHours(String days, String hours) {
    return 'noch $days T. $hours Std.';
  }

  @override
  String taskInfoDurationHoursMinutes(String hours, String minutes) {
    return 'noch $hours Std. $minutes Min.';
  }

  @override
  String taskInfoDurationMinutes(String minutes) {
    return 'noch $minutes Min.';
  }

  @override
  String taskInfoSubtasksProgress(String completed, String total) {
    return '$completed von $total erledigt';
  }

  @override
  String get taskInfoSubtasksAutoFinishSuffix =>
      'Automatisch abschließen aktiv';

  @override
  String taskInfoBlockedByProgress(String satisfied, String total) {
    return '$satisfied von $total erfüllt';
  }

  @override
  String taskInfoRepeatEvery(String count, String unit) {
    return 'Alle $count $unit';
  }

  @override
  String taskInfoRepeatCompletions(String count) {
    return '$count-mal abgeschlossen';
  }

  @override
  String taskInfoLinksCount(String count) {
    return '$count Links';
  }

  @override
  String get tooltipCopyNote => 'Notiz kopieren';

  @override
  String get noteCopiedSnackBar => 'Notiz in die Zwischenablage kopiert.';

  @override
  String get actionUndo => 'Rückgängig';

  @override
  String taskCompletedUndoSnackBar(String title) {
    return '„$title“ abgeschlossen.';
  }

  @override
  String taskDowngradedUndoSnackBar(String title) {
    return '„$title“ herabgestuft.';
  }

  @override
  String taskDeletedUndoSnackBar(String title) {
    return '„$title“ gelöscht.';
  }

  @override
  String get localWatchLabel => 'Externe Dateiänderungen überwachen';

  @override
  String get localWatchDescription =>
      'Änderungen durch externe Editoren, Skripte oder Datei-Synchronisation automatisch zusammenführen.';

  @override
  String taskIdRowLabel(String id) {
    return 'ID: $id';
  }

  @override
  String get tooltipCopyTaskId => 'Aufgaben-ID kopieren';

  @override
  String get taskIdCopiedSnackBar =>
      'Aufgaben-ID in die Zwischenablage kopiert.';

  @override
  String get labelLinkErrorMaxExceeded =>
      'Maximal 20 Links pro Label erreicht.';

  @override
  String get tooltipCancelEditLink => 'Link-Bearbeitung abbrechen';

  @override
  String get tooltipEditLink => 'Link bearbeiten';

  @override
  String get tooltipMoveLinkDown => 'Link nach unten verschieben';

  @override
  String get tooltipMoveLinkUp => 'Link nach oben verschieben';

  @override
  String get tooltipSaveLink => 'Link aktualisieren';

  @override
  String get dueLeadWindowSectionTitle => 'Fälligkeits-Priorisierung';

  @override
  String get dueLeadWindowSectionDescription =>
      'Geplante offene Aufgaben bei nahender Fälligkeit automatisch für Fokus und Bereit priorisieren.';

  @override
  String get dueLeadWindowLabel => 'Vorlaufzeit';

  @override
  String get dueLeadWindowOff => 'Aus (nie automatisch priorisieren)';

  @override
  String get dueLeadWindowAtDue => 'Bei Fälligkeit (0 Stunden)';

  @override
  String get dueLeadWindow12Hours => '12 Stunden vor Fälligkeit';

  @override
  String get dueLeadWindow24Hours => '24 Stunden vor Fälligkeit (Standard)';

  @override
  String get dueLeadWindow48Hours => '48 Stunden vor Fälligkeit';

  @override
  String get dueLeadWindow7Days => '7 Tage vor Fälligkeit';

  @override
  String get dueLeadWindowShort12Hours => '12 Std.';

  @override
  String get dueLeadWindowShort24Hours => '24 Std.';

  @override
  String get dueLeadWindowShort48Hours => '48 Std.';

  @override
  String get dueLeadWindowShort7Days => '7 Tg.';

  @override
  String get taskDueAutoPrioritizeLabel =>
      'Bei nahender Fälligkeit priorisieren';

  @override
  String get taskDueAutoPrioritizeSubtitle =>
      'Ab Beginn der Vorlaufzeit vor reguläre Aufgaben ziehen.';

  @override
  String get taskInfoDueAutoPromotedActive =>
      'Durch Fälligkeits-Vorlaufzeit priorisiert';

  @override
  String get taskInfoDueAutoPromoteAtDue =>
      'Automatische Priorisierung bei Fälligkeit';

  @override
  String taskInfoDueAutoPromoteScheduled(String window) {
    return 'Automatische Priorisierung $window vor Fälligkeit';
  }

  @override
  String get taskInfoDuePassiveHint =>
      'Informativer Termin (Auto-Priorität aus)';

  @override
  String get taskInfoDueLeadWindowOffHint =>
      'Fälligkeits-Priorisierung in Einstellungen deaktiviert';

  @override
  String get taskSuspendedNoteLabel => 'Zurückstellungsnotiz (optional)';

  @override
  String get taskSuspendedNoteHint => 'Warum ist diese Aufgabe zurückgestellt?';

  @override
  String get taskDueNoteLabel => 'Fälligkeitsnotiz (optional)';

  @override
  String get taskDueNoteHint => 'Fristdetails oder Abgabebedingungen';

  @override
  String get schedulingNoteErrorTooLong =>
      'Notiz darf maximal 2.000 Zeichen lang sein.';

  @override
  String get schedulingNoteErrorInvalid =>
      'Notiz enthält nicht unterstützte Steuerzeichen.';

  @override
  String get repeatLeadDaysLabel => 'Vorbereitungszeit (Tage, optional)';

  @override
  String get repeatLeadDaysHint => '0 (sofort nach Wiederholung aktivieren)';

  @override
  String get repeatLeadDaysErrorInvalid =>
      'Ganze Zahl zwischen 0 und 3650 Tagen eingeben.';

  @override
  String taskInfoRepeatLeadDays(String days) {
    return 'Vorbereitungsfenster öffnet $days Tag(e) vor Fälligkeit';
  }

  @override
  String get historySectionTitle => 'Verlauf';

  @override
  String get historyEmptyHint => 'Noch keine Verlaufseinträge vorhanden.';

  @override
  String get historyEntryTextLabel => 'Verlaufseintrag';

  @override
  String get historyEntryTextHint => 'Fortschritt oder Notiz erfassen';

  @override
  String get historyTimestampLabel => 'Zeitstempel (optional, Standard: jetzt)';

  @override
  String get historyTimestampHint => 'JJJJ-MM-TT Std:Min';

  @override
  String get tooltipAddHistoryEntry => 'Verlaufseintrag hinzufügen';

  @override
  String get tooltipEditHistoryEntry => 'Verlaufseintrag bearbeiten';

  @override
  String get tooltipSaveHistoryEntry => 'Verlaufseintrag aktualisieren';

  @override
  String get tooltipCancelEditHistoryEntry => 'Bearbeitung abbrechen';

  @override
  String get tooltipDeleteHistoryEntry => 'Verlaufseintrag löschen';

  @override
  String get historyErrorTextEmpty => 'Bitte einen Verlaufstext eingeben.';

  @override
  String get historyErrorTextTooLong =>
      'Verlaufseintrag darf maximal 500 Zeichen lang sein.';

  @override
  String get historyErrorTextInvalid =>
      'Verlaufseintrag enthält nicht unterstützte Steuerzeichen.';

  @override
  String get historyErrorTimestampInvalid =>
      'Gültiges Datum (JJJJ-MM-TT) und optionale Uhrzeit (Std:Min) eingeben.';

  @override
  String get historyErrorMaxExceeded =>
      'Maximal 500 Verlaufseinträge pro Aufgabe erreicht.';

  @override
  String get syncConflictDeletionBanner =>
      'Synchronisierung pausiert: Eine gleichzeitige Bearbeitung steht im Konflikt mit einer Löschung.';

  @override
  String get syncConflictRecoveryBanner =>
      'Synchronisierung pausiert: Lokale Änderungen erfordern eine Wiederherstellung nach Fortschreiten der Synchronisierungshistorie.';

  @override
  String get syncErrorGenerationRollbackBanner =>
      'Synchronisierung gestoppt: Die Synchronisierungsgeneration der gemeinsamen Datei ist älter als der bestätigte Stand.';

  @override
  String taskInfoDueAnchorDetail(String anchor) {
    return 'Terminanker: $anchor';
  }

  @override
  String get fileReadErrorTitle => 'Datei-Lesefehler';

  @override
  String get fileReadTargetLocal => 'Lokale Datei';

  @override
  String get fileReadTargetRemote => 'Remote-Datei';

  @override
  String get fileReadStatusOk => 'OK';

  @override
  String get fileReadStatusUnreadable => 'Nicht lesbar';

  @override
  String get fileReadSummaryLocalOnly =>
      'Die lokale Datei konnte nicht gelesen werden.';

  @override
  String get fileReadSummaryRemoteOnly =>
      'Die Remote-Datei konnte nicht gelesen werden.';

  @override
  String get fileReadSummaryLocalFailedRemoteOk =>
      'Nur die lokale Datei konnte nicht gelesen werden. Die Remote-Datei ist intakt.';

  @override
  String get fileReadSummaryRemoteFailedLocalOk =>
      'Nur die Remote-Datei konnte nicht gelesen werden. Die lokale Datei ist intakt.';

  @override
  String get fileReadSummaryBothFailed =>
      'Die lokale Datei und die Remote-Datei konnten nicht gelesen werden.';

  @override
  String fileReadReasonUnsupportedVersion(String version) {
    return 'Nicht unterstützte TDF-Version $version (erwartet: 0.8.0).';
  }

  @override
  String fileReadReasonTdfFormat(String line, String details) {
    return 'Formatfehler (Zeile $line): $details';
  }

  @override
  String fileReadStatusEntryLine(String target, String status) {
    return '$target: $status';
  }

  @override
  String get errorSettingsCorrupt =>
      'Anwendungseinstellungen konnten nicht gelesen werden.';

  @override
  String get errorSettingsUnsupportedVersion =>
      'Die Einstellungen wurden von einer neueren TierTask-Version erstellt. Aktualisiere TierTask, um Datenverlust zu vermeiden.';

  @override
  String get errorSettingsCredentialStorageUnavailable =>
      'Sicherer Anmeldedatenspeicher ist nicht verfügbar. Das WebDAV-Passwort konnte nicht gespeichert werden.';

  @override
  String get errorSettingsSaveFailed =>
      'Anwendungseinstellungen konnten nicht gespeichert werden.';

  @override
  String get settingsRecoveredFromBackupNotice =>
      'Einstellungen wurden nach einem Dateifehler aus der Sicherung wiederhergestellt.';

  @override
  String get settingsResetAfterQuarantineNotice =>
      'Beschädigte Einstellungen wurden gesichert und auf Standardwerte zurückgesetzt.';

  @override
  String get themePaletteCalm => 'Calm';

  @override
  String get themePalettePlumUmber => 'Plum Umber';

  @override
  String get devBuildBadge => 'DEV';

  @override
  String get tierFocusSubtitle =>
      'Drei aktive Aufgaben. Ein klarer nächster Schritt.';

  @override
  String get tierReadySubtitle =>
      'Bis zu fünf Aufgaben, die als Nächstes in den Fokus nachrücken.';

  @override
  String get tierPlannedSubtitle =>
      'Aktive Warteschlange, die Bereit automatisch nachfüllt.';

  @override
  String get tierBlockedSubtitle =>
      'Zurückgestellt oder durch Voraussetzungen und Bedingungen blockiert.';

  @override
  String get tierSomedaySubtitle =>
      'Außerhalb der aktiven Warteschlange gesammelt.';

  @override
  String get tierCompletedSubtitle =>
      'Erledigte Aufgaben werden 30 Tage (UTC) aufbewahrt.';

  @override
  String get sectionTasksTitle => 'Aufgaben';

  @override
  String get sectionToolsTitle => 'Werkzeuge';

  @override
  String get allTasksLabel => 'Alle Aufgaben';

  @override
  String get activeFilterClearTooltip => 'Filter entfernen (Alle Aufgaben)';

  @override
  String get actionBackToTasks => 'Zurück zu den Aufgaben';

  @override
  String get actionBackToSearch => 'Zurück zur Suche';

  @override
  String get actionDismiss => 'Ausblenden';

  @override
  String get actionResolveConflict => 'Konflikt lösen';

  @override
  String get actionResolveRecovery => 'Wiederherstellung öffnen';

  @override
  String get actionComplete => 'Abschließen';

  @override
  String get actionRestore => 'Wiederherstellen';

  @override
  String get actionCopy => 'Kopieren';

  @override
  String get searchViewTitle => 'Alle Aufgaben';

  @override
  String get searchViewSubtitle =>
      'Suche über alle sechs Tiers im aktiven Kontext.';

  @override
  String get searchEmptyHint => 'Keine passenden Aufgaben gefunden.';

  @override
  String get searchCloseTooltip => 'Suche schließen';

  @override
  String get loadingBoardTitle => 'Arbeitsbereich wird geladen...';

  @override
  String get loadingBoardSubtitle =>
      'TDF-Dokument wird gelesen und auf sechs Tiers ausgewertet.';

  @override
  String get sidebarFilterLabelsPlaceholder => 'Labels filtern...';

  @override
  String get sidebarFilterLabelsEmpty => 'Keine passenden Labels.';

  @override
  String get sidebarFilterLabelsToggle => 'Labels filtern';

  @override
  String get sidebarManageLabels => 'Labels verwalten';

  @override
  String get sidebarCollapseLabels => 'Labels einklappen';

  @override
  String get sidebarExpandLabels => 'Labels ausklappen';

  @override
  String get sidebarFilterLocationsPlaceholder => 'Orte filtern...';

  @override
  String get sidebarFilterLocationsEmpty => 'Keine passenden Orte.';

  @override
  String get sidebarFilterLocationsToggle => 'Orte filtern';

  @override
  String get sidebarManageLocations => 'Orte verwalten';

  @override
  String get sidebarCollapseLocations => 'Orte einklappen';

  @override
  String get sidebarExpandLocations => 'Orte ausklappen';

  @override
  String get openLabelInManagerTooltip =>
      'Label in Verwaltung öffnen und ausklappen';

  @override
  String get openLocationInManagerTooltip =>
      'Ort in Verwaltung öffnen und ausklappen';

  @override
  String get syncStatusLocalOnly => 'Nur lokal';

  @override
  String get syncStatusSynced => 'Aktuell';

  @override
  String get syncStatusSyncing => 'Synchronisiert...';

  @override
  String get syncStatusConflict => 'Konflikt';

  @override
  String get syncStatusError => 'Sync-Fehler';

  @override
  String get rawTdfPreviewTitle => 'TDF-Quelltext';

  @override
  String get rawTdfPreviewSubtitle =>
      'Kanonische, zeilenweise LF-Serialisierung des aktuellen Boards.';

  @override
  String rawTdfStatsSummary(String bytes, String lines) {
    return '$bytes Bytes / 1 MiB · $lines Zeilen / 16.384 max';
  }

  @override
  String get rawTdfCopiedNotice =>
      'TDF-Dokument in die Zwischenablage kopiert.';

  @override
  String get rawTdfLimitExceededTitle => 'Vorschau-Limit überschritten';

  @override
  String get rawTdfLimitExceededDescription =>
      'Das serialisierte TDF-Dokument überschreitet das kanonische 1-MiB- oder 16.384-Zeilen-Limit (TDF 0.8.0 Abschnitt 6.2) und kann nicht direkt angezeigt werden.';

  @override
  String badgeMoreIndicators(String count) {
    return '+$count weitere';
  }

  @override
  String get badgeAutoPriority => 'Fällig · Priorisiert';

  @override
  String badgeOverduePrefix(String date) {
    return 'Überfällig: $date';
  }

  @override
  String badgeSuspendedUntil(String date) {
    return 'Zurückgestellt bis $date';
  }

  @override
  String get badgeSuspendedForever => 'Unbegrenzt zurückgestellt';

  @override
  String badgeBlockedByProgress(String done, String total) {
    return '$done/$total Voraussetzungen';
  }

  @override
  String badgeStepsProgress(String done, String total) {
    return '$done/$total Schritte';
  }

  @override
  String get badgeLinkSingular => '1 Link';

  @override
  String badgeHistoryCount(String count) {
    return '$count Verlauf';
  }

  @override
  String get repeatEveryDay => 'Jeden Tag';

  @override
  String get repeatEveryWeek => 'Jede Woche';

  @override
  String get repeatEveryMonth => 'Jeden Monat';

  @override
  String get completedReadOnlyPill =>
      'Erledigt · zum Bearbeiten wiederherstellen';

  @override
  String get inlineEditTitleTooltip => 'Titel bearbeiten';

  @override
  String get inlineEditNameTooltip => 'Namen bearbeiten';

  @override
  String get inlineAddNote => '+ Notiz';

  @override
  String get inlineAddLinks => '+ Links';

  @override
  String get inlineAddSubtasks => '+ Unteraufgaben';

  @override
  String get inlineAddLabels => '+ Labels';

  @override
  String get inlineAddDue => '+ Fälligkeit';

  @override
  String get inlineAddRepeat => '+ Wiederholen';

  @override
  String get inlineAddSuspend => '+ Zurückstellen';

  @override
  String get inlineAddPrerequisites => '+ Voraussetzungen';

  @override
  String get inlineAddConditions => '+ Bedingungen';

  @override
  String get inlineClearAction => 'Entfernen';

  @override
  String get inlineDisableRepeatAction => 'Wiederholung aus';

  @override
  String get inlineResumeTaskAction => 'Wieder aktivieren';

  @override
  String get inlineRepeatLeadNeedsDueHint =>
      'Vorbereitungszeit erfordert eine gesetzte Fälligkeit.';

  @override
  String get inlinePlacementSectionTitle => 'Warteschlange & Priorität';

  @override
  String get placementQueueOption => 'Warteschlange';

  @override
  String get placementQueueHint => 'Am Ende der Warteschlange einordnen.';

  @override
  String get placementPriorityHint =>
      'Priorisiert vor regulären Aufgaben in Fokus oder Bereit einordnen.';

  @override
  String get placementSomedayHint =>
      'Außerhalb der aktiven Warteschlange unter Irgendwann sammeln.';

  @override
  String get inlineDeleteTaskConfirm => 'Aufgabe löschen?';

  @override
  String get inlineDeleteLabelConfirm => 'Label löschen?';

  @override
  String get inlineDeleteLocationConfirm => 'Ort löschen?';

  @override
  String get actionKeep => 'Behalten';

  @override
  String get actionConfirmDelete => 'Ja, löschen';

  @override
  String get actionDone => 'Fertig';

  @override
  String get actionOpenAsDraft => 'Als Entwurf öffnen';

  @override
  String get actionNewTaskCompact => 'Neue Aufgabe';

  @override
  String get actionCreateTask => 'Aufgabe anlegen';

  @override
  String get actionCreateLabel => 'Label anlegen';

  @override
  String get actionCreateLocation => 'Ort anlegen';

  @override
  String get draftNewTaskTitle => 'Neue Aufgabe (Entwurf)';

  @override
  String get draftNewLabelTitle => 'Neues Label (Entwurf)';

  @override
  String get draftNewLocationTitle => 'Neuer Ort (Entwurf)';

  @override
  String get draftUncommittedHint =>
      'Noch nicht gespeichert · erst bei Klick auf Anlegen wird in die TDF-Datei geschrieben.';

  @override
  String get quickCreateLabelHint => 'Neues Label schnell anlegen...';

  @override
  String get quickCreateLocationHint => 'Neuen Ort schnell anlegen...';

  @override
  String get labelsManagerSubtitle =>
      'Kontexte, eigene Warteschlangen, Referenz-Links und vererbte Bedingungen.';

  @override
  String get locationsManagerSubtitle =>
      'Wiederverwendbare Orte für GPS-Bedingungen an Aufgaben und Labels.';

  @override
  String get labelPickerSearchPlaceholder => 'Labels suchen oder anlegen...';

  @override
  String labelPickerFilterAll(String count) {
    return 'Alle ($count)';
  }

  @override
  String labelPickerFilterScoped(String count) {
    return 'Eigene Queue ($count)';
  }

  @override
  String labelPickerFilterGlobal(String count) {
    return 'Global ($count)';
  }

  @override
  String get labelPickerNoMatches => 'Keine passenden Labels gefunden.';

  @override
  String get labelPickerEmptyHint =>
      'Noch keine Labels. Namen eingeben, um direkt eines anzulegen.';

  @override
  String labelPickerCreateAndAssign(String name) {
    return '„$name“ anlegen & zuweisen';
  }

  @override
  String labelPickerRemoveTooltip(String name) {
    return 'Label entfernen: $name';
  }

  @override
  String openTasksCountPill(String count) {
    return '$count offen';
  }

  @override
  String get prerequisiteCyclePreventedHint => 'Zyklus verhindert';

  @override
  String get globalContextLabel => 'Globaler Kontext';

  @override
  String get scopedQueueLabel => 'Eigene Warteschlange';

  @override
  String get conditionInheritLabel => 'Label-Bedingungen übernehmen';

  @override
  String get conditionCustomLabel => 'Eigene Bedingung';

  @override
  String get conditionSatisfiedStatus => 'Aktiv erfüllt';

  @override
  String get conditionBlockedStatus => 'Derzeit nicht erfüllt (blockiert)';

  @override
  String get suspendedUntilModeLabel => 'Bis zu einem Zeitpunkt';

  @override
  String get suspendedForeverModeLabel => 'Unbegrenzt';

  @override
  String get historyTimestampToggleTooltip => 'Zeitstempel wählen';

  @override
  String get historyErrorDuplicate =>
      'Ein identischer Verlaufseintrag mit diesem Zeitstempel existiert bereits.';

  @override
  String locationRadiusReadout(String radius) {
    return 'Radius: $radius';
  }

  @override
  String get entityRemovedExternallyNotice =>
      'Dieser Eintrag wurde durch eine externe Änderung entfernt.';

  @override
  String get taskCompletedExternallyNotice =>
      'Diese Aufgabe wurde durch eine externe Änderung abgeschlossen.';

  @override
  String get labelIdCopiedNotice => 'Label-ID in die Zwischenablage kopiert.';

  @override
  String get locationIdCopiedNotice => 'Orts-ID in die Zwischenablage kopiert.';

  @override
  String taskRestoredNotice(String title) {
    return '„$title“ wiederhergestellt.';
  }

  @override
  String taskCompletedRepeatNotice(String title) {
    return '„$title“ abgeschlossen und für den nächsten Zyklus neu eingeplant.';
  }

  @override
  String get actionUndoneNotice => 'Aktion rückgängig gemacht.';

  @override
  String actionUndoneRemainingNotice(String remaining) {
    return 'Aktion rückgängig gemacht ($remaining weitere im Verlauf).';
  }

  @override
  String workspaceSwitchedNotice(String name) {
    return 'Arbeitsbereich gewechselt: $name';
  }

  @override
  String get gpsAppliedNotice => 'Aktuelle GPS-Position übernommen.';

  @override
  String get locationResolvedNotice =>
      'Quelle erfolgreich auf Koordinaten aufgelöst.';

  @override
  String get labelSavedNotice => 'Label gespeichert.';

  @override
  String get labelDeletedNotice => 'Label gelöscht.';

  @override
  String get locationSavedNotice => 'Ort gespeichert.';

  @override
  String get locationDeletedNotice => 'Ort gelöscht.';

  @override
  String get noticeTaskSaved => 'Aufgabe gespeichert.';

  @override
  String noticeTaskSavedInTier(String tier) {
    return 'Gespeichert · jetzt in $tier';
  }

  @override
  String noticeTaskMovedToScopedQueue(String label) {
    return 'In eigene Warteschlange verschoben: $label';
  }

  @override
  String get noticePriorityEnabled => 'Aufgabe priorisiert';

  @override
  String get noticePriorityDisabled => 'Priorität entfernt';

  @override
  String get noticeMovedToSomeday => 'Nach Irgendwann verschoben';

  @override
  String get noticeMovedToQueue => 'In aktive Warteschlange aufgenommen';

  @override
  String noticeLabelAdded(String name) {
    return 'Label hinzugefügt: $name';
  }

  @override
  String noticeLabelRemoved(String name) {
    return 'Label entfernt: $name';
  }

  @override
  String noticeLabelCreatedAndAssigned(String name) {
    return 'Label angelegt & zugewiesen: $name';
  }

  @override
  String settingsWorkspaceSubtitle(String workspace) {
    return 'Konfiguration für den aktiven Arbeitsbereich „$workspace“.';
  }

  @override
  String get settingsAutoSavedBadge => 'Sofort gespeichert';

  @override
  String get settingsUnsavedChangesBadge => 'Ungespeicherte Änderungen';

  @override
  String get settingsMoveDesktopOnlyTooltip =>
      'Verzeichniswechsel ist nur auf Desktop-Systemen (Linux/Windows) verfügbar.';

  @override
  String get webDavUrlUserinfoError =>
      'URL darf keine eingebetteten Zugangsdaten (user:pass@) enthalten.';

  @override
  String get webDavPathInvalidError =>
      'Ungültiger Remote-Dateipfad (\"..\", Backslashes und Steuerzeichen sind nicht erlaubt).';

  @override
  String get logViewerSubtitle =>
      'Strukturierte Sitzungsereignisse (ohne Zugangsdaten, GPS-Rohdaten oder Notiztexte).';

  @override
  String get logFilterSubsystemLabel => 'Subsystem';

  @override
  String get logActionUpload => 'Log hochladen';

  @override
  String get logActionClear => 'Leeren';

  @override
  String get conflictResolutionTitle => 'Löschkonflikte lösen (TDF-DEL-003)';

  @override
  String get conflictResolutionSubtitle =>
      'Entscheide für jeden betroffenen Eintrag, ob die lokale Bearbeitung behalten oder die Löschung bestätigt werden soll.';

  @override
  String get conflictKeepEditOption =>
      'Bearbeitung behalten (Wiederherstellen)';

  @override
  String get conflictConfirmDeleteOption => 'Löschung bestätigen';

  @override
  String get conflictApplyAndSyncAction =>
      'Entscheidungen anwenden & synchronisieren';

  @override
  String get conflictResolvedNotice =>
      'Löschkonflikte gelöst. Synchronisierung fortgesetzt.';

  @override
  String get recoveryResolutionTitle =>
      'Wiederherstellung nach Generationswechsel (TDF-REC-002)';

  @override
  String get recoveryResolutionSubtitle =>
      'Die gemeinsame Synchronisierungshistorie ist über den letzten bestätigten Stand hinaus fortgeschritten. Entscheide für jeden betroffenen lokalen Eintrag.';

  @override
  String get recoveryAsNewOption => 'Als neu wiederherstellen (neue ID)';

  @override
  String get recoveryDiscardLocalOption => 'Lokale Änderung verwerfen';

  @override
  String get recoveryApplyAndSyncAction =>
      'Wiederherstellung anwenden & synchronisieren';

  @override
  String get recoveryResolvedNotice =>
      'Wiederherstellung abgeschlossen. Synchronisierung fortgesetzt.';

  @override
  String get entityKindTaskBadge => 'AUFGABE';

  @override
  String get entityKindLabelBadge => 'LABEL';

  @override
  String get entityKindLocationBadge => 'ORT';

  @override
  String get tooltipCloseApp => 'TierTask schließen';

  @override
  String get tooltipScrollToTop => 'Nach oben scrollen';

  @override
  String get tooltipCopyFilteredLog => 'Gefiltert kopieren';

  @override
  String get logFilteredCopiedSnackBar =>
      'Gefiltertes Diagnoseprotokoll in die Zwischenablage kopiert.';
}
