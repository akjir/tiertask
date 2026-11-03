// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TierTask';

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
  String get tabFocusAndReady => 'Focus & Ready';

  @override
  String get emptyFocusHint =>
      'No tasks in Focus. Tasks from Ready or Planned automatically move up here.';

  @override
  String get emptyReadyHint => 'No tasks in Ready.';

  @override
  String get emptyPlannedHint => 'No tasks in active backlog (Planned).';

  @override
  String get emptyBlockedHint => 'No blocked tasks (Blocked).';

  @override
  String get emptySomedayHint => 'No ideas stored in Someday.';

  @override
  String get emptyCompletedHint => 'No completed tasks from the last 30 days.';

  @override
  String emptySectionEntries(String heading) {
    return 'No entries in $heading.';
  }

  @override
  String get tooltipSyncWebDav => 'Synchronize with WebDAV';

  @override
  String get tooltipMarkdownPreview => 'Show TDF preview';

  @override
  String get tooltipSettings => 'Settings';

  @override
  String get markdownPreviewTitle => 'Raw TDF (Single Source of Truth)';

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
  String get quickAddPriority => 'Priority';

  @override
  String get quickAddAdvanced => 'Advanced';

  @override
  String get advancedTaskTitle => 'Extended Task View';

  @override
  String get editTaskTitle => 'Edit Task';

  @override
  String get tooltipDowngradeTask => 'Downgrade task';

  @override
  String get tooltipEditTask => 'Edit task';

  @override
  String get taskNameLabel => 'Task Name';

  @override
  String get taskNameErrorEmpty => 'Please enter a task name.';

  @override
  String get taskNameErrorDuplicate => 'A task with this name already exists.';

  @override
  String get taskNoteLabel => 'Note';

  @override
  String get taskNoteHint => 'Optional note or description...';

  @override
  String get subtasksAutoFinishLabel => 'Auto-finish';

  @override
  String get subtasksSectionTitle => 'Subtasks';

  @override
  String get subtaskInputHint => 'Add subtask...';

  @override
  String get tooltipAddSubtask => 'Add subtask';

  @override
  String get tooltipRemoveSubtask => 'Remove subtask';

  @override
  String quickAddHint(String heading) {
    return 'Add new task to $heading...';
  }

  @override
  String get actionAdd => 'Add';

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
  String get themeSectionTitle => 'Theme';

  @override
  String get themeSectionDescription =>
      'Select the color theme. System follows the operating system brightness setting.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get openTaskCountSectionTitle => 'Open Task Count';

  @override
  String get openTaskCountSectionDescription =>
      'Show or hide the total number of open tasks on label cards.';

  @override
  String get openTaskCountOff => 'Off';

  @override
  String get openTaskCountOn => 'On';

  @override
  String get storageModeSectionTitle => 'Storage Mode';

  @override
  String get storageModeSectionDescription =>
      'Select whether tasks are stored in a local TDF file, on a WebDAV server, or in both locations.';

  @override
  String get storageModeLocal => 'Local';

  @override
  String get storageModeWebDav => 'WebDAV';

  @override
  String get storageModeBoth => 'Both';

  @override
  String get localSectionTitle => 'Local TDF File';

  @override
  String get localSectionDescription =>
      'Stores all tasks in a local TDF file on this device.';

  @override
  String get localFilePathLabel => 'Local TDF File Name';

  @override
  String get localFilePathHint => 'tiertask.tdf or t2.tdf';

  @override
  String get localFilePathErrorEmpty => 'Please enter a local file name.';

  @override
  String get resolvedLocalPathLabel => 'Resolved Local File Path:';

  @override
  String get webdavSectionTitle =>
      'WebDAV Synchronization (Single Source of Truth)';

  @override
  String get webdavSectionDescription =>
      'TierTask stores all tasks in a single TDF file (tiertask.tdf) on your WebDAV server. Use an application password when supported by your server.';

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
  String get filePathLabel => 'TDF File Name / Path';

  @override
  String get filePathHint => 'tiertask.tdf or t2.tdf';

  @override
  String get resolvedEndpointLabel => 'Resolved WebDAV Endpoint (GET / PUT):';

  @override
  String get credentialsSavedBanner => 'Settings saved locally.';

  @override
  String get connectionSuccessBanner =>
      'Connection succeeded. TDF file synchronized with WebDAV.';

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
  String get errorLoadMarkdownFailed => 'Failed to load TDF file from server.';

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
  String get errorSaveMarkdownFailed => 'Failed to save TDF file on server.';

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

  @override
  String get errorInvalidLocalFilePath =>
      'Invalid local TDF file name or path.';

  @override
  String get errorLocalFileTooLarge =>
      'TDF file exceeds the maximum allowed size.';

  @override
  String errorLoadLocalFileFailed(String details) {
    return 'Failed to read local TDF file ($details).';
  }

  @override
  String errorSaveLocalFileFailed(String details) {
    return 'Failed to write local TDF file ($details).';
  }

  @override
  String get sectionFocusTasks => 'FOCUS TASKS';

  @override
  String get sectionReadyTasks => 'READY TASKS';

  @override
  String get sectionPlannedTasks => 'PLANNED TASKS';

  @override
  String get sectionBlockedTasks => 'BLOCKED TASKS';

  @override
  String get sectionSomedayTasks => 'SOMEDAY TASKS';

  @override
  String get sectionCompletedTasks => 'COMPLETED TASKS';

  @override
  String get sectionLabels => 'LABELS';

  @override
  String taskCountLabel(int count) {
    return '$count tasks';
  }

  @override
  String get tooltipMenu => 'Open menu';

  @override
  String get tooltipSearch => 'Search tasks';

  @override
  String get searchHint => 'Search focus tasks...';

  @override
  String get drawerLabels => 'Labels';

  @override
  String get labelNameHint => 'New label name...';

  @override
  String get colorHexLabel => 'Hex Color';

  @override
  String get emptyLabelsHint => 'No labels created yet.';

  @override
  String get tooltipDeleteLabel => 'Delete label';

  @override
  String get actionEdit => 'Edit';

  @override
  String get createNewLabel => 'Create new label';

  @override
  String get editLabelsTitle => 'Edit labels';

  @override
  String get tooltipRenameLabel => 'Rename label';

  @override
  String get taskSuspendedLabel => 'Suspended';

  @override
  String get taskSuspendedUntilLabel => 'Suspended until (optional)';

  @override
  String get taskSuspendedUntilHint =>
      'YYYY-MM-DD [HH:MM] (empty = indefinite)';

  @override
  String get taskSuspendedErrorInvalid =>
      'Enter a valid timestamp (YYYY-MM-DD or YYYY-MM-DD HH:MM).';

  @override
  String get taskSuspendedDisablesConditionsHint =>
      'Suspended is active: evaluation of all other conditions is disabled and this task appears under Blocked.';

  @override
  String get conditionGlobalAnyLabel => 'Any (ignore label conditions)';

  @override
  String get conditionDayGroupTitle => 'Weekdays';

  @override
  String get conditionDayAnyLabel => 'Any day';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get conditionTimeGroupTitle => 'Time Windows';

  @override
  String get conditionTimeAnyLabel => 'Any time';

  @override
  String get conditionTimeStartHint => 'Start (HH:MM)';

  @override
  String get conditionTimeEndHint => 'End (HH:MM)';

  @override
  String get conditionTimeErrorInvalid => 'Enter valid 24-hour times (HH:MM).';

  @override
  String get tooltipAddTimeCondition => 'Add time window';

  @override
  String get tooltipRemoveTimeCondition => 'Remove time window';

  @override
  String get conditionLocationGroupTitle => 'Locations (GPS)';

  @override
  String get conditionLocationAnyLabel => 'Any location';

  @override
  String get conditionLocationLatHint => 'Latitude';

  @override
  String get conditionLocationLonHint => 'Longitude';

  @override
  String get conditionLocationRadiusHint => 'Radius (m/km)';

  @override
  String get conditionLocationErrorInvalid =>
      'Enter valid latitude, longitude, and radius (e.g. 200m or 1.5km).';

  @override
  String get tooltipAddLocationCondition => 'Add location rule';

  @override
  String get tooltipRemoveLocationCondition => 'Remove location rule';

  @override
  String get taskDetailsSectionTitle => 'Task Details';

  @override
  String get taskSchedulingSectionTitle => 'Scheduling & Status';

  @override
  String get taskLabelsSectionTitle => 'Labels';

  @override
  String get taskBlockedBySectionTitle => 'Prerequisite Tasks';

  @override
  String get taskBlockedBySectionDescription =>
      'Search for open tasks by name and select tasks that must be finished before this task becomes active.';

  @override
  String get blockedBySearchHint => 'Search tasks by name...';

  @override
  String get blockedBySearchNoResults => 'No matching tasks found.';

  @override
  String get tooltipClearSearch => 'Clear search';

  @override
  String get taskConditionsSectionTitle => 'Activation Conditions';

  @override
  String get taskConditionsSectionDescription =>
      'Restrict when and where this task becomes active, or override inherited label conditions.';

  @override
  String get tooltipPickDate => 'Pick date';

  @override
  String get tooltipPickTime => 'Pick time';

  @override
  String get tooltipClearDate => 'Clear timestamp';

  @override
  String get tooltipPickStartTime => 'Pick start time';

  @override
  String get tooltipPickEndTime => 'Pick end time';

  @override
  String get themePaletteSectionTitle => 'Color Palette';

  @override
  String get themePaletteSectionDescription =>
      'Select the Material 3 color palette for surfaces and highlights.';

  @override
  String get themePaletteSlate => 'Slate';

  @override
  String get themePaletteNavy => 'Navy';

  @override
  String get timeZoneSectionTitle => 'Time Zone';

  @override
  String get timeZoneSectionDescription =>
      'Select whether the local time zone is detected automatically from the device or set manually for task conditions and display.';

  @override
  String get timeZoneModeAutomatic => 'Automatic';

  @override
  String get timeZoneModeManual => 'Manual';

  @override
  String get timeZoneOffsetLabel => 'UTC Offset';

  @override
  String get repeatFlagLabel => 'Repeat';

  @override
  String get repeatIntervalLabel => 'Repeat every';

  @override
  String get repeatUnitDays => 'Days';

  @override
  String get repeatUnitWeeks => 'Weeks';

  @override
  String get repeatUnitMonths => 'Months';

  @override
  String get repeatErrorInvalid =>
      'Please enter an interval between 1 and 3650.';
}
