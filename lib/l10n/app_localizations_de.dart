// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'TierTask (T2)';

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
  String get tier1Description => 'Aktive Top-Priorität (Soft-Limit: 3)';

  @override
  String get tier2Description => 'Startklar für Fokus (Soft-Limit: 5)';

  @override
  String get tier3Description =>
      'Aktives Backlog (rückt automatisch in Bereit nach)';

  @override
  String get tier4Description => 'Wartet auf externe Ereignisse oder Dritte';

  @override
  String get tier5Description => 'Ideenspeicher ohne automatisches Nachrücken';

  @override
  String get tier6Description =>
      'Abgeschlossene Aufgaben (30 Tage Aufbewahrung)';

  @override
  String get tabFocusAndReady => '[1] Fokus & [2] Bereit';

  @override
  String get emptyFocusHint =>
      'Keine Aufgaben in # [1] Fokus. Neue Aufgaben aus # [2] Bereit oder # [3] Geplant rücken automatisch hierher nach.';

  @override
  String get emptyReadyHint => 'Keine Aufgaben in # [2] Bereit.';

  @override
  String get emptyPlannedHint =>
      'Keine Aufgaben im aktiven Backlog (# [3] Geplant).';

  @override
  String get emptyBlockedHint =>
      'Keine blockierten Aufgaben (# [4] Blockiert).';

  @override
  String get emptySomedayHint => 'Keine Ideen in # [5] Irgendwann gespeichert.';

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
  String get tooltipMarkdownPreview => 'Markdown-Vorschau anzeigen';

  @override
  String get tooltipSettings => 'Einstellungen';

  @override
  String get markdownPreviewTitle => 'Raw Markdown (Single Source of Truth)';

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
  String defaultTierChipLabel(String heading) {
    return '$heading (Standard)';
  }

  @override
  String quickAddHint(String heading) {
    return 'Neue Aufgabe in $heading hinzufügen...';
  }

  @override
  String get actionAdd => 'Hinzufügen';

  @override
  String get restoreTaskTitle => 'Aufgabe wiederherstellen';

  @override
  String get moveTaskTitle => 'Aufgabe verschieben';

  @override
  String selectTargetTierSubtitle(String taskTitle) {
    return '\"$taskTitle\" - Zielkategorie auswählen:';
  }

  @override
  String completedOnDate(String date) {
    return 'Erledigt am $date';
  }

  @override
  String get tooltipDowngradeToReady => 'Herabstufen nach # [2] Bereit';

  @override
  String get tooltipDowngradeToPlanned => 'Herabstufen nach # [3] Geplant';

  @override
  String get tooltipBlockTask => 'Sofort nach # [4] Blockiert verschieben';

  @override
  String get tooltipPromoteToPlanned => 'In # [3] Geplant einreihen';

  @override
  String get tooltipMoreActions => 'Weitere Aktionen';

  @override
  String get menuMoveTo => 'Verschieben nach...';

  @override
  String get menuEditText => 'Text bearbeiten';

  @override
  String get menuDelete => 'Löschen';

  @override
  String get editTaskDialogTitle => 'Aufgabe bearbeiten';

  @override
  String get editTaskFieldLabel => 'Aufgabentext';

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
  String get webdavSectionTitle =>
      'WebDAV-Synchronisation (Single Source of Truth)';

  @override
  String get webdavSectionDescription =>
      'TierTask speichert alle Aufgaben in einer einzigen Markdown-Datei (tiertask.md) auf deinem WebDAV-Server. Nutze nach Möglichkeit ein eigenes App-Passwort.';

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
  String get filePathLabel => 'Markdown-Dateiname / Pfad';

  @override
  String get filePathHint => 'tiertask.md oder t2.md';

  @override
  String get resolvedEndpointLabel =>
      'Aufgelöster WebDAV-Endpunkt (GET / PUT):';

  @override
  String get credentialsSavedBanner => 'Zugangsdaten lokal gespeichert.';

  @override
  String get connectionSuccessBanner =>
      'Verbindung erfolgreich. Markdown-Datei wurde mit WebDAV synchronisiert.';

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
      'Fehler beim Laden der Markdown-Datei vom Server.';

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
      'Fehler beim Speichern der Markdown-Datei auf dem Server.';

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
}
