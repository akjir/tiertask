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
  String get markdownPreviewTitle => 'Raw TDF (Single Source of Truth)';

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
  String get openTaskCountSectionTitle => 'Gesamtzahl offener Aufgaben';

  @override
  String get openTaskCountSectionDescription =>
      'Gesamtzahl der offenen Aufgaben auf Label-Karten ein- oder ausblenden.';

  @override
  String get openTaskCountOff => 'Aus';

  @override
  String get openTaskCountOn => 'An';

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
  String get webdavSectionTitle =>
      'WebDAV-Synchronisation (Single Source of Truth)';

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
  String get sectionLabels => 'LABELS';

  @override
  String taskCountLabel(int count) {
    return '$count Aufgaben';
  }

  @override
  String get tooltipMenu => 'Menü öffnen';

  @override
  String get tooltipSearch => 'Aufgaben suchen';

  @override
  String get searchHint => 'Fokusaufgaben durchsuchen...';

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
  String get tooltipRenameLabel => 'Label umbenennen';

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
  String get sectionBlockedByTasks => 'VORAUSSETZUNGEN (BLOCKIERT DURCH)';

  @override
  String get sectionTaskConditions => 'AKTIVIERUNGSBEDINGUNGEN';

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
}
