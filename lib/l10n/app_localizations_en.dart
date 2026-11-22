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
  String get actionClose => 'Close';

  @override
  String get unconfiguredBannerText =>
      'Local mode active. Configure WebDAV for synchronization.';

  @override
  String get actionConfigure => 'Configure';

  @override
  String get actionSettings => 'Settings';

  @override
  String get actionRetry => 'Retry';

  @override
  String get quickAddPriority => 'Priority';

  @override
  String get tooltipDowngradeTask => 'Downgrade task';

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
  String get quickAddHint => 'New task...';

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
  String get localFilePathHint => 'tiertask.tdf or t2.tdf';

  @override
  String get resolvedLocalPathLabel => 'Resolved Local File Path:';

  @override
  String get webdavSectionTitle => 'WebDAV Synchronization';

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
  String get tooltipMenu => 'Open menu';

  @override
  String get tooltipSearch => 'Search tasks';

  @override
  String get searchHint => 'Search tasks...';

  @override
  String get drawerLabels => 'Labels';

  @override
  String get labelNameHint => 'New label name...';

  @override
  String get emptyLabelsHint => 'No labels created yet.';

  @override
  String get tooltipDeleteLabel => 'Delete label';

  @override
  String get actionEdit => 'Edit';

  @override
  String get taskSuspendedLabel => 'Suspended';

  @override
  String get taskSuspendedUntilLabel => 'Suspended until (optional)';

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
  String get conditionLocationErrorInvalid =>
      'Enter valid latitude, longitude, and radius (e.g. 200m or 1.5km).';

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
  String get tooltipPickDate => 'Pick date';

  @override
  String get tooltipPickTime => 'Pick time';

  @override
  String get themePaletteSectionTitle => 'Color Palette';

  @override
  String get themePaletteSectionDescription =>
      'Select the Material 3 color palette for surfaces and highlights.';

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

  @override
  String get tooltipClearInput => 'Clear text';

  @override
  String get localDirectoryMovedBanner =>
      'Local TDF directory updated and file moved.';

  @override
  String errorMoveTargetFileExists(String path) {
    return 'Cannot move TDF file: A file already exists at the target path ($path).';
  }

  @override
  String errorMoveTargetDirectoryExists(String path) {
    return 'Cannot move TDF file: A directory with this name already exists at the target path ($path).';
  }

  @override
  String errorMoveTargetSymlinkExists(String path) {
    return 'Cannot move TDF file: A symbolic link already exists at the target path ($path).';
  }

  @override
  String errorMoveSourceIsSymlink(String path) {
    return 'Cannot move TDF file: The source path is a symbolic link ($path).';
  }

  @override
  String errorMoveSourceIsDirectory(String path) {
    return 'Cannot move TDF file: The source path is a directory ($path).';
  }

  @override
  String errorMoveTargetDirectoryNotFound(String path) {
    return 'Cannot move TDF file: The target directory does not exist ($path).';
  }

  @override
  String errorMoveTargetNotADirectory(String path) {
    return 'Cannot move TDF file: The selected target path is not a directory ($path).';
  }

  @override
  String errorMovePermissionDenied(String path) {
    return 'Cannot move TDF file: Permission denied ($path).';
  }

  @override
  String errorMoveReadOnlyFileSystem(String path) {
    return 'Cannot move TDF file: The file system is read-only ($path).';
  }

  @override
  String errorMoveDiskFull(String path) {
    return 'Cannot move TDF file: Not enough free disk space ($path).';
  }

  @override
  String errorMoveFileLocked(String path) {
    return 'Cannot move TDF file: The file is locked or in use by another process ($path).';
  }

  @override
  String errorMovePathTooLong(String path) {
    return 'Cannot move TDF file: The file path or name is too long ($path).';
  }

  @override
  String errorMoveLocalFileFailed(String details) {
    return 'Cannot move TDF file ($details).';
  }

  @override
  String get errorDuplicateWorkspaceFilePath =>
      'Another workspace already uses this TDF file path.';

  @override
  String get tooltipManageWorkspaces => 'Switch or manage workspaces';

  @override
  String get workspacesDialogTitle => 'Workspaces';

  @override
  String get workspacesDialogDescription =>
      'Switch between isolated task boards or create a new workspace with its own TDF file.';

  @override
  String get workspaceActiveBadge => 'Active';

  @override
  String get createWorkspaceHint => 'New workspace name...';

  @override
  String workspaceSuggestedFileLabel(String fileName) {
    return 'TDF file: $fileName';
  }

  @override
  String get tooltipCreateWorkspace => 'Create workspace';

  @override
  String get tooltipRenameWorkspace => 'Rename workspace';

  @override
  String get tooltipDeleteWorkspace => 'Delete workspace';

  @override
  String deleteWorkspaceConfirmMessage(String name) {
    return 'Remove workspace \"$name\"? Its TDF file will not be deleted.';
  }

  @override
  String get actionDelete => 'Delete';

  @override
  String get errorWorkspaceNameEmpty =>
      'Please enter a valid workspace name (1–128 characters).';

  @override
  String get errorWorkspaceNameDuplicate =>
      'A workspace with this name already exists.';

  @override
  String get errorWorkspaceCannotDeleteLast =>
      'The last remaining workspace cannot be deleted.';

  @override
  String get errorWorkspaceMaxExceeded =>
      'Maximum number of workspaces (32) reached.';

  @override
  String get locationSectionTitle => 'Location Determination';

  @override
  String get locationSectionDescription =>
      'Determine your current place and GPS coordinates while the app is running to evaluate location conditions.';

  @override
  String get locationOff => 'Off';

  @override
  String get locationOn => 'On';

  @override
  String get tooltipLocationStatus => 'Location status';

  @override
  String get locationDialogTitle => 'Location Status';

  @override
  String get locationStatusSearching => 'Searching for location...';

  @override
  String get locationStatusFound => 'Location found';

  @override
  String get locationStatusUnavailable => 'No location information available';

  @override
  String get locationPlaceLabel => 'Place';

  @override
  String get locationCoordinatesLabel => 'GPS Coordinates';

  @override
  String get locationPlaceUnknown => 'Unknown place';

  @override
  String get locationSourceLabel => 'Source';

  @override
  String get locationSourceGps => 'GPS';

  @override
  String get locationSourceSystem => 'System / Network';

  @override
  String get locationSourceInternet => 'Internet (GeoIP)';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get labelNameLabel => 'Label Name';

  @override
  String get labelNameErrorEmpty => 'Please enter a label name.';

  @override
  String get labelNameErrorDuplicate =>
      'A label with this name already exists.';

  @override
  String get labelColorSectionTitle => 'Color';

  @override
  String get labelColorHint => '#RRGGBB (optional)';

  @override
  String get labelColorErrorInvalid => 'Enter a valid hex color (#RRGGBB).';

  @override
  String get labelConditionsSectionDescription =>
      'Restrict when and where tasks with this label become active by default.';

  @override
  String get linksSectionTitle => 'Links';

  @override
  String get linkTitleHint => 'Link title (e.g. Documentation)';

  @override
  String get linkUriHint => 'URI (e.g. https://example.com)';

  @override
  String get tooltipAddLink => 'Add link';

  @override
  String get tooltipRemoveLink => 'Remove link';

  @override
  String get tooltipOpenLink => 'Open link';

  @override
  String get tooltipIndicatorNote => 'Note';

  @override
  String get linkErrorInvalid =>
      'Enter both a link title and a valid URI with scheme (e.g. https://...).';

  @override
  String get linkErrorMaxExceeded => 'Maximum of 20 links per task reached.';

  @override
  String get errorOpenLinkFailed => 'Could not open link.';

  @override
  String get diagnosticsSectionTitle => 'Enable Diagnostic Log';

  @override
  String get diagnosticsSectionDescription =>
      'Record runtime events and preserve crash traces locally in tiertask.log for debugging.';

  @override
  String get diagnosticLogButton => 'Diagnostic Log';

  @override
  String get diagnosticLogTitle => 'Diagnostic Log';

  @override
  String get emptyLogHint => 'No diagnostic log entries recorded yet.';

  @override
  String get tooltipCopyLog => 'Copy All';

  @override
  String get logCopiedSnackBar => 'Diagnostic log copied to clipboard.';

  @override
  String get logClearedSnackBar => 'Diagnostic log cleared.';

  @override
  String get actionWipeLocalFile => 'Wipe Local TDF File';

  @override
  String get actionWipeRemoteFile => 'Wipe Remote TDF File';

  @override
  String get wipeLocalDialogTitle => 'Wipe Local TDF File';

  @override
  String get wipeRemoteDialogTitle => 'Wipe Remote TDF File';

  @override
  String wipeLocalDialogDescription(String fileName, String baseName) {
    return 'This will empty the local file \"$fileName\" and re-initialize it as an empty TDF document. Enter \"$baseName\" (file name without .tdf) to confirm.';
  }

  @override
  String wipeRemoteDialogDescription(String fileName, String baseName) {
    return 'This will empty the remote WebDAV file \"$fileName\" and re-initialize it as an empty TDF document. Enter \"$baseName\" (file name without .tdf) to confirm.';
  }

  @override
  String get wipeConfirmInputLabel => 'File name without .tdf';

  @override
  String get wipeCreateBackupLabel =>
      'Create backup (.bak / .bak.001+) if file exists';

  @override
  String get actionWipeConfirm => 'Wipe File';

  @override
  String get localFileWipedBanner => 'Local TDF file wiped and re-initialized.';

  @override
  String get remoteFileWipedBanner =>
      'Remote TDF file wiped and re-initialized on WebDAV.';

  @override
  String get actionSelectLocalFile => 'Select';

  @override
  String get actionMoveLocalFile => 'Move';

  @override
  String get actionRenameLocalFile => 'Rename';

  @override
  String get selectLocalDialogTitle => 'Select or Create Local TDF File';

  @override
  String get selectLocalDialogDescription =>
      'Select an existing TDF file in the storage directory or enter a new file name.';

  @override
  String get renameLocalDialogTitle => 'Rename Local TDF File';

  @override
  String renameLocalDialogDescription(String fileName) {
    return 'Enter a new file name for \"$fileName\" in the current directory.';
  }

  @override
  String get localFileNameInputLabel => 'File Name (.tdf)';

  @override
  String get localFileNameErrorInvalid =>
      'Please enter a valid file name without path separators.';

  @override
  String get localFileSelectedBanner => 'Local TDF file selected.';

  @override
  String get localFileRenamedBanner => 'Local TDF file renamed.';

  @override
  String get logLevelLabel => 'Minimum Log Level';

  @override
  String get logLevelDebug => 'Debug';

  @override
  String get logLevelInfo => 'Info';

  @override
  String get logLevelWarn => 'Warning';

  @override
  String get logLevelError => 'Error';

  @override
  String get logStorageLabel => 'Log Storage';

  @override
  String get logStorageLocal => 'Local';

  @override
  String get logStorageWebDav => 'WebDAV';

  @override
  String get logStorageBoth => 'Both';

  @override
  String logMetadataFile(String fileName) {
    return 'File: $fileName';
  }

  @override
  String logMetadataStats(String entries, String warnings, String errors) {
    return 'Entries: $entries | Warnings: $warnings | Errors: $errors';
  }

  @override
  String get logFilterAllTags => 'All';

  @override
  String get logSyncedSnackBar => 'Diagnostic log synced to WebDAV.';

  @override
  String get tooltipPickCustomColor => 'Choose custom color';

  @override
  String get labelColorPickerDialogTitle => 'Choose Custom Color';

  @override
  String get labelColorBrightnessLabel => 'Brightness';

  @override
  String get actionSelectColor => 'Select';

  @override
  String get tooltipTaskEditorAutoFinish =>
      'Automatically completes the entire task as soon as all subtasks are checked off.';

  @override
  String get drawerLocations => 'Locations';

  @override
  String get emptyLocationsHint => 'No locations created yet.';

  @override
  String get tooltipDeleteLocation => 'Delete location';

  @override
  String get locationNameLabel => 'Location Name';

  @override
  String get locationCoordinatesSectionTitle => 'Coordinates & Radius';

  @override
  String get locationLatitudeLabel => 'Latitude (-90 to 90)';

  @override
  String get locationLongitudeLabel => 'Longitude (-180 to 180)';

  @override
  String get locationRadiusLabel => 'Radius (m/km)';

  @override
  String get locationUseCurrentGpsButton => 'Use Current GPS Position';

  @override
  String get locationNameErrorEmpty => 'Please enter a location name.';

  @override
  String get locationSourceErrorEmpty =>
      'Please enter a valid source or leave it empty.';

  @override
  String get locationCoordinatesErrorInvalid =>
      'Enter valid latitude (-90..90) and longitude (-180..180).';

  @override
  String get locationRadiusErrorInvalid =>
      'Enter a valid radius between 0.01m and 100km.';

  @override
  String get labelScopedSectionTitle => 'Board Scope';

  @override
  String get labelScopedSwitchSubtitle =>
      'Hide tasks with this label unless this label filter is active.';

  @override
  String get taskDueButtonLabel => 'Due (optional)';

  @override
  String pillDuePrefix(String date) {
    return 'Due: $date';
  }

  @override
  String get locationSourceTypeLabel => 'Source Type';

  @override
  String get locationSourceTypeGps => 'GPS Coordinates';

  @override
  String get locationSourceTypeAddress => 'Address';

  @override
  String get locationSourceTypePlusCode => 'Google Plus Code';

  @override
  String get locationSourceAddressHint => 'Street, postal code, city';

  @override
  String get locationSourcePlusCodeHint => 'e.g. 9F2PXXH7+F4 or XXH7+F4 Erfurt';

  @override
  String get locationResolveButton => 'Resolve';

  @override
  String get locationSelectCandidateTitle => 'Select Location';

  @override
  String get locationResolveErrorNotFound =>
      'Could not resolve address or Plus Code.';

  @override
  String get locationResolveErrorInvalidPlusCode =>
      'Enter a valid Plus Code (e.g. 9F2PXXH7+F4 or XXH7+F4 Erfurt).';

  @override
  String get tooltipIndicatorConditions => 'Activation conditions';

  @override
  String get taskInfoSuspendedForever => 'Indefinitely';

  @override
  String taskInfoSuspendedUntil(String timestamp, String duration) {
    return 'Until $timestamp ($duration)';
  }

  @override
  String get taskInfoDueLabel => 'Due';

  @override
  String taskInfoDueAt(String timestamp, String duration) {
    return '$timestamp ($duration)';
  }

  @override
  String taskInfoDueOverdue(String timestamp) {
    return 'Overdue ($timestamp)';
  }

  @override
  String taskInfoDurationDaysHours(String days, String hours) {
    return '$days d $hours h remaining';
  }

  @override
  String taskInfoDurationHoursMinutes(String hours, String minutes) {
    return '$hours h $minutes min remaining';
  }

  @override
  String taskInfoDurationMinutes(String minutes) {
    return '$minutes min remaining';
  }

  @override
  String taskInfoSubtasksProgress(String completed, String total) {
    return '$completed of $total completed';
  }

  @override
  String get taskInfoSubtasksAutoFinishSuffix => 'Auto-finish enabled';

  @override
  String taskInfoBlockedByProgress(String satisfied, String total) {
    return '$satisfied of $total satisfied';
  }

  @override
  String taskInfoRepeatEvery(String count, String unit) {
    return 'Every $count $unit';
  }

  @override
  String taskInfoRepeatCompletions(String count) {
    return 'Completed $count times';
  }

  @override
  String taskInfoLinksCount(String count) {
    return '$count links';
  }

  @override
  String get tooltipCopyNote => 'Copy note';

  @override
  String get noteCopiedSnackBar => 'Note copied to clipboard.';

  @override
  String get actionUndo => 'Undo';

  @override
  String taskCompletedUndoSnackBar(String title) {
    return 'Completed \"$title\".';
  }

  @override
  String taskDowngradedUndoSnackBar(String title) {
    return 'Downgraded \"$title\".';
  }

  @override
  String taskDeletedUndoSnackBar(String title) {
    return 'Deleted \"$title\".';
  }

  @override
  String get localWatchLabel => 'Watch for external file changes';

  @override
  String get localWatchDescription =>
      'Automatically merge edits saved by external editors, scripts, or file-sync tools.';

  @override
  String taskIdRowLabel(String id) {
    return 'ID: $id';
  }

  @override
  String get tooltipCopyTaskId => 'Copy task ID';

  @override
  String get taskIdCopiedSnackBar => 'Task ID copied to clipboard.';

  @override
  String get labelLinkErrorMaxExceeded =>
      'Maximum of 20 links per label reached.';

  @override
  String get tooltipCancelEditLink => 'Cancel link edit';

  @override
  String get tooltipEditLink => 'Edit link';

  @override
  String get tooltipMoveLinkDown => 'Move link down';

  @override
  String get tooltipMoveLinkUp => 'Move link up';

  @override
  String get tooltipSaveLink => 'Update link';

  @override
  String get dueLeadWindowSectionTitle => 'Deadline Auto-Priority';

  @override
  String get dueLeadWindowSectionDescription =>
      'Automatically prioritize scheduled open tasks into Focus and Ready when their due date approaches.';

  @override
  String get dueLeadWindowLabel => 'Lead Window';

  @override
  String get dueLeadWindowOff => 'Off (never auto-prioritize)';

  @override
  String get dueLeadWindowAtDue => 'At deadline (0 hours)';

  @override
  String get dueLeadWindow12Hours => '12 hours before deadline';

  @override
  String get dueLeadWindow24Hours => '24 hours before deadline (Default)';

  @override
  String get dueLeadWindow48Hours => '48 hours before deadline';

  @override
  String get dueLeadWindow7Days => '7 days before deadline';

  @override
  String get dueLeadWindowShort12Hours => '12 h';

  @override
  String get dueLeadWindowShort24Hours => '24 h';

  @override
  String get dueLeadWindowShort48Hours => '48 h';

  @override
  String get dueLeadWindowShort7Days => '7 d';

  @override
  String get taskDueAutoPrioritizeLabel => 'Auto-prioritize near deadline';

  @override
  String get taskDueAutoPrioritizeSubtitle =>
      'Pull ahead of regular queued tasks once the lead window opens.';

  @override
  String get taskInfoDueAutoPromotedActive =>
      'Prioritized by deadline lead window';

  @override
  String get taskInfoDueAutoPromoteAtDue => 'Auto-prioritizes at deadline';

  @override
  String taskInfoDueAutoPromoteScheduled(String window) {
    return 'Auto-prioritizes $window before deadline';
  }

  @override
  String get taskInfoDuePassiveHint =>
      'Informational deadline (auto-priority off)';

  @override
  String get taskInfoDueLeadWindowOffHint =>
      'Deadline auto-priority disabled in settings';

  @override
  String get taskSuspendedNoteLabel => 'Deferral note (optional)';

  @override
  String get taskSuspendedNoteHint => 'Why is this task deferred?';

  @override
  String get taskDueNoteLabel => 'Deadline note (optional)';

  @override
  String get taskDueNoteHint => 'Cutoff details or submission requirements';

  @override
  String get schedulingNoteErrorTooLong =>
      'Note must not exceed 2,000 characters.';

  @override
  String get schedulingNoteErrorInvalid =>
      'Note contains unsupported control characters.';

  @override
  String get repeatLeadDaysLabel => 'Preparation lead (days, optional)';

  @override
  String get repeatLeadDaysHint => '0 (activate immediately after rollover)';

  @override
  String get repeatLeadDaysErrorInvalid =>
      'Enter a whole number between 0 and 3650 days.';

  @override
  String taskInfoRepeatLeadDays(String days) {
    return 'Preparation window opens $days day(s) before due date';
  }

  @override
  String get historySectionTitle => 'History';

  @override
  String get historyEmptyHint => 'No history entries recorded yet.';

  @override
  String get historyEntryTextLabel => 'History entry';

  @override
  String get historyEntryTextHint => 'Add progress update or note';

  @override
  String get historyTimestampLabel => 'Timestamp (optional, defaults to now)';

  @override
  String get historyTimestampHint => 'YYYY-MM-DD HH:MM';

  @override
  String get tooltipAddHistoryEntry => 'Add history entry';

  @override
  String get tooltipEditHistoryEntry => 'Edit history entry';

  @override
  String get tooltipSaveHistoryEntry => 'Update history entry';

  @override
  String get tooltipCancelEditHistoryEntry => 'Cancel history edit';

  @override
  String get tooltipDeleteHistoryEntry => 'Delete history entry';

  @override
  String get historyErrorTextEmpty => 'Enter a history text.';

  @override
  String get historyErrorTextTooLong =>
      'History entry must not exceed 500 characters.';

  @override
  String get historyErrorTextInvalid =>
      'History entry contains unsupported control characters.';

  @override
  String get historyErrorTimestampInvalid =>
      'Enter a valid date (YYYY-MM-DD) and optional time (HH:MM).';

  @override
  String get historyErrorMaxExceeded =>
      'Maximum of 500 history entries per task reached.';

  @override
  String get syncConflictDeletionBanner =>
      'Synchronization paused: a concurrent edit conflicts with a deletion.';

  @override
  String get syncConflictRecoveryBanner =>
      'Synchronization paused: local changes require recovery after sync history advancement.';

  @override
  String get syncErrorGenerationRollbackBanner =>
      'Synchronization stopped: the shared file sync generation is older than the acknowledged state.';

  @override
  String taskInfoDueAnchorDetail(String anchor) {
    return 'Schedule anchor: $anchor';
  }

  @override
  String get fileReadErrorTitle => 'File Read Error';

  @override
  String get fileReadTargetLocal => 'Local file';

  @override
  String get fileReadTargetRemote => 'Remote file';

  @override
  String get fileReadStatusOk => 'OK';

  @override
  String get fileReadStatusUnreadable => 'Cannot be read';

  @override
  String get fileReadSummaryLocalOnly => 'The local file could not be read.';

  @override
  String get fileReadSummaryRemoteOnly => 'The remote file could not be read.';

  @override
  String get fileReadSummaryLocalFailedRemoteOk =>
      'Only the local file could not be read. The remote file is intact.';

  @override
  String get fileReadSummaryRemoteFailedLocalOk =>
      'Only the remote file could not be read. The local file is intact.';

  @override
  String get fileReadSummaryBothFailed =>
      'Both the local and remote files could not be read.';

  @override
  String fileReadReasonUnsupportedVersion(String version) {
    return 'Unsupported TDF version $version (expected 0.8.0).';
  }

  @override
  String fileReadReasonTdfFormat(String line, String details) {
    return 'Format error (line $line): $details';
  }

  @override
  String fileReadStatusEntryLine(String target, String status) {
    return '$target: $status';
  }

  @override
  String get errorSettingsCorrupt => 'Application settings could not be read.';

  @override
  String get errorSettingsUnsupportedVersion =>
      'Settings were created by a newer TierTask version. Update TierTask to avoid data loss.';

  @override
  String get errorSettingsCredentialStorageUnavailable =>
      'Secure credential storage is unavailable. WebDAV password could not be saved.';

  @override
  String get errorSettingsSaveFailed => 'Could not save application settings.';

  @override
  String get settingsRecoveredFromBackupNotice =>
      'Settings were restored from backup after a file error.';

  @override
  String get settingsResetAfterQuarantineNotice =>
      'Corrupt settings were backed up and reset to defaults.';

  @override
  String get themePaletteCalm => 'Calm';

  @override
  String get themePalettePlumUmber => 'Plum Umber';

  @override
  String get devBuildBadge => 'DEV';

  @override
  String get tierFocusSubtitle => 'Three active tasks. One clear next step.';

  @override
  String get tierReadySubtitle =>
      'Up to five tasks queued to pull into Focus next.';

  @override
  String get tierPlannedSubtitle =>
      'Active backlog feeding Ready automatically.';

  @override
  String get tierBlockedSubtitle =>
      'Suspended or waiting on prerequisites and activation conditions.';

  @override
  String get tierSomedaySubtitle => 'Collected outside the active queue.';

  @override
  String get tierCompletedSubtitle =>
      'Completed tasks are retained for 30 days (UTC).';

  @override
  String get sectionTasksTitle => 'Tasks';

  @override
  String get sectionToolsTitle => 'Tools';

  @override
  String get allTasksLabel => 'All Tasks';

  @override
  String get activeFilterClearTooltip => 'Clear filter (All Tasks)';

  @override
  String get actionBackToTasks => 'Back to tasks';

  @override
  String get actionBackToSearch => 'Back to search';

  @override
  String get actionDismiss => 'Dismiss';

  @override
  String get actionResolveConflict => 'Resolve conflict';

  @override
  String get actionResolveRecovery => 'Open recovery';

  @override
  String get actionComplete => 'Complete';

  @override
  String get actionRestore => 'Restore';

  @override
  String get actionCopy => 'Copy';

  @override
  String get searchViewTitle => 'All Tasks';

  @override
  String get searchViewSubtitle =>
      'Searching across all six tiers in the active context.';

  @override
  String get searchEmptyHint => 'No matching tasks found.';

  @override
  String get searchCloseTooltip => 'Close search';

  @override
  String get loadingBoardTitle => 'Loading workspace...';

  @override
  String get loadingBoardSubtitle =>
      'Reading TDF document and evaluating six tiers.';

  @override
  String get sidebarFilterLabelsPlaceholder => 'Filter labels...';

  @override
  String get sidebarFilterLabelsEmpty => 'No matching labels.';

  @override
  String get sidebarFilterLabelsToggle => 'Filter labels';

  @override
  String get sidebarManageLabels => 'Manage labels';

  @override
  String get sidebarCollapseLabels => 'Collapse labels';

  @override
  String get sidebarExpandLabels => 'Expand labels';

  @override
  String get sidebarFilterLocationsPlaceholder => 'Filter locations...';

  @override
  String get sidebarFilterLocationsEmpty => 'No matching locations.';

  @override
  String get sidebarFilterLocationsToggle => 'Filter locations';

  @override
  String get sidebarManageLocations => 'Manage locations';

  @override
  String get sidebarCollapseLocations => 'Collapse locations';

  @override
  String get sidebarExpandLocations => 'Expand locations';

  @override
  String get openLabelInManagerTooltip => 'Open and expand label in Manage';

  @override
  String get openLocationInManagerTooltip =>
      'Open and expand location in Manage';

  @override
  String get syncStatusLocalOnly => 'Local only';

  @override
  String get syncStatusSynced => 'Synced';

  @override
  String get syncStatusSyncing => 'Syncing...';

  @override
  String get syncStatusConflict => 'Conflict';

  @override
  String get syncStatusError => 'Sync error';

  @override
  String get rawTdfPreviewTitle => 'TDF Source';

  @override
  String get rawTdfPreviewSubtitle =>
      'Canonical LF-terminated TDF serialization of the current workspace board.';

  @override
  String rawTdfStatsSummary(String bytes, String lines) {
    return '$bytes bytes / 1 MiB · $lines lines / 16,384 max';
  }

  @override
  String get rawTdfCopiedNotice => 'TDF document copied to clipboard.';

  @override
  String get rawTdfLimitExceededTitle => 'Preview Limit Exceeded';

  @override
  String get rawTdfLimitExceededDescription =>
      'The serialized TDF document exceeds the canonical 1 MiB or 16,384-line limit (TDF 0.8.0 Section 6.2) and cannot be previewed inline.';

  @override
  String badgeMoreIndicators(String count) {
    return '+$count more';
  }

  @override
  String get badgeAutoPriority => 'Due · Prioritized';

  @override
  String badgeOverduePrefix(String date) {
    return 'Overdue: $date';
  }

  @override
  String badgeSuspendedUntil(String date) {
    return 'Suspended until $date';
  }

  @override
  String get badgeSuspendedForever => 'Suspended indefinitely';

  @override
  String badgeBlockedByProgress(String done, String total) {
    return '$done/$total prerequisites';
  }

  @override
  String badgeStepsProgress(String done, String total) {
    return '$done/$total steps';
  }

  @override
  String get badgeLinkSingular => '1 link';

  @override
  String badgeHistoryCount(String count) {
    return '$count history';
  }

  @override
  String get repeatEveryDay => 'Every day';

  @override
  String get repeatEveryWeek => 'Every week';

  @override
  String get repeatEveryMonth => 'Every month';

  @override
  String get completedReadOnlyPill => 'Completed · restore task to edit';

  @override
  String get inlineEditTitleTooltip => 'Edit title';

  @override
  String get inlineEditNameTooltip => 'Edit name';

  @override
  String get inlineAddNote => '+ Note';

  @override
  String get inlineAddLinks => '+ Links';

  @override
  String get inlineAddSubtasks => '+ Subtasks';

  @override
  String get inlineAddLabels => '+ Labels';

  @override
  String get inlineAddDue => '+ Due';

  @override
  String get inlineAddRepeat => '+ Repeat';

  @override
  String get inlineAddSuspend => '+ Suspend';

  @override
  String get inlineAddPrerequisites => '+ Prerequisites';

  @override
  String get inlineAddConditions => '+ Conditions';

  @override
  String get inlineClearAction => 'Clear';

  @override
  String get inlineDisableRepeatAction => 'Disable repeat';

  @override
  String get inlineResumeTaskAction => 'Resume task';

  @override
  String get inlineRepeatLeadNeedsDueHint =>
      'Set a due date to configure preparation lead days.';

  @override
  String get inlinePlacementSectionTitle => 'Queue & Priority';

  @override
  String get placementQueueOption => 'Queue';

  @override
  String get placementQueueHint => 'Append at the end of the active queue.';

  @override
  String get placementPriorityHint =>
      'Prioritize ahead of regular tasks in Focus or Ready.';

  @override
  String get placementSomedayHint =>
      'Park outside the active queue in Someday.';

  @override
  String get inlineDeleteTaskConfirm => 'Delete this task?';

  @override
  String get inlineDeleteLabelConfirm => 'Delete this label?';

  @override
  String get inlineDeleteLocationConfirm => 'Delete this location?';

  @override
  String get actionKeep => 'Keep';

  @override
  String get actionConfirmDelete => 'Yes, delete';

  @override
  String get actionDone => 'Done';

  @override
  String get actionOpenAsDraft => 'Open as draft';

  @override
  String get actionNewTaskCompact => 'New task';

  @override
  String get actionCreateTask => 'Create task';

  @override
  String get actionCreateLabel => 'Create label';

  @override
  String get actionCreateLocation => 'Create location';

  @override
  String get draftNewTaskTitle => 'New Task (Draft)';

  @override
  String get draftNewLabelTitle => 'New Label (Draft)';

  @override
  String get draftNewLocationTitle => 'New Location (Draft)';

  @override
  String get draftUncommittedHint =>
      'Uncommitted · saved to the TDF file only when you click Create.';

  @override
  String get quickCreateLabelHint => 'Quick-create a new label...';

  @override
  String get quickCreateLocationHint => 'Quick-create a new location...';

  @override
  String get labelsManagerSubtitle =>
      'Contexts, scoped queues, reference links, and inherited conditions.';

  @override
  String get locationsManagerSubtitle =>
      'Reusable locations for task and label GPS conditions.';

  @override
  String get labelPickerSearchPlaceholder => 'Search or create label...';

  @override
  String labelPickerFilterAll(String count) {
    return 'All ($count)';
  }

  @override
  String labelPickerFilterScoped(String count) {
    return 'Scoped ($count)';
  }

  @override
  String labelPickerFilterGlobal(String count) {
    return 'Global ($count)';
  }

  @override
  String get labelPickerNoMatches => 'No matching labels found.';

  @override
  String get labelPickerEmptyHint =>
      'No labels yet. Type a name above to create one.';

  @override
  String labelPickerCreateAndAssign(String name) {
    return 'Create & assign \"$name\"';
  }

  @override
  String labelPickerRemoveTooltip(String name) {
    return 'Remove label: $name';
  }

  @override
  String openTasksCountPill(String count) {
    return '$count open';
  }

  @override
  String get prerequisiteCyclePreventedHint => 'Cycle prevented';

  @override
  String get globalContextLabel => 'Global Context';

  @override
  String get scopedQueueLabel => 'Scoped Queue';

  @override
  String get conditionInheritLabel => 'Inherit label conditions';

  @override
  String get conditionCustomLabel => 'Custom condition';

  @override
  String get conditionSatisfiedStatus => 'Currently satisfied';

  @override
  String get conditionBlockedStatus => 'Currently unmet (blocked)';

  @override
  String get suspendedUntilModeLabel => 'Until a date and time';

  @override
  String get suspendedForeverModeLabel => 'Indefinitely';

  @override
  String get historyTimestampToggleTooltip => 'Set timestamp';

  @override
  String get historyErrorDuplicate =>
      'An identical history entry with this timestamp already exists.';

  @override
  String locationRadiusReadout(String radius) {
    return 'Radius: $radius';
  }

  @override
  String get entityRemovedExternallyNotice =>
      'This item was removed by an external update.';

  @override
  String get taskCompletedExternallyNotice =>
      'This task was completed by an external update.';

  @override
  String get labelIdCopiedNotice => 'Label ID copied to clipboard.';

  @override
  String get locationIdCopiedNotice => 'Location ID copied to clipboard.';

  @override
  String taskRestoredNotice(String title) {
    return '\"$title\" restored.';
  }

  @override
  String taskCompletedRepeatNotice(String title) {
    return '\"$title\" completed and rescheduled for the next cycle.';
  }

  @override
  String get actionUndoneNotice => 'Action undone.';

  @override
  String actionUndoneRemainingNotice(String remaining) {
    return 'Action undone ($remaining more in history).';
  }

  @override
  String workspaceSwitchedNotice(String name) {
    return 'Switched workspace: $name';
  }

  @override
  String get gpsAppliedNotice => 'Current GPS position applied.';

  @override
  String get locationResolvedNotice => 'Source resolved to coordinates.';

  @override
  String get labelSavedNotice => 'Label saved.';

  @override
  String get labelDeletedNotice => 'Label deleted.';

  @override
  String get locationSavedNotice => 'Location saved.';

  @override
  String get locationDeletedNotice => 'Location deleted.';

  @override
  String get noticeTaskSaved => 'Task saved.';

  @override
  String noticeTaskSavedInTier(String tier) {
    return 'Saved · now in $tier';
  }

  @override
  String noticeTaskMovedToScopedQueue(String label) {
    return 'Moved to scoped queue: $label';
  }

  @override
  String get noticePriorityEnabled => 'Task prioritized';

  @override
  String get noticePriorityDisabled => 'Priority cleared';

  @override
  String get noticeMovedToSomeday => 'Moved to Someday';

  @override
  String get noticeMovedToQueue => 'Activated in queue';

  @override
  String noticeLabelAdded(String name) {
    return 'Label added: $name';
  }

  @override
  String noticeLabelRemoved(String name) {
    return 'Label removed: $name';
  }

  @override
  String noticeLabelCreatedAndAssigned(String name) {
    return 'Label created and assigned: $name';
  }

  @override
  String settingsWorkspaceSubtitle(String workspace) {
    return 'Configuration for active workspace \"$workspace\".';
  }

  @override
  String get settingsAutoSavedBadge => 'Auto-saved';

  @override
  String get settingsUnsavedChangesBadge => 'Unsaved changes';

  @override
  String get settingsMoveDesktopOnlyTooltip =>
      'Moving directories is available only on desktop platforms (Linux/Windows).';

  @override
  String get webDavUrlUserinfoError =>
      'URL must not contain embedded credentials (user:pass@).';

  @override
  String get webDavPathInvalidError =>
      'Invalid remote file path (\"..\", backslashes, and control characters are forbidden).';

  @override
  String get logViewerSubtitle =>
      'Structured runtime entries (credentials, raw GPS coordinates, and notes redacted).';

  @override
  String get logFilterSubsystemLabel => 'Subsystem';

  @override
  String get logActionUpload => 'Upload Log';

  @override
  String get logActionClear => 'Clear';

  @override
  String get conflictResolutionTitle =>
      'Resolve Deletion Conflicts (TDF-DEL-003)';

  @override
  String get conflictResolutionSubtitle =>
      'Choose whether to keep the concurrent local edit or confirm deletion for each conflicted item.';

  @override
  String get conflictKeepEditOption => 'Keep Edit (Undelete)';

  @override
  String get conflictConfirmDeleteOption => 'Confirm Deletion';

  @override
  String get conflictApplyAndSyncAction => 'Apply Decisions & Sync';

  @override
  String get conflictResolvedNotice =>
      'Deletion conflicts resolved. Synchronization resumed.';

  @override
  String get recoveryResolutionTitle =>
      'Recover After History Advancement (TDF-REC-002)';

  @override
  String get recoveryResolutionSubtitle =>
      'Shared deletion history advanced past the last acknowledged state. Choose an action for each affected local item.';

  @override
  String get recoveryAsNewOption => 'Recover as New (fresh ID)';

  @override
  String get recoveryDiscardLocalOption => 'Discard Local Change';

  @override
  String get recoveryApplyAndSyncAction => 'Apply Recovery & Sync';

  @override
  String get recoveryResolvedNotice =>
      'Recovery completed. Synchronization resumed.';

  @override
  String get entityKindTaskBadge => 'TASK';

  @override
  String get entityKindLabelBadge => 'LABEL';

  @override
  String get entityKindLocationBadge => 'LOCATION';

  @override
  String get tooltipCloseApp => 'Close TierTask';

  @override
  String get tooltipScrollToTop => 'Scroll to Top';

  @override
  String get tooltipCopyFilteredLog => 'Copy Filtered';

  @override
  String get logFilteredCopiedSnackBar =>
      'Filtered diagnostic log copied to clipboard.';
}
