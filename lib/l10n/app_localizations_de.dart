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
  String get tabFocusAndReady => 'Fokus & Bereit';

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
  String emptySectionEntries(String heading) {
    return 'Keine Einträge in $heading.';
  }

  @override
  String get tooltipSyncWebDav => 'Mit WebDAV synchronisieren';

  @override
  String get tooltipMarkdownPreview => 'TDF-Vorschau anzeigen';

  @override
  String get tooltipSettings => 'Einstellungen';

  @override
  String get markdownPreviewTitle => 'Raw TDF';

  @override
  String get actionClose => 'Schließen';

  @override
  String get unconfiguredBannerText =>
      'Lokaler Modus aktiv. Konfiguriere WebDAV für die Synchronisation.';

  @override
  String get actionConfigure => 'Einrichten';

  @override
  String get syncErrorTitle => 'WebDAV Synchronisationsfehler';

  @override
  String get actionSettings => 'Einstellungen';

  @override
  String get actionRetry => 'Erneut versuchen';

  @override
  String get quickAddPriority => 'Priorität';

  @override
  String get quickAddAdvanced => 'Erweitert';

  @override
  String get advancedTaskTitle => 'Erweiterte Ansicht';

  @override
  String get editTaskTitle => 'Aufgabe bearbeiten';

  @override
  String get tooltipDowngradeTask => 'Aufgabe herabstufen';

  @override
  String get tooltipEditTask => 'Aufgabe bearbeiten';

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
  String quickAddHint(String heading) {
    return 'Neue Aufgabe in $heading hinzufügen...';
  }

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
  String get localFilePathLabel => 'Lokaler TDF-Dateiname';

  @override
  String get localFilePathHint => 'tiertask.tdf oder t2.tdf';

  @override
  String get localFilePathErrorEmpty =>
      'Bitte einen lokalen Dateinamen eingeben.';

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
  String get sectionFocusTasks => 'FOKUSAUFGABEN';

  @override
  String get sectionReadyTasks => 'BEREITE AUFGABEN';

  @override
  String get sectionPlannedTasks => 'GEPLANTE AUFGABEN';

  @override
  String get sectionBlockedTasks => 'BLOCKIERTE AUFGABEN';

  @override
  String get sectionSomedayTasks => 'IRGENDWANN-AUFGABEN';

  @override
  String get sectionCompletedTasks => 'ERLEDIGTE AUFGABEN';

  @override
  String get sectionAllTasks => 'ALLE AUFGABEN';

  @override
  String get sectionLabels => 'LABELS';

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
  String get colorHexLabel => 'Hex-Farbe';

  @override
  String get emptyLabelsHint => 'Noch keine Labels angelegt.';

  @override
  String get tooltipDeleteLabel => 'Label löschen';

  @override
  String get actionEdit => 'Bearbeiten';

  @override
  String get createNewLabel => 'Neues Label erstellen';

  @override
  String get editLabelsTitle => 'Labels bearbeiten';

  @override
  String get taskSuspendedLabel => 'Zurückgestellt';

  @override
  String get taskSuspendedUntilLabel => 'Zurückgestellt bis (optional)';

  @override
  String get taskSuspendedUntilHint => 'JJJJ-MM-TT [HH:MM] (leer = unbegrenzt)';

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
  String get conditionLocationLatHint => 'Breitengrad';

  @override
  String get conditionLocationLonHint => 'Längengrad';

  @override
  String get conditionLocationRadiusHint => 'Radius (m/km)';

  @override
  String get conditionLocationErrorInvalid =>
      'Bitte gültigen Breitengrad, Längengrad und Radius eingeben (z. B. 200m oder 1.5km).';

  @override
  String get tooltipAddLocationCondition => 'Standortregel hinzufügen';

  @override
  String get tooltipRemoveLocationCondition => 'Standortregel entfernen';

  @override
  String get taskDetailsSectionTitle => 'Aufgabendetails';

  @override
  String get taskSchedulingSectionTitle => 'Planung & Status';

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
  String get taskConditionsSectionDescription =>
      'Schränke ein, wann und wo diese Aufgabe aktiv wird, oder überschreibe geerbte Label-Bedingungen.';

  @override
  String get tooltipPickDate => 'Datum auswählen';

  @override
  String get tooltipPickTime => 'Uhrzeit auswählen';

  @override
  String get tooltipClearDate => 'Zeitstempel löschen';

  @override
  String get tooltipPickStartTime => 'Startzeit auswählen';

  @override
  String get tooltipPickEndTime => 'Endzeit auswählen';

  @override
  String get themePaletteSectionTitle => 'Farbpalette';

  @override
  String get themePaletteSectionDescription =>
      'Material-3-Farbpalette für Oberflächen und Hervorhebungen auswählen.';

  @override
  String get themePaletteSlate => 'Schiefer';

  @override
  String get themePaletteNavy => 'Marineblau';

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
  String get actionChangeDirectory => 'Verzeichnis ändern';

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
  String get tooltipIndicatorPriority => 'Priorität';

  @override
  String get tooltipIndicatorRepeat => 'Wiederkehrende Aufgabe';

  @override
  String get tooltipIndicatorSubtasks => 'Unteraufgaben';

  @override
  String get tooltipIndicatorSubtasksAutoFinish =>
      'Unteraufgaben (automatisch abschließen)';

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
  String get editLabelTitle => 'Label bearbeiten';

  @override
  String get tooltipEditLabel => 'Label bearbeiten';

  @override
  String get labelDetailsSectionTitle => 'Labeldetails';

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
  String get tooltipIndicatorLinks => 'Hat Links';

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
  String get tooltipScrollToBottom => 'Nach unten scrollen';

  @override
  String get tooltipClearLog => 'Protokoll leeren';

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
  String errorUnsupportedTdfVersionLocal(String version) {
    return 'Die lokale Datei verwendet die nicht unterstützte Dateiversion $version. Bitte aktualisieren Sie TierTask auf eine neuere Version.';
  }

  @override
  String errorUnsupportedTdfVersionRemote(String version) {
    return 'Die Remote-Datei verwendet die nicht unterstützte Dateiversion $version. Bitte aktualisieren Sie TierTask auf eine neuere Version.';
  }

  @override
  String errorUnsupportedTdfVersionBoth(String version) {
    return 'Die lokale Datei und die Remote-Datei verwenden die nicht unterstützte Dateiversion $version. Bitte aktualisieren Sie TierTask auf eine neuere Version.';
  }

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
  String get logMetadataSectionTitle => 'Sitzungs-Metadaten';

  @override
  String logMetadataFile(String fileName) {
    return 'Datei: $fileName';
  }

  @override
  String logMetadataVersion(String version) {
    return 'Version: $version';
  }

  @override
  String logMetadataPlatform(String platform) {
    return 'Plattform: $platform';
  }

  @override
  String logMetadataWorkspace(String workspace) {
    return 'Arbeitsbereich: $workspace';
  }

  @override
  String logMetadataTimeZone(String timeZone) {
    return 'Zeitzone: $timeZone';
  }

  @override
  String logMetadataStats(String entries, String warnings, String errors) {
    return 'Einträge: $entries | Warnungen: $warnings | Fehler: $errors';
  }

  @override
  String get logFilterAllTags => 'Alle';

  @override
  String get tooltipSyncLogWebDav => 'Protokoll mit WebDAV synchronisieren';

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
  String get tooltipConditionDayAny =>
      'Überschreibt explizit alle Wochentags-Einschränkungen zugewiesener Labels, sodass diese Aufgabe an jedem Tag aktiv ist.';

  @override
  String get tooltipConditionTimeAny =>
      'Überschreibt explizit alle Zeitfenster-Einschränkungen zugewiesener Labels, sodass diese Aufgabe zu jeder Uhrzeit aktiv ist.';

  @override
  String get tooltipConditionLocationAny =>
      'Überschreibt explizit alle Standort-Einschränkungen zugewiesener Labels, sodass diese Aufgabe an jedem Standort aktiv ist.';

  @override
  String get tooltipTaskEditorPriority =>
      'Markiert diese Aufgabe mit Priorität, sodass sie vor regulären Aufgaben in Fokus oder Bereit gezogen wird.';

  @override
  String get tooltipTaskEditorSomeday =>
      'Parkt diese Aufgabe im Irgendwann-Backlog, ohne sie in aktive Stufen zu ziehen.';

  @override
  String get tooltipTaskEditorSuspended =>
      'Stellt diese Aufgabe unter Blockiert zurück (optional bis zu einem gewählten Zeitpunkt) und deaktiviert währenddessen die Bedingungsauswertung.';

  @override
  String get tooltipTaskEditorRepeat =>
      'Plant diese Aufgabe beim Abschließen automatisch nach dem festgelegten Intervall neu ein und setzt alle Unteraufgaben zurück.';

  @override
  String get tooltipTaskEditorAutoFinish =>
      'Schließt die gesamte Aufgabe automatisch ab, sobald alle Unteraufgaben abgehakt sind.';

  @override
  String get drawerLocations => 'Orte';

  @override
  String get createNewLocation => 'Neuen Ort erstellen';

  @override
  String get editLocationsTitle => 'Orte bearbeiten';

  @override
  String get editLocationTitle => 'Ort bearbeiten';

  @override
  String get emptyLocationsHint => 'Noch keine Orte erstellt.';

  @override
  String get tooltipDeleteLocation => 'Ort löschen';

  @override
  String get tooltipEditLocation => 'Ort bearbeiten';

  @override
  String get locationDetailsSectionTitle => 'Ortsdetails';

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
  String get labelScopedSwitchTitle => 'Fokussiertes Label';

  @override
  String get labelScopedSwitchSubtitle =>
      'Aufgaben mit diesem Label ausblenden, solange dieser Filter nicht aktiv ist.';

  @override
  String get taskDueButtonLabel => 'Fällig am (optional)';

  @override
  String get taskDueClearTooltip => 'Fälligkeit löschen';

  @override
  String pillDuePrefix(String date) {
    return 'Fällig: $date';
  }

  @override
  String get errorLocalFileCasExhausted =>
      'Die lokale Datei wurde gleichzeitig geändert und hat die maximale Anzahl an Merge-Versuchen überschritten.';

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
}
