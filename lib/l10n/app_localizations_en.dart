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
  String get markdownPreviewTitle => 'Raw TDF';

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
  String get sectionAllTasks => 'ALL TASKS';

  @override
  String get sectionLabels => 'LABELS';

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

  @override
  String get tooltipClearInput => 'Clear text';

  @override
  String get actionChangeDirectory => 'Change Directory';

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
  String get tooltipIndicatorPriority => 'Priority';

  @override
  String get tooltipIndicatorRepeat => 'Repeating task';

  @override
  String get tooltipIndicatorSubtasks => 'Subtasks';

  @override
  String get tooltipIndicatorSubtasksAutoFinish => 'Subtasks (auto-finish)';

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
  String get editLabelTitle => 'Edit Label';

  @override
  String get tooltipEditLabel => 'Edit label';

  @override
  String get labelDetailsSectionTitle => 'Label Details';

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
  String get tooltipIndicatorLinks => 'Has links';

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
  String get tooltipScrollToBottom => 'Scroll to Bottom';

  @override
  String get tooltipClearLog => 'Clear Log';

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
  String errorUnsupportedTdfVersionLocal(String version) {
    return 'The local file uses unsupported file version $version. Please update TierTask to a newer version.';
  }

  @override
  String errorUnsupportedTdfVersionRemote(String version) {
    return 'The remote file uses unsupported file version $version. Please update TierTask to a newer version.';
  }

  @override
  String errorUnsupportedTdfVersionBoth(String version) {
    return 'The local and remote files use unsupported file version $version. Please update TierTask to a newer version.';
  }

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
  String get logMetadataSectionTitle => 'Session Metadata';

  @override
  String logMetadataFile(String fileName) {
    return 'File: $fileName';
  }

  @override
  String logMetadataVersion(String version) {
    return 'Version: $version';
  }

  @override
  String logMetadataPlatform(String platform) {
    return 'Platform: $platform';
  }

  @override
  String logMetadataWorkspace(String workspace) {
    return 'Workspace: $workspace';
  }

  @override
  String logMetadataTimeZone(String timeZone) {
    return 'Time Zone: $timeZone';
  }

  @override
  String logMetadataStats(String entries, String warnings, String errors) {
    return 'Entries: $entries | Warnings: $warnings | Errors: $errors';
  }

  @override
  String get logFilterAllTags => 'All';

  @override
  String get tooltipSyncLogWebDav => 'Sync log to WebDAV';

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
  String get tooltipConditionDayAny =>
      'Explicitly overrides all weekday restrictions from assigned labels so this task is active on any day.';

  @override
  String get tooltipConditionTimeAny =>
      'Explicitly overrides all time window restrictions from assigned labels so this task is active at any time.';

  @override
  String get tooltipConditionLocationAny =>
      'Explicitly overrides all location restrictions from assigned labels so this task is active at any location.';

  @override
  String get tooltipTaskEditorPriority =>
      'Marks this task as priority so it is pulled into Focus or Ready ahead of standard tasks.';

  @override
  String get tooltipTaskEditorSomeday =>
      'Parks this task in the Someday backlog without pulling it into active tiers.';

  @override
  String get tooltipTaskEditorSuspended =>
      'Defers this task to Blocked (optionally until a chosen timestamp) and disables condition evaluation while active.';

  @override
  String get tooltipTaskEditorRepeat =>
      'Automatically reschedules this task after the configured interval upon completion and resets all subtasks.';

  @override
  String get tooltipTaskEditorAutoFinish =>
      'Automatically completes the entire task as soon as all subtasks are checked off.';

  @override
  String get drawerLocations => 'Locations';

  @override
  String get createNewLocation => 'Create new location';

  @override
  String get editLocationsTitle => 'Edit locations';

  @override
  String get editLocationTitle => 'Edit Location';

  @override
  String get emptyLocationsHint => 'No locations created yet.';

  @override
  String get tooltipDeleteLocation => 'Delete location';

  @override
  String get tooltipEditLocation => 'Edit location';

  @override
  String get locationDetailsSectionTitle => 'Location Details';

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
  String get labelScopedSwitchTitle => 'Scoped Label';

  @override
  String get labelScopedSwitchSubtitle =>
      'Hide tasks with this label unless this label filter is active.';

  @override
  String get taskDueButtonLabel => 'Due (optional)';

  @override
  String get taskDueClearTooltip => 'Clear due timestamp';

  @override
  String pillDuePrefix(String date) {
    return 'Due: $date';
  }

  @override
  String get errorLocalFileCasExhausted =>
      'Local file was modified concurrently and exceeded maximum merge retries.';

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
  String get tooltipIndicatorSuspended => 'Suspended';

  @override
  String get tooltipIndicatorBlockedBy => 'Prerequisite tasks';

  @override
  String get tooltipIndicatorConditions => 'Activation conditions';

  @override
  String tooltipIndicatorSummary(String count) {
    return 'Task information ($count indicators)';
  }

  @override
  String get taskInfoDialogTitle => 'Task Information';

  @override
  String get taskInfoPriorityValue => 'Prioritized in queue';

  @override
  String get taskInfoSuspendedForever => 'Indefinitely';

  @override
  String taskInfoSuspendedUntil(String timestamp, String duration) {
    return 'Until $timestamp ($duration)';
  }

  @override
  String taskInfoSuspendedElapsed(String timestamp) {
    return 'Elapsed ($timestamp)';
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
  String get deleteTaskDialogTitle => 'Delete Task';

  @override
  String deleteTaskConfirmMessage(String title) {
    return 'Delete task \"$title\"? This action can be undone while the workspace remains open.';
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
}
