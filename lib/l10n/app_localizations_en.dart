// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TierTask (T2)';

  @override
  String get tier1Name => 'Focus';

  @override
  String get tier2Name => 'Ready';

  @override
  String get tier3Name => 'Planned';

  @override
  String get tier4Name => 'Blocked';

  @override
  String get tier5Name => 'Someday';

  @override
  String get tier6Name => 'Completed';

  @override
  String get tier1Description => 'Active top priority (Soft limit: 3)';

  @override
  String get tier2Description => 'Ready for Focus (Soft limit: 5)';

  @override
  String get tier3Description =>
      'Active backlog (automatically pulls into Ready)';

  @override
  String get tier4Description => 'Waiting on external events or third parties';

  @override
  String get tier5Description => 'Idea storage without automatic pull';

  @override
  String get tier6Description => 'Completed tasks (30-day retention)';

  @override
  String get tabFocusAndReady => '[1] Focus & [2] Ready';

  @override
  String get emptyFocusHint =>
      'No tasks in # [1] Focus. Tasks from # [2] Ready or # [3] Planned automatically move up here.';

  @override
  String get emptyReadyHint => 'No tasks in # [2] Ready.';

  @override
  String get emptyPlannedHint => 'No tasks in active backlog (# [3] Planned).';

  @override
  String get emptyBlockedHint => 'No blocked tasks (# [4] Blocked).';

  @override
  String get emptySomedayHint => 'No ideas stored in # [5] Someday.';

  @override
  String get emptyCompletedHint => 'No completed tasks from the last 30 days.';

  @override
  String emptySectionEntries(String heading) {
    return 'No entries in $heading.';
  }

  @override
  String get tooltipSyncWebDav => 'Synchronize with WebDAV';

  @override
  String get tooltipMarkdownPreview => 'Show Markdown preview';

  @override
  String get tooltipSettings => 'Settings';

  @override
  String get markdownPreviewTitle => 'Raw Markdown (Single Source of Truth)';

  @override
  String get actionClose => 'Close';

  @override
  String get unconfiguredBannerText =>
      'Local mode active. Configure WebDAV for synchronization.';

  @override
  String get actionConfigure => 'Configure';

  @override
  String get syncErrorTitle => 'WebDAV Synchronization Error';

  @override
  String get actionSettings => 'Settings';

  @override
  String get actionRetry => 'Retry';

  @override
  String defaultTierChipLabel(String heading) {
    return '$heading (Default)';
  }

  @override
  String quickAddHint(String heading) {
    return 'Add new task to $heading...';
  }

  @override
  String get actionAdd => 'Add';

  @override
  String get restoreTaskTitle => 'Restore Task';

  @override
  String get moveTaskTitle => 'Move Task';

  @override
  String selectTargetTierSubtitle(String taskTitle) {
    return '\"$taskTitle\" - Select target tier:';
  }

  @override
  String completedOnDate(String date) {
    return 'Completed on $date';
  }

  @override
  String get tooltipDowngradeToReady => 'Downgrade to # [2] Ready';

  @override
  String get tooltipDowngradeToPlanned => 'Downgrade to # [3] Planned';

  @override
  String get tooltipBlockTask => 'Move immediately to # [4] Blocked';

  @override
  String get tooltipPromoteToPlanned => 'Queue in # [3] Planned';

  @override
  String get tooltipMoreActions => 'More actions';

  @override
  String get menuMoveTo => 'Move to...';

  @override
  String get menuEditText => 'Edit text';

  @override
  String get menuDelete => 'Delete';

  @override
  String get editTaskDialogTitle => 'Edit Task';

  @override
  String get editTaskFieldLabel => 'Task text';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get languageSectionTitle => 'Language';

  @override
  String get languageSectionDescription =>
      'Select the display language. System uses German on German systems and English otherwise.';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get webdavSectionTitle =>
      'WebDAV Synchronization (Single Source of Truth)';

  @override
  String get webdavSectionDescription =>
      'TierTask stores all tasks in a single Markdown file (tiertask.md) on your WebDAV server. Use an application password when supported by your server.';

  @override
  String get serverUrlLabel => 'WebDAV Server URL';

  @override
  String get serverUrlErrorEmpty => 'Please enter a server URL.';

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameErrorEmpty => 'Please enter a username.';

  @override
  String get passwordLabel => 'App Password / Password';

  @override
  String get tooltipShowPassword => 'Show password';

  @override
  String get tooltipHidePassword => 'Hide password';

  @override
  String get passwordErrorEmpty => 'Please enter a password or app password.';

  @override
  String get filePathLabel => 'Markdown File Name / Path';

  @override
  String get filePathHint => 'tiertask.md or t2.md';

  @override
  String get resolvedEndpointLabel => 'Resolved WebDAV Endpoint (GET / PUT):';

  @override
  String get credentialsSavedBanner => 'Settings saved locally.';

  @override
  String get connectionSuccessBanner =>
      'Connection succeeded. Markdown file synchronized with WebDAV.';

  @override
  String get actionTestConnectionAndSync => 'Test Connection / Sync Now';

  @override
  String get errorWebDavNotConfigured =>
      'Please configure WebDAV in Settings first.';

  @override
  String get errorInvalidServerUrl => 'Invalid WebDAV server URL.';

  @override
  String get errorAuthFailedLoad =>
      'Authentication failed. Please check username and app password.';

  @override
  String get errorLoadMarkdownFailed =>
      'Failed to load Markdown file from server.';

  @override
  String errorNetworkUnreachable(String details) {
    return 'Network error: Server unreachable ($details).';
  }

  @override
  String get errorTimeoutLoad => 'Connection to WebDAV server timed out.';

  @override
  String errorTlsLoad(String details) {
    return 'TLS/SSL connection error: $details';
  }

  @override
  String errorUnexpectedLoad(String details) {
    return 'Unexpected WebDAV error while loading: $details';
  }

  @override
  String get errorAuthFailedSave =>
      'Authentication failed while saving. Please check app password.';

  @override
  String get errorSaveMarkdownFailed =>
      'Failed to save Markdown file on server.';

  @override
  String errorNetworkSave(String details) {
    return 'Network error while saving ($details).';
  }

  @override
  String get errorTimeoutSave => 'Timed out while saving to WebDAV server.';

  @override
  String errorTlsSave(String details) {
    return 'TLS/SSL error while saving: $details';
  }

  @override
  String errorUnexpectedSave(String details) {
    return 'Unexpected WebDAV error while saving: $details';
  }
}
