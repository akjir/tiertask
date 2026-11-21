import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// Application title shown in the app bar and window header.
  ///
  /// In en, this message translates to:
  /// **'TierTask'**
  String get appTitle;

  /// Display name for tier 1 (Focus).
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get tier1Name;

  /// Display name for tier 2 (Ready).
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get tier2Name;

  /// Display name for tier 3 (Planned).
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get tier3Name;

  /// Display name for tier 4 (Blocked).
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get tier4Name;

  /// Display name for tier 5 (Someday).
  ///
  /// In en, this message translates to:
  /// **'Someday'**
  String get tier5Name;

  /// Display name for tier 6 (Completed).
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get tier6Name;

  /// Empty-state hint shown when tier 1 (Focus) contains no tasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks in Focus. Tasks from Ready or Planned automatically move up here.'**
  String get emptyFocusHint;

  /// Empty-state hint shown when tier 2 (Ready) contains no tasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks in Ready.'**
  String get emptyReadyHint;

  /// Empty-state hint shown when tier 3 (Planned) contains no tasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks in active backlog (Planned).'**
  String get emptyPlannedHint;

  /// Empty-state hint shown when tier 4 (Blocked) contains no tasks.
  ///
  /// In en, this message translates to:
  /// **'No blocked tasks (Blocked).'**
  String get emptyBlockedHint;

  /// Empty-state hint shown when tier 5 (Someday) contains no tasks.
  ///
  /// In en, this message translates to:
  /// **'No ideas stored in Someday.'**
  String get emptySomedayHint;

  /// Empty-state hint shown when tier 6 (Completed) contains no tasks.
  ///
  /// In en, this message translates to:
  /// **'No completed tasks from the last 30 days.'**
  String get emptyCompletedHint;

  /// Tooltip for the WebDAV synchronization button in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Synchronize with WebDAV'**
  String get tooltipSyncWebDav;

  /// Button label to close a dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// Banner message shown when WebDAV synchronization is not configured.
  ///
  /// In en, this message translates to:
  /// **'Local mode active. Configure WebDAV for synchronization.'**
  String get unconfiguredBannerText;

  /// Button label to open configuration settings from the banner.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get actionConfigure;

  /// Button label to navigate to the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get actionSettings;

  /// Button label to retry a failed synchronization operation.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// Toggle button label for marking a new task as priority in the quick-add bar.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get quickAddPriority;

  /// Tooltip for the downward arrow button that downgrades a task.
  ///
  /// In en, this message translates to:
  /// **'Downgrade task'**
  String get tooltipDowngradeTask;

  /// Input label for the task name field in the extended task view.
  ///
  /// In en, this message translates to:
  /// **'Task Name'**
  String get taskNameLabel;

  /// Validation error shown when the task name is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a task name.'**
  String get taskNameErrorEmpty;

  /// Validation error shown when another task already uses the same name.
  ///
  /// In en, this message translates to:
  /// **'A task with this name already exists.'**
  String get taskNameErrorDuplicate;

  /// Input label for the optional task note field in the extended task view.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get taskNoteLabel;

  /// Placeholder hint for the optional task note input field.
  ///
  /// In en, this message translates to:
  /// **'Optional note or description...'**
  String get taskNoteHint;

  /// Toggle label for automatically completing a task when all subtasks are done.
  ///
  /// In en, this message translates to:
  /// **'Auto-finish'**
  String get subtasksAutoFinishLabel;

  /// Section heading for subtasks inside the extended task creation view.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get subtasksSectionTitle;

  /// Placeholder hint inside the subtask input field.
  ///
  /// In en, this message translates to:
  /// **'Add subtask...'**
  String get subtaskInputHint;

  /// Tooltip for the button that adds a subtask to the task being created.
  ///
  /// In en, this message translates to:
  /// **'Add subtask'**
  String get tooltipAddSubtask;

  /// Tooltip for the button that removes a subtask from the list.
  ///
  /// In en, this message translates to:
  /// **'Remove subtask'**
  String get tooltipRemoveSubtask;

  /// Placeholder hint inside the quick-add text field for the selected tier.
  ///
  /// In en, this message translates to:
  /// **'Add new task to {heading}...'**
  String quickAddHint(String heading);

  /// Button label to add a new task.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// Button label to cancel an action or dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Button label to save changes.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// App bar title for the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section heading for display language selection in settings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSectionTitle;

  /// Helper description explaining how the display language setting behaves.
  ///
  /// In en, this message translates to:
  /// **'Select the display language. System uses German on German systems and English otherwise.'**
  String get languageSectionDescription;

  /// Option label to follow the operating system locale.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// Option label for the English display language.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Option label for the German display language.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// Section heading for color theme selection in settings.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeSectionTitle;

  /// Helper description explaining how the color theme setting behaves.
  ///
  /// In en, this message translates to:
  /// **'Select the color theme. System follows the operating system brightness setting.'**
  String get themeSectionDescription;

  /// Option label to follow the operating system brightness setting.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Option label for the light color theme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Option label for the dark color theme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Section heading for storage mode selection in settings.
  ///
  /// In en, this message translates to:
  /// **'Storage Mode'**
  String get storageModeSectionTitle;

  /// Helper description explaining the storage mode options.
  ///
  /// In en, this message translates to:
  /// **'Select whether tasks are stored in a local TDF file, on a WebDAV server, or in both locations.'**
  String get storageModeSectionDescription;

  /// Option label for local-only TDF file storage.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get storageModeLocal;

  /// Option label for WebDAV-only TDF synchronization.
  ///
  /// In en, this message translates to:
  /// **'WebDAV'**
  String get storageModeWebDav;

  /// Option label for combined local and WebDAV TDF storage.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get storageModeBoth;

  /// Section heading for local TDF file settings.
  ///
  /// In en, this message translates to:
  /// **'Local TDF File'**
  String get localSectionTitle;

  /// Helper description explaining local TDF file persistence.
  ///
  /// In en, this message translates to:
  /// **'Stores all tasks in a local TDF file on this device.'**
  String get localSectionDescription;

  /// Placeholder hint for the local TDF file name field.
  ///
  /// In en, this message translates to:
  /// **'tiertask.tdf or t2.tdf'**
  String get localFilePathHint;

  /// Label above the resolved local TDF file path preview.
  ///
  /// In en, this message translates to:
  /// **'Resolved Local File Path:'**
  String get resolvedLocalPathLabel;

  /// Section heading for WebDAV synchronization settings.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Synchronization'**
  String get webdavSectionTitle;

  /// Helper description explaining WebDAV TDF synchronization.
  ///
  /// In en, this message translates to:
  /// **'TierTask stores all tasks in a single TDF file (tiertask.tdf) on your WebDAV server. Use an application password when supported by your server.'**
  String get webdavSectionDescription;

  /// Input label for the WebDAV server URL field.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Server URL'**
  String get serverUrlLabel;

  /// Validation error shown when the WebDAV server URL is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a server URL.'**
  String get serverUrlErrorEmpty;

  /// Input label for the WebDAV username field.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// Validation error shown when the WebDAV username is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username.'**
  String get usernameErrorEmpty;

  /// Input label for the WebDAV password or application password field.
  ///
  /// In en, this message translates to:
  /// **'App Password / Password'**
  String get passwordLabel;

  /// Tooltip for the button that reveals the password text.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get tooltipShowPassword;

  /// Tooltip for the button that obscures the password text.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get tooltipHidePassword;

  /// Validation error shown when the WebDAV password is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password or app password.'**
  String get passwordErrorEmpty;

  /// Input label for the remote TDF file name or path field.
  ///
  /// In en, this message translates to:
  /// **'TDF File Name / Path'**
  String get filePathLabel;

  /// Placeholder hint for the remote TDF file name field.
  ///
  /// In en, this message translates to:
  /// **'tiertask.tdf or t2.tdf'**
  String get filePathHint;

  /// Label above the resolved full WebDAV URL preview.
  ///
  /// In en, this message translates to:
  /// **'Resolved WebDAV Endpoint (GET / PUT):'**
  String get resolvedEndpointLabel;

  /// Status message shown when settings are saved locally.
  ///
  /// In en, this message translates to:
  /// **'Settings saved locally.'**
  String get credentialsSavedBanner;

  /// Status message shown when WebDAV connection and synchronization succeed.
  ///
  /// In en, this message translates to:
  /// **'Connection succeeded. TDF file synchronized with WebDAV.'**
  String get connectionSuccessBanner;

  /// Button label to test the WebDAV connection and synchronize immediately.
  ///
  /// In en, this message translates to:
  /// **'Test Connection / Sync Now'**
  String get actionTestConnectionAndSync;

  /// Error message shown when attempting WebDAV sync before configuring credentials.
  ///
  /// In en, this message translates to:
  /// **'Please configure WebDAV in Settings first.'**
  String get errorWebDavNotConfigured;

  /// Error message shown when the configured WebDAV URL is invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid WebDAV server URL.'**
  String get errorInvalidServerUrl;

  /// Error message shown when HTTP 401/403 occurs while loading from WebDAV.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Please check username and app password.'**
  String get errorAuthFailedLoad;

  /// Error message shown when loading the TDF file fails with a non-success status.
  ///
  /// In en, this message translates to:
  /// **'Failed to load TDF file from server.'**
  String get errorLoadMarkdownFailed;

  /// Error message shown when the WebDAV server cannot be reached over the network.
  ///
  /// In en, this message translates to:
  /// **'Network error: Server unreachable ({details}).'**
  String errorNetworkUnreachable(String details);

  /// Error message shown when a WebDAV load request times out.
  ///
  /// In en, this message translates to:
  /// **'Connection to WebDAV server timed out.'**
  String get errorTimeoutLoad;

  /// Error message shown when TLS handshake fails while loading from WebDAV.
  ///
  /// In en, this message translates to:
  /// **'TLS/SSL connection error: {details}'**
  String errorTlsLoad(String details);

  /// Error message shown when an unexpected error occurs while loading from WebDAV.
  ///
  /// In en, this message translates to:
  /// **'Unexpected WebDAV error while loading: {details}'**
  String errorUnexpectedLoad(String details);

  /// Error message shown when HTTP 401/403 occurs while saving to WebDAV.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed while saving. Please check app password.'**
  String get errorAuthFailedSave;

  /// Error message shown when saving the TDF file fails with a non-success status.
  ///
  /// In en, this message translates to:
  /// **'Failed to save TDF file on server.'**
  String get errorSaveMarkdownFailed;

  /// Error message shown when a network error occurs while saving to WebDAV.
  ///
  /// In en, this message translates to:
  /// **'Network error while saving ({details}).'**
  String errorNetworkSave(String details);

  /// Error message shown when a WebDAV save request times out.
  ///
  /// In en, this message translates to:
  /// **'Timed out while saving to WebDAV server.'**
  String get errorTimeoutSave;

  /// Error message shown when a TLS error occurs while saving to WebDAV.
  ///
  /// In en, this message translates to:
  /// **'TLS/SSL error while saving: {details}'**
  String errorTlsSave(String details);

  /// Error message shown when an unexpected error occurs while saving to WebDAV.
  ///
  /// In en, this message translates to:
  /// **'Unexpected WebDAV error while saving: {details}'**
  String errorUnexpectedSave(String details);

  /// Error message shown when the configured local TDF file path is invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid local TDF file name or path.'**
  String get errorInvalidLocalFilePath;

  /// Error message shown when a TDF file exceeds maxFileBytes.
  ///
  /// In en, this message translates to:
  /// **'TDF file exceeds the maximum allowed size.'**
  String get errorLocalFileTooLarge;

  /// Error message shown when reading the local TDF file fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to read local TDF file ({details}).'**
  String errorLoadLocalFileFailed(String details);

  /// Error message shown when writing the local TDF file fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to write local TDF file ({details}).'**
  String errorSaveLocalFileFailed(String details);

  /// Tooltip for the top-left navigation menu button.
  ///
  /// In en, this message translates to:
  /// **'Open menu'**
  String get tooltipMenu;

  /// Tooltip for the top-right search button.
  ///
  /// In en, this message translates to:
  /// **'Search tasks'**
  String get tooltipSearch;

  /// Placeholder hint inside the landing page search field.
  ///
  /// In en, this message translates to:
  /// **'Search tasks...'**
  String get searchHint;

  /// Button tooltip and sheet title for managing labels.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get drawerLabels;

  /// Placeholder hint inside the label name input field.
  ///
  /// In en, this message translates to:
  /// **'New label name...'**
  String get labelNameHint;

  /// Empty-state hint shown when no labels exist.
  ///
  /// In en, this message translates to:
  /// **'No labels created yet.'**
  String get emptyLabelsHint;

  /// Tooltip for the button that deletes a label.
  ///
  /// In en, this message translates to:
  /// **'Delete label'**
  String get tooltipDeleteLabel;

  /// Button label to edit labels in the navigation drawer.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// Toggle chip label for marking a task as suspended in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get taskSuspendedLabel;

  /// Input field label for an optional suspension timestamp in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Suspended until (optional)'**
  String get taskSuspendedUntilLabel;

  /// Validation error shown when the suspended-until timestamp is malformed.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid timestamp (YYYY-MM-DD or YYYY-MM-DD HH:MM).'**
  String get taskSuspendedErrorInvalid;

  /// Informational banner shown when a task is suspended and condition evaluation is disabled.
  ///
  /// In en, this message translates to:
  /// **'Suspended is active: evaluation of all other conditions is disabled and this task appears under Blocked.'**
  String get taskSuspendedDisablesConditionsHint;

  /// Toggle chip label for the global condition any reset directive.
  ///
  /// In en, this message translates to:
  /// **'Any (ignore label conditions)'**
  String get conditionGlobalAnyLabel;

  /// Title for the weekday condition group in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get conditionDayGroupTitle;

  /// Toggle chip label for the day any group reset directive.
  ///
  /// In en, this message translates to:
  /// **'Any day'**
  String get conditionDayAnyLabel;

  /// Short label for Monday.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// Short label for Tuesday.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// Short label for Wednesday.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// Short label for Thursday.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// Short label for Friday.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// Short label for Saturday.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// Short label for Sunday.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// Title for the time window condition group in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Time Windows'**
  String get conditionTimeGroupTitle;

  /// Toggle chip label for the time any group reset directive.
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get conditionTimeAnyLabel;

  /// Input hint for the start of a time window condition.
  ///
  /// In en, this message translates to:
  /// **'Start (HH:MM)'**
  String get conditionTimeStartHint;

  /// Input hint for the end of a time window condition.
  ///
  /// In en, this message translates to:
  /// **'End (HH:MM)'**
  String get conditionTimeEndHint;

  /// Validation error shown when a time window input is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter valid 24-hour times (HH:MM).'**
  String get conditionTimeErrorInvalid;

  /// Tooltip for the button that adds a time window condition.
  ///
  /// In en, this message translates to:
  /// **'Add time window'**
  String get tooltipAddTimeCondition;

  /// Tooltip for the button that removes a time window condition.
  ///
  /// In en, this message translates to:
  /// **'Remove time window'**
  String get tooltipRemoveTimeCondition;

  /// Title for the GPS location condition group in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Locations (GPS)'**
  String get conditionLocationGroupTitle;

  /// Toggle chip label for the location any group reset directive.
  ///
  /// In en, this message translates to:
  /// **'Any location'**
  String get conditionLocationAnyLabel;

  /// Validation error shown when a GPS location condition input is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter valid latitude, longitude, and radius (e.g. 200m or 1.5km).'**
  String get conditionLocationErrorInvalid;

  /// Section card title for labels in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Labels'**
  String get taskLabelsSectionTitle;

  /// Section card title for prerequisite tasks in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Prerequisite Tasks'**
  String get taskBlockedBySectionTitle;

  /// Section card description for prerequisite tasks in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Search for open tasks by name and select tasks that must be finished before this task becomes active.'**
  String get taskBlockedBySectionDescription;

  /// Placeholder hint for searching prerequisite tasks by name.
  ///
  /// In en, this message translates to:
  /// **'Search tasks by name...'**
  String get blockedBySearchHint;

  /// Empty-state text shown when no prerequisite task matches the search query.
  ///
  /// In en, this message translates to:
  /// **'No matching tasks found.'**
  String get blockedBySearchNoResults;

  /// Tooltip for clearing the prerequisite task search input.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get tooltipClearSearch;

  /// Section card title for activation conditions in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Activation Conditions'**
  String get taskConditionsSectionTitle;

  /// Tooltip for the date picker button on the suspended timestamp field.
  ///
  /// In en, this message translates to:
  /// **'Pick date'**
  String get tooltipPickDate;

  /// Tooltip for the time picker button on the suspended timestamp field.
  ///
  /// In en, this message translates to:
  /// **'Pick time'**
  String get tooltipPickTime;

  /// Settings section title for choosing the Material 3 color palette.
  ///
  /// In en, this message translates to:
  /// **'Color Palette'**
  String get themePaletteSectionTitle;

  /// Settings section description for choosing the Material 3 color palette.
  ///
  /// In en, this message translates to:
  /// **'Select the Material 3 color palette for surfaces and highlights.'**
  String get themePaletteSectionDescription;

  /// Settings section title for choosing the local time zone mode and offset.
  ///
  /// In en, this message translates to:
  /// **'Time Zone'**
  String get timeZoneSectionTitle;

  /// Settings section description for choosing the local time zone mode and offset.
  ///
  /// In en, this message translates to:
  /// **'Select whether the local time zone is detected automatically from the device or set manually for task conditions and display.'**
  String get timeZoneSectionDescription;

  /// Option label for automatic device time zone detection.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get timeZoneModeAutomatic;

  /// Option label for manual UTC offset selection.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get timeZoneModeManual;

  /// Dropdown label for selecting the manual UTC offset.
  ///
  /// In en, this message translates to:
  /// **'UTC Offset'**
  String get timeZoneOffsetLabel;

  /// Toggle chip label for enabling task recurrence in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeatFlagLabel;

  /// Input label for the numeric recurrence interval count.
  ///
  /// In en, this message translates to:
  /// **'Repeat every'**
  String get repeatIntervalLabel;

  /// Label for daily recurrence unit.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get repeatUnitDays;

  /// Label for weekly recurrence unit.
  ///
  /// In en, this message translates to:
  /// **'Weeks'**
  String get repeatUnitWeeks;

  /// Label for monthly recurrence unit.
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get repeatUnitMonths;

  /// Validation error shown when the repeat interval count is outside 1..3650.
  ///
  /// In en, this message translates to:
  /// **'Please enter an interval between 1 and 3650.'**
  String get repeatErrorInvalid;

  /// Tooltip for the button that clears the text in a focused input field.
  ///
  /// In en, this message translates to:
  /// **'Clear text'**
  String get tooltipClearInput;

  /// Status message shown when the local TDF directory is changed and the file is moved.
  ///
  /// In en, this message translates to:
  /// **'Local TDF directory updated and file moved.'**
  String get localDirectoryMovedBanner;

  /// Error message shown when a regular file already exists at the destination TDF path.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: A file already exists at the target path ({path}).'**
  String errorMoveTargetFileExists(String path);

  /// Error message shown when a directory already exists at the destination TDF path.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: A directory with this name already exists at the target path ({path}).'**
  String errorMoveTargetDirectoryExists(String path);

  /// Error message shown when a symbolic link already exists at the destination TDF path.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: A symbolic link already exists at the target path ({path}).'**
  String errorMoveTargetSymlinkExists(String path);

  /// Error message shown when the current TDF source path is a symbolic link.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: The source path is a symbolic link ({path}).'**
  String errorMoveSourceIsSymlink(String path);

  /// Error message shown when the current TDF source path is a directory.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: The source path is a directory ({path}).'**
  String errorMoveSourceIsDirectory(String path);

  /// Error message shown when the selected target directory does not exist.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: The target directory does not exist ({path}).'**
  String errorMoveTargetDirectoryNotFound(String path);

  /// Error message shown when the selected target directory path is a file or symlink instead of a directory.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: The selected target path is not a directory ({path}).'**
  String errorMoveTargetNotADirectory(String path);

  /// Error message shown when filesystem permissions prevent moving the TDF file.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: Permission denied ({path}).'**
  String errorMovePermissionDenied(String path);

  /// Error message shown when the target or source filesystem is read-only.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: The file system is read-only ({path}).'**
  String errorMoveReadOnlyFileSystem(String path);

  /// Error message shown when there is insufficient disk space to move the TDF file.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: Not enough free disk space ({path}).'**
  String errorMoveDiskFull(String path);

  /// Error message shown when the TDF file is locked by another process.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: The file is locked or in use by another process ({path}).'**
  String errorMoveFileLocked(String path);

  /// Error message shown when the destination TDF path exceeds OS length limits.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file: The file path or name is too long ({path}).'**
  String errorMovePathTooLong(String path);

  /// Fallback error message shown when moving the local TDF file fails for another reason.
  ///
  /// In en, this message translates to:
  /// **'Cannot move TDF file ({details}).'**
  String errorMoveLocalFileFailed(String details);

  /// Error message shown when the target TDF file path collides with another workspace.
  ///
  /// In en, this message translates to:
  /// **'Another workspace already uses this TDF file path.'**
  String get errorDuplicateWorkspaceFilePath;

  /// Tooltip for the active workspace card beneath the TierTask title in the navigation drawer.
  ///
  /// In en, this message translates to:
  /// **'Switch or manage workspaces'**
  String get tooltipManageWorkspaces;

  /// Title of the workspace management dialog.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspacesDialogTitle;

  /// Subtitle description inside the workspace management dialog.
  ///
  /// In en, this message translates to:
  /// **'Switch between isolated task boards or create a new workspace with its own TDF file.'**
  String get workspacesDialogDescription;

  /// Badge label displayed on the currently active workspace in the workspace management dialog.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get workspaceActiveBadge;

  /// Placeholder hint inside the input field for creating a new workspace.
  ///
  /// In en, this message translates to:
  /// **'New workspace name...'**
  String get createWorkspaceHint;

  /// Helper label showing the suggested .tdf filename for a new workspace.
  ///
  /// In en, this message translates to:
  /// **'TDF file: {fileName}'**
  String workspaceSuggestedFileLabel(String fileName);

  /// Tooltip for the button that creates and activates a new workspace.
  ///
  /// In en, this message translates to:
  /// **'Create workspace'**
  String get tooltipCreateWorkspace;

  /// Tooltip for the button that starts or saves inline renaming of a workspace.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get tooltipRenameWorkspace;

  /// Tooltip for the button that deletes a workspace.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace'**
  String get tooltipDeleteWorkspace;

  /// Inline confirmation message shown before removing a workspace.
  ///
  /// In en, this message translates to:
  /// **'Remove workspace \"{name}\"? Its TDF file will not be deleted.'**
  String deleteWorkspaceConfirmMessage(String name);

  /// Button label to confirm deleting an item.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// Validation error shown when a workspace name is empty, contains control characters, or exceeds 128 characters.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid workspace name (1–128 characters).'**
  String get errorWorkspaceNameEmpty;

  /// Validation error shown when another workspace already uses the same display name.
  ///
  /// In en, this message translates to:
  /// **'A workspace with this name already exists.'**
  String get errorWorkspaceNameDuplicate;

  /// Validation error shown when attempting to delete the only remaining workspace.
  ///
  /// In en, this message translates to:
  /// **'The last remaining workspace cannot be deleted.'**
  String get errorWorkspaceCannotDeleteLast;

  /// Validation error shown when attempting to create more than 32 workspaces.
  ///
  /// In en, this message translates to:
  /// **'Maximum number of workspaces (32) reached.'**
  String get errorWorkspaceMaxExceeded;

  /// Section heading for foreground location determination settings.
  ///
  /// In en, this message translates to:
  /// **'Location Determination'**
  String get locationSectionTitle;

  /// Helper description explaining foreground-only location determination.
  ///
  /// In en, this message translates to:
  /// **'Determine your current place and GPS coordinates while the app is running to evaluate location conditions.'**
  String get locationSectionDescription;

  /// Option label to disable location determination.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get locationOff;

  /// Option label to enable foreground location determination.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get locationOn;

  /// Tooltip for the top bar button that opens the location status popup.
  ///
  /// In en, this message translates to:
  /// **'Location status'**
  String get tooltipLocationStatus;

  /// Title of the popup dialog displaying the current location status.
  ///
  /// In en, this message translates to:
  /// **'Location Status'**
  String get locationDialogTitle;

  /// Status message shown while foreground location determination is in progress.
  ///
  /// In en, this message translates to:
  /// **'Searching for location...'**
  String get locationStatusSearching;

  /// Status message shown when the current location has been determined.
  ///
  /// In en, this message translates to:
  /// **'Location found'**
  String get locationStatusFound;

  /// Status message shown when location determination is active but no location could be determined.
  ///
  /// In en, this message translates to:
  /// **'No location information available'**
  String get locationStatusUnavailable;

  /// Label above the determined place name in the location status popup.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get locationPlaceLabel;

  /// Label above the GPS coordinates in the location status popup.
  ///
  /// In en, this message translates to:
  /// **'GPS Coordinates'**
  String get locationCoordinatesLabel;

  /// Fallback label shown when GPS coordinates are found without a resolved place name.
  ///
  /// In en, this message translates to:
  /// **'Unknown place'**
  String get locationPlaceUnknown;

  /// Label above the location source in the location status popup.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get locationSourceLabel;

  /// Source label for hardware GPS or GNSS satellite location fixes.
  ///
  /// In en, this message translates to:
  /// **'GPS'**
  String get locationSourceGps;

  /// Source label for OS or network location services (Wi-Fi, cell, GeoClue2, or Windows Location API).
  ///
  /// In en, this message translates to:
  /// **'System / Network'**
  String get locationSourceSystem;

  /// Source label for IP-based GeoIP fallback location fixes.
  ///
  /// In en, this message translates to:
  /// **'Internet (GeoIP)'**
  String get locationSourceInternet;

  /// Button label to manually refresh the current location.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// Input label for the label name field in the label editor.
  ///
  /// In en, this message translates to:
  /// **'Label Name'**
  String get labelNameLabel;

  /// Validation error shown when the label name is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a label name.'**
  String get labelNameErrorEmpty;

  /// Validation error shown when another label already uses the same name.
  ///
  /// In en, this message translates to:
  /// **'A label with this name already exists.'**
  String get labelNameErrorDuplicate;

  /// Section card title for the optional hexadecimal color in the label editor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get labelColorSectionTitle;

  /// Placeholder hint inside the hexadecimal color input field.
  ///
  /// In en, this message translates to:
  /// **'#RRGGBB (optional)'**
  String get labelColorHint;

  /// Validation error shown when the hexadecimal color input is malformed.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid hex color (#RRGGBB).'**
  String get labelColorErrorInvalid;

  /// Section card description for activation conditions in the label editor.
  ///
  /// In en, this message translates to:
  /// **'Restrict when and where tasks with this label become active by default.'**
  String get labelConditionsSectionDescription;

  /// Section card title for task links in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get linksSectionTitle;

  /// Placeholder hint for the link title input field.
  ///
  /// In en, this message translates to:
  /// **'Link title (e.g. Documentation)'**
  String get linkTitleHint;

  /// Placeholder hint for the link URI input field.
  ///
  /// In en, this message translates to:
  /// **'URI (e.g. https://example.com)'**
  String get linkUriHint;

  /// Tooltip for the button that adds a link to a task.
  ///
  /// In en, this message translates to:
  /// **'Add link'**
  String get tooltipAddLink;

  /// Tooltip for the button that removes a link from a task.
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get tooltipRemoveLink;

  /// Tooltip for the button that opens a task link URI.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get tooltipOpenLink;

  /// Tooltip for the passive note indicator icon on a task pill.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get tooltipIndicatorNote;

  /// Validation error shown when a link title or URI is empty or invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter both a link title and a valid URI with scheme (e.g. https://...).'**
  String get linkErrorInvalid;

  /// Validation error shown when attempting to add more than 20 links to a task.
  ///
  /// In en, this message translates to:
  /// **'Maximum of 20 links per task reached.'**
  String get linkErrorMaxExceeded;

  /// Error message shown when opening a task link URI fails.
  ///
  /// In en, this message translates to:
  /// **'Could not open link.'**
  String get errorOpenLinkFailed;

  /// Settings section card title for the opt-in diagnostic logging toggle.
  ///
  /// In en, this message translates to:
  /// **'Enable Diagnostic Log'**
  String get diagnosticsSectionTitle;

  /// Settings section card description explaining opt-in diagnostic logging and crash preservation.
  ///
  /// In en, this message translates to:
  /// **'Record runtime events and preserve crash traces locally in tiertask.log for debugging.'**
  String get diagnosticsSectionDescription;

  /// Navigation drawer button label that opens the diagnostic log viewer.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic Log'**
  String get diagnosticLogButton;

  /// Dialog title for the diagnostic log viewer.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic Log'**
  String get diagnosticLogTitle;

  /// Placeholder text shown in the diagnostic log viewer when the log buffer is empty.
  ///
  /// In en, this message translates to:
  /// **'No diagnostic log entries recorded yet.'**
  String get emptyLogHint;

  /// Tooltip for the Copy All button in the diagnostic log viewer.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get tooltipCopyLog;

  /// Tooltip for the Scroll to Bottom button in the diagnostic log viewer.
  ///
  /// In en, this message translates to:
  /// **'Scroll to Bottom'**
  String get tooltipScrollToBottom;

  /// SnackBar confirmation message shown after copying the diagnostic log to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log copied to clipboard.'**
  String get logCopiedSnackBar;

  /// SnackBar confirmation message shown after clearing the diagnostic log.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log cleared.'**
  String get logClearedSnackBar;

  /// Button label in Settings to wipe and re-initialize the local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Wipe Local TDF File'**
  String get actionWipeLocalFile;

  /// Button label in Settings to wipe and re-initialize the remote WebDAV TDF file.
  ///
  /// In en, this message translates to:
  /// **'Wipe Remote TDF File'**
  String get actionWipeRemoteFile;

  /// Dialog title when confirming a wipe of the local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Wipe Local TDF File'**
  String get wipeLocalDialogTitle;

  /// Dialog title when confirming a wipe of the remote WebDAV TDF file.
  ///
  /// In en, this message translates to:
  /// **'Wipe Remote TDF File'**
  String get wipeRemoteDialogTitle;

  /// Description in the local file wipe confirmation dialog instructing the user to enter the file name without .tdf.
  ///
  /// In en, this message translates to:
  /// **'This will empty the local file \"{fileName}\" and re-initialize it as an empty TDF document. Enter \"{baseName}\" (file name without .tdf) to confirm.'**
  String wipeLocalDialogDescription(String fileName, String baseName);

  /// Description in the remote WebDAV file wipe confirmation dialog instructing the user to enter the file name without .tdf.
  ///
  /// In en, this message translates to:
  /// **'This will empty the remote WebDAV file \"{fileName}\" and re-initialize it as an empty TDF document. Enter \"{baseName}\" (file name without .tdf) to confirm.'**
  String wipeRemoteDialogDescription(String fileName, String baseName);

  /// Input label in the wipe confirmation dialog requiring the file name without the .tdf extension.
  ///
  /// In en, this message translates to:
  /// **'File name without .tdf'**
  String get wipeConfirmInputLabel;

  /// Checkbox label in the wipe confirmation dialog to create a .bak or .bak.001+ backup before wiping.
  ///
  /// In en, this message translates to:
  /// **'Create backup (.bak / .bak.001+) if file exists'**
  String get wipeCreateBackupLabel;

  /// Confirmation button label in the wipe TDF file dialog.
  ///
  /// In en, this message translates to:
  /// **'Wipe File'**
  String get actionWipeConfirm;

  /// Status banner message shown after wiping and re-initializing the local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Local TDF file wiped and re-initialized.'**
  String get localFileWipedBanner;

  /// Status banner message shown after wiping and re-initializing the remote WebDAV TDF file.
  ///
  /// In en, this message translates to:
  /// **'Remote TDF file wiped and re-initialized on WebDAV.'**
  String get remoteFileWipedBanner;

  /// Button label to select an existing local TDF file or create a new one.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get actionSelectLocalFile;

  /// Button label to move the local TDF file into another directory.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get actionMoveLocalFile;

  /// Button label to rename the local TDF file in the same directory.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get actionRenameLocalFile;

  /// Dialog title for selecting an existing local TDF file or creating a new one.
  ///
  /// In en, this message translates to:
  /// **'Select or Create Local TDF File'**
  String get selectLocalDialogTitle;

  /// Dialog description for selecting or creating a local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Select an existing TDF file in the storage directory or enter a new file name.'**
  String get selectLocalDialogDescription;

  /// Dialog title for renaming the local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Rename Local TDF File'**
  String get renameLocalDialogTitle;

  /// Dialog description instructing the user to enter a new file name for the local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Enter a new file name for \"{fileName}\" in the current directory.'**
  String renameLocalDialogDescription(String fileName);

  /// Input field label for entering a TDF file name.
  ///
  /// In en, this message translates to:
  /// **'File Name (.tdf)'**
  String get localFileNameInputLabel;

  /// Validation error shown when an entered TDF file name is empty or contains path separators.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid file name without path separators.'**
  String get localFileNameErrorInvalid;

  /// Status banner message shown after selecting or creating a local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Local TDF file selected.'**
  String get localFileSelectedBanner;

  /// Status banner message shown after renaming the local TDF file.
  ///
  /// In en, this message translates to:
  /// **'Local TDF file renamed.'**
  String get localFileRenamedBanner;

  /// Localized string for logLevelLabel
  ///
  /// In en, this message translates to:
  /// **'Minimum Log Level'**
  String get logLevelLabel;

  /// Localized string for logLevelDebug
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get logLevelDebug;

  /// Localized string for logLevelInfo
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logLevelInfo;

  /// Localized string for logLevelWarn
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logLevelWarn;

  /// Localized string for logLevelError
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logLevelError;

  /// Localized string for logStorageLabel
  ///
  /// In en, this message translates to:
  /// **'Log Storage'**
  String get logStorageLabel;

  /// Localized string for logStorageLocal
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get logStorageLocal;

  /// Localized string for logStorageWebDav
  ///
  /// In en, this message translates to:
  /// **'WebDAV'**
  String get logStorageWebDav;

  /// Localized string for logStorageBoth
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get logStorageBoth;

  /// Localized string for logMetadataFile
  ///
  /// In en, this message translates to:
  /// **'File: {fileName}'**
  String logMetadataFile(String fileName);

  /// Localized string for logMetadataStats
  ///
  /// In en, this message translates to:
  /// **'Entries: {entries} | Warnings: {warnings} | Errors: {errors}'**
  String logMetadataStats(String entries, String warnings, String errors);

  /// Localized string for logFilterAllTags
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get logFilterAllTags;

  /// Localized string for logSyncedSnackBar
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log synced to WebDAV.'**
  String get logSyncedSnackBar;

  /// Confirm button label in the custom color wheel dialog.
  ///
  /// In en, this message translates to:
  /// **'Choose custom color'**
  String get tooltipPickCustomColor;

  /// Confirm button label in the custom color wheel dialog.
  ///
  /// In en, this message translates to:
  /// **'Choose Custom Color'**
  String get labelColorPickerDialogTitle;

  /// Confirm button label in the custom color wheel dialog.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get labelColorBrightnessLabel;

  /// Confirm button label in the custom color wheel dialog.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get actionSelectColor;

  /// Tooltip for the Auto-finish toggle chip in the subtasks section of the task editor.
  ///
  /// In en, this message translates to:
  /// **'Automatically completes the entire task as soon as all subtasks are checked off.'**
  String get tooltipTaskEditorAutoFinish;

  /// Section title for locations in the navigation drawer.
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get drawerLocations;

  /// Empty-state hint shown when no locations exist.
  ///
  /// In en, this message translates to:
  /// **'No locations created yet.'**
  String get emptyLocationsHint;

  /// Tooltip for the button that deletes a location.
  ///
  /// In en, this message translates to:
  /// **'Delete location'**
  String get tooltipDeleteLocation;

  /// Input label for the location name field in the location editor.
  ///
  /// In en, this message translates to:
  /// **'Location Name'**
  String get locationNameLabel;

  /// Section card title for GPS coordinates and radius in the location editor.
  ///
  /// In en, this message translates to:
  /// **'Coordinates & Radius'**
  String get locationCoordinatesSectionTitle;

  /// Input label for latitude in the location editor.
  ///
  /// In en, this message translates to:
  /// **'Latitude (-90 to 90)'**
  String get locationLatitudeLabel;

  /// Input label for longitude in the location editor.
  ///
  /// In en, this message translates to:
  /// **'Longitude (-180 to 180)'**
  String get locationLongitudeLabel;

  /// Input label for radius in the location editor.
  ///
  /// In en, this message translates to:
  /// **'Radius (m/km)'**
  String get locationRadiusLabel;

  /// Button label to populate location coordinates from the current foreground GPS fix.
  ///
  /// In en, this message translates to:
  /// **'Use Current GPS Position'**
  String get locationUseCurrentGpsButton;

  /// Validation error shown when the location name is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a location name.'**
  String get locationNameErrorEmpty;

  /// Validation error shown when the location source is invalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid source or leave it empty.'**
  String get locationSourceErrorEmpty;

  /// Validation error shown when location latitude or longitude is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter valid latitude (-90..90) and longitude (-180..180).'**
  String get locationCoordinatesErrorInvalid;

  /// Validation error shown when location radius is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid radius between 0.01m and 100km.'**
  String get locationRadiusErrorInvalid;

  /// Section card title for the scoped label switch in the label editor.
  ///
  /// In en, this message translates to:
  /// **'Board Scope'**
  String get labelScopedSectionTitle;

  /// Switch subtitle explaining scoped label behavior in the label editor.
  ///
  /// In en, this message translates to:
  /// **'Hide tasks with this label unless this label filter is active.'**
  String get labelScopedSwitchSubtitle;

  /// Input field label for an optional due timestamp in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Due (optional)'**
  String get taskDueButtonLabel;

  /// Badge text on a task pill showing the due date.
  ///
  /// In en, this message translates to:
  /// **'Due: {date}'**
  String pillDuePrefix(String date);

  /// Label for the location source type dropdown.
  ///
  /// In en, this message translates to:
  /// **'Source Type'**
  String get locationSourceTypeLabel;

  /// Dropdown option for manual or hardware GPS coordinate input.
  ///
  /// In en, this message translates to:
  /// **'GPS Coordinates'**
  String get locationSourceTypeGps;

  /// Dropdown option for street address forward geocoding.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get locationSourceTypeAddress;

  /// Dropdown option for Open Location Code (Google Plus Code) resolution.
  ///
  /// In en, this message translates to:
  /// **'Google Plus Code'**
  String get locationSourceTypePlusCode;

  /// Hint text for the location source input when Address is selected.
  ///
  /// In en, this message translates to:
  /// **'Street, postal code, city'**
  String get locationSourceAddressHint;

  /// Hint text for the location source input when Google Plus Code is selected.
  ///
  /// In en, this message translates to:
  /// **'e.g. 9F2PXXH7+F4 or XXH7+F4 Erfurt'**
  String get locationSourcePlusCodeHint;

  /// Button label to resolve an entered address or Plus Code into coordinates.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get locationResolveButton;

  /// Title of the candidate selection dialog when forward geocoding returns multiple matches.
  ///
  /// In en, this message translates to:
  /// **'Select Location'**
  String get locationSelectCandidateTitle;

  /// Validation error when address or Plus Code locality lookup returns no matches.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve address or Plus Code.'**
  String get locationResolveErrorNotFound;

  /// Validation error when the entered Plus Code syntax is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Plus Code (e.g. 9F2PXXH7+F4 or XXH7+F4 Erfurt).'**
  String get locationResolveErrorInvalidPlusCode;

  /// Tooltip for the activation conditions indicator icon.
  ///
  /// In en, this message translates to:
  /// **'Activation conditions'**
  String get tooltipIndicatorConditions;

  /// Value text shown when a task is suspended indefinitely.
  ///
  /// In en, this message translates to:
  /// **'Indefinitely'**
  String get taskInfoSuspendedForever;

  /// Value text shown when a task is suspended until a future timestamp with remaining duration.
  ///
  /// In en, this message translates to:
  /// **'Until {timestamp} ({duration})'**
  String taskInfoSuspendedUntil(String timestamp, String duration);

  /// Section label for the due deadline in the task information dialog.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get taskInfoDueLabel;

  /// Value text shown when a task has a future due timestamp with remaining duration.
  ///
  /// In en, this message translates to:
  /// **'{timestamp} ({duration})'**
  String taskInfoDueAt(String timestamp, String duration);

  /// Value text shown when a task's due timestamp has passed.
  ///
  /// In en, this message translates to:
  /// **'Overdue ({timestamp})'**
  String taskInfoDueOverdue(String timestamp);

  /// Remaining duration formatted in days and hours.
  ///
  /// In en, this message translates to:
  /// **'{days} d {hours} h remaining'**
  String taskInfoDurationDaysHours(String days, String hours);

  /// Remaining duration formatted in hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min remaining'**
  String taskInfoDurationHoursMinutes(String hours, String minutes);

  /// Remaining duration formatted in minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min remaining'**
  String taskInfoDurationMinutes(String minutes);

  /// Subtask completion progress shown in the task information dialog.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} completed'**
  String taskInfoSubtasksProgress(String completed, String total);

  /// Detail line indicating that subtasks auto-finish is enabled.
  ///
  /// In en, this message translates to:
  /// **'Auto-finish enabled'**
  String get taskInfoSubtasksAutoFinishSuffix;

  /// Prerequisite task completion progress shown in the task information dialog.
  ///
  /// In en, this message translates to:
  /// **'{satisfied} of {total} satisfied'**
  String taskInfoBlockedByProgress(String satisfied, String total);

  /// Recurrence interval summary shown in the task information dialog.
  ///
  /// In en, this message translates to:
  /// **'Every {count} {unit}'**
  String taskInfoRepeatEvery(String count, String unit);

  /// Cumulative completion count shown in the task information dialog.
  ///
  /// In en, this message translates to:
  /// **'Completed {count} times'**
  String taskInfoRepeatCompletions(String count);

  /// Count of links shown in the task information dialog.
  ///
  /// In en, this message translates to:
  /// **'{count} links'**
  String taskInfoLinksCount(String count);

  /// Tooltip for the button that copies the expanded task note to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy note'**
  String get tooltipCopyNote;

  /// SnackBar confirmation message shown after copying a task note to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Note copied to clipboard.'**
  String get noteCopiedSnackBar;

  /// Confirmation prompt shown before deleting a task.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// Confirmation prompt shown before deleting a task.
  ///
  /// In en, this message translates to:
  /// **'Completed \"{title}\".'**
  String taskCompletedUndoSnackBar(String title);

  /// Confirmation prompt shown before deleting a task.
  ///
  /// In en, this message translates to:
  /// **'Downgraded \"{title}\".'**
  String taskDowngradedUndoSnackBar(String title);

  /// Confirmation prompt shown before deleting a task.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\".'**
  String taskDeletedUndoSnackBar(String title);

  /// Label for the local external file watcher toggle in settings.
  ///
  /// In en, this message translates to:
  /// **'Watch for external file changes'**
  String get localWatchLabel;

  /// Description for the local external file watcher toggle in settings.
  ///
  /// In en, this message translates to:
  /// **'Automatically merge edits saved by external editors, scripts, or file-sync tools.'**
  String get localWatchDescription;

  /// Subtle label displaying the task identifier at the top of an expanded task card.
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String taskIdRowLabel(String id);

  /// Tooltip for the button that copies the task ID to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy task ID'**
  String get tooltipCopyTaskId;

  /// SnackBar confirmation message shown after copying a task ID to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Task ID copied to clipboard.'**
  String get taskIdCopiedSnackBar;

  /// Validation error when adding more than 20 links to a label.
  ///
  /// In en, this message translates to:
  /// **'Maximum of 20 links per label reached.'**
  String get labelLinkErrorMaxExceeded;

  /// Tooltip for canceling an active inline link edit.
  ///
  /// In en, this message translates to:
  /// **'Cancel link edit'**
  String get tooltipCancelEditLink;

  /// Tooltip for starting an inline edit of an existing link row.
  ///
  /// In en, this message translates to:
  /// **'Edit link'**
  String get tooltipEditLink;

  /// Tooltip for moving a link row down by one position.
  ///
  /// In en, this message translates to:
  /// **'Move link down'**
  String get tooltipMoveLinkDown;

  /// Tooltip for moving a link row up by one position.
  ///
  /// In en, this message translates to:
  /// **'Move link up'**
  String get tooltipMoveLinkUp;

  /// Tooltip for confirming an inline link edit.
  ///
  /// In en, this message translates to:
  /// **'Update link'**
  String get tooltipSaveLink;

  /// Section title for the per-workspace deadline auto-priority lead window setting.
  ///
  /// In en, this message translates to:
  /// **'Deadline Auto-Priority'**
  String get dueLeadWindowSectionTitle;

  /// Section description for the deadline auto-priority lead window setting.
  ///
  /// In en, this message translates to:
  /// **'Automatically prioritize scheduled open tasks into Focus and Ready when their due date approaches.'**
  String get dueLeadWindowSectionDescription;

  /// Dropdown label for selecting the deadline auto-priority lead window.
  ///
  /// In en, this message translates to:
  /// **'Lead Window'**
  String get dueLeadWindowLabel;

  /// Option disabling automatic priority promotion near deadlines.
  ///
  /// In en, this message translates to:
  /// **'Off (never auto-prioritize)'**
  String get dueLeadWindowOff;

  /// Option enabling automatic priority promotion at exact deadline arrival.
  ///
  /// In en, this message translates to:
  /// **'At deadline (0 hours)'**
  String get dueLeadWindowAtDue;

  /// Option enabling automatic priority promotion 12 hours before deadline.
  ///
  /// In en, this message translates to:
  /// **'12 hours before deadline'**
  String get dueLeadWindow12Hours;

  /// Default option enabling automatic priority promotion 24 hours before deadline.
  ///
  /// In en, this message translates to:
  /// **'24 hours before deadline (Default)'**
  String get dueLeadWindow24Hours;

  /// Option enabling automatic priority promotion 48 hours before deadline.
  ///
  /// In en, this message translates to:
  /// **'48 hours before deadline'**
  String get dueLeadWindow48Hours;

  /// Option enabling automatic priority promotion 7 days before deadline.
  ///
  /// In en, this message translates to:
  /// **'7 days before deadline'**
  String get dueLeadWindow7Days;

  /// Short 12-hour lead window label used in task info status text.
  ///
  /// In en, this message translates to:
  /// **'12 h'**
  String get dueLeadWindowShort12Hours;

  /// Short 24-hour lead window label used in task info status text.
  ///
  /// In en, this message translates to:
  /// **'24 h'**
  String get dueLeadWindowShort24Hours;

  /// Short 48-hour lead window label used in task info status text.
  ///
  /// In en, this message translates to:
  /// **'48 h'**
  String get dueLeadWindowShort48Hours;

  /// Short 7-day lead window label used in task info status text.
  ///
  /// In en, this message translates to:
  /// **'7 d'**
  String get dueLeadWindowShort7Days;

  /// Switch title in task editor controlling whether a due date auto-prioritizes the task.
  ///
  /// In en, this message translates to:
  /// **'Auto-prioritize near deadline'**
  String get taskDueAutoPrioritizeLabel;

  /// Switch subtitle in task editor explaining deadline lead-window auto-priority.
  ///
  /// In en, this message translates to:
  /// **'Pull ahead of regular queued tasks once the lead window opens.'**
  String get taskDueAutoPrioritizeSubtitle;

  /// Status line in task info dialog when an open task is inside the deadline lead window.
  ///
  /// In en, this message translates to:
  /// **'Prioritized by deadline lead window'**
  String get taskInfoDueAutoPromotedActive;

  /// Status line in task info dialog when workspace lead window is set to 0 hours.
  ///
  /// In en, this message translates to:
  /// **'Auto-prioritizes at deadline'**
  String get taskInfoDueAutoPromoteAtDue;

  /// Status line in task info dialog showing when deadline auto-priority will activate.
  ///
  /// In en, this message translates to:
  /// **'Auto-prioritizes {window} before deadline'**
  String taskInfoDueAutoPromoteScheduled(String window);

  /// Status line in task info dialog when a task deadline is marked passive.
  ///
  /// In en, this message translates to:
  /// **'Informational deadline (auto-priority off)'**
  String get taskInfoDuePassiveHint;

  /// Status line in task info dialog when workspace deadline auto-priority is turned off.
  ///
  /// In en, this message translates to:
  /// **'Deadline auto-priority disabled in settings'**
  String get taskInfoDueLeadWindowOffHint;

  /// Input label for the optional deferral note field shown when Suspended is enabled.
  ///
  /// In en, this message translates to:
  /// **'Deferral note (optional)'**
  String get taskSuspendedNoteLabel;

  /// Placeholder hint for the optional deferral note input field.
  ///
  /// In en, this message translates to:
  /// **'Why is this task deferred?'**
  String get taskSuspendedNoteHint;

  /// Input label for the optional deadline note field shown when Due is enabled.
  ///
  /// In en, this message translates to:
  /// **'Deadline note (optional)'**
  String get taskDueNoteLabel;

  /// Placeholder hint for the optional deadline note input field.
  ///
  /// In en, this message translates to:
  /// **'Cutoff details or submission requirements'**
  String get taskDueNoteHint;

  /// Validation error shown when a deferral or deadline note exceeds 2,000 Unicode scalar values.
  ///
  /// In en, this message translates to:
  /// **'Note must not exceed 2,000 characters.'**
  String get schedulingNoteErrorTooLong;

  /// Validation error shown when a deferral or deadline note contains disallowed control characters or unpaired surrogates.
  ///
  /// In en, this message translates to:
  /// **'Note contains unsupported control characters.'**
  String get schedulingNoteErrorInvalid;

  /// Input label for the recurring preparation lead window in days when both Repeat and Due are enabled.
  ///
  /// In en, this message translates to:
  /// **'Preparation lead (days, optional)'**
  String get repeatLeadDaysLabel;

  /// Placeholder hint for the optional recurring preparation lead days input field.
  ///
  /// In en, this message translates to:
  /// **'0 (activate immediately after rollover)'**
  String get repeatLeadDaysHint;

  /// Validation error shown when the recurring preparation lead input is not an integer in 0..3650.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number between 0 and 3650 days.'**
  String get repeatLeadDaysErrorInvalid;

  /// Detail line in TaskInfoDialog describing the Mode 2 recurring preparation lead offset.
  ///
  /// In en, this message translates to:
  /// **'Preparation window opens {days} day(s) before due date'**
  String taskInfoRepeatLeadDays(String days);

  /// Section title for the task history journal card in TaskInfoDialog and EditTaskScreen.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historySectionTitle;

  /// Empty-state hint shown inside the history section of TaskInfoDialog when no history entries exist.
  ///
  /// In en, this message translates to:
  /// **'No history entries recorded yet.'**
  String get historyEmptyHint;

  /// Input label for the single-line history entry text field.
  ///
  /// In en, this message translates to:
  /// **'History entry'**
  String get historyEntryTextLabel;

  /// Placeholder hint for the single-line history entry text field.
  ///
  /// In en, this message translates to:
  /// **'Add progress update or note'**
  String get historyEntryTextHint;

  /// Input label for the optional local wall-clock history timestamp field in EditTaskScreen.
  ///
  /// In en, this message translates to:
  /// **'Timestamp (optional, defaults to now)'**
  String get historyTimestampLabel;

  /// Placeholder hint for the optional local wall-clock history timestamp field.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD HH:MM'**
  String get historyTimestampHint;

  /// Tooltip for the button that appends a history entry.
  ///
  /// In en, this message translates to:
  /// **'Add history entry'**
  String get tooltipAddHistoryEntry;

  /// Tooltip for starting an edit of an existing history entry row.
  ///
  /// In en, this message translates to:
  /// **'Edit history entry'**
  String get tooltipEditHistoryEntry;

  /// Tooltip for confirming an edit to an existing history entry.
  ///
  /// In en, this message translates to:
  /// **'Update history entry'**
  String get tooltipSaveHistoryEntry;

  /// Tooltip for canceling an active edit of a history entry.
  ///
  /// In en, this message translates to:
  /// **'Cancel history edit'**
  String get tooltipCancelEditHistoryEntry;

  /// Tooltip for deleting a history entry row.
  ///
  /// In en, this message translates to:
  /// **'Delete history entry'**
  String get tooltipDeleteHistoryEntry;

  /// Validation error shown when a history entry text is empty or spaces-only.
  ///
  /// In en, this message translates to:
  /// **'Enter a history text.'**
  String get historyErrorTextEmpty;

  /// Validation error shown when a history entry exceeds 500 Unicode scalar values.
  ///
  /// In en, this message translates to:
  /// **'History entry must not exceed 500 characters.'**
  String get historyErrorTextTooLong;

  /// Validation error shown when a history entry contains disallowed control characters or unpaired UTF-16 surrogates.
  ///
  /// In en, this message translates to:
  /// **'History entry contains unsupported control characters.'**
  String get historyErrorTextInvalid;

  /// Validation error shown when a history timestamp is malformed or outside 0001..9999 UTC.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date (YYYY-MM-DD) and optional time (HH:MM).'**
  String get historyErrorTimestampInvalid;

  /// Validation error shown when adding a distinct entry would exceed 500 history entries on a task.
  ///
  /// In en, this message translates to:
  /// **'Maximum of 500 history entries per task reached.'**
  String get historyErrorMaxExceeded;

  /// Status banner message shown when synchronization pauses due to an edit-versus-deletion conflict.
  ///
  /// In en, this message translates to:
  /// **'Synchronization paused: a concurrent edit conflicts with a deletion.'**
  String get syncConflictDeletionBanner;

  /// Status banner message shown when synchronization pauses because local items require recovery after a generation advance.
  ///
  /// In en, this message translates to:
  /// **'Synchronization paused: local changes require recovery after sync history advancement.'**
  String get syncConflictRecoveryBanner;

  /// Status banner message shown when synchronization stops due to a deleted.generation rollback.
  ///
  /// In en, this message translates to:
  /// **'Synchronization stopped: the shared file sync generation is older than the acknowledged state.'**
  String get syncErrorGenerationRollbackBanner;

  /// Read-only detail line in the task info dialog showing the intended local schedule anchor when clamped or shifted across a DST transition.
  ///
  /// In en, this message translates to:
  /// **'Schedule anchor: {anchor}'**
  String taskInfoDueAnchorDetail(String anchor);

  /// Heading shown when one or more TDF storage files cannot be read.
  ///
  /// In en, this message translates to:
  /// **'File Read Error'**
  String get fileReadErrorTitle;

  /// Label identifying the local TDF storage file in read status diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Local file'**
  String get fileReadTargetLocal;

  /// Label identifying the remote WebDAV TDF storage file in read status diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Remote file'**
  String get fileReadTargetRemote;

  /// Compact status label indicating that a TDF storage file is intact and readable.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get fileReadStatusOk;

  /// Compact status label indicating that a TDF storage file could not be read.
  ///
  /// In en, this message translates to:
  /// **'Cannot be read'**
  String get fileReadStatusUnreadable;

  /// Summary shown in local-only mode when the local TDF file cannot be read.
  ///
  /// In en, this message translates to:
  /// **'The local file could not be read.'**
  String get fileReadSummaryLocalOnly;

  /// Summary shown in WebDAV-only mode when the remote TDF file cannot be read.
  ///
  /// In en, this message translates to:
  /// **'The remote file could not be read.'**
  String get fileReadSummaryRemoteOnly;

  /// Summary shown in dual-storage mode when only the local TDF file failed and the remote file is intact.
  ///
  /// In en, this message translates to:
  /// **'Only the local file could not be read. The remote file is intact.'**
  String get fileReadSummaryLocalFailedRemoteOk;

  /// Summary shown in dual-storage mode when only the remote TDF file failed and the local file is intact.
  ///
  /// In en, this message translates to:
  /// **'Only the remote file could not be read. The local file is intact.'**
  String get fileReadSummaryRemoteFailedLocalOk;

  /// Summary shown in dual-storage mode when both the local and remote TDF files failed.
  ///
  /// In en, this message translates to:
  /// **'Both the local and remote files could not be read.'**
  String get fileReadSummaryBothFailed;

  /// Per-file error reason when a TDF file specifies an unsupported version header.
  ///
  /// In en, this message translates to:
  /// **'Unsupported TDF version {version} (expected 0.8.0).'**
  String fileReadReasonUnsupportedVersion(String version);

  /// Per-file error reason when a TDF file fails lexical, structural, or semantic validation.
  ///
  /// In en, this message translates to:
  /// **'Format error (line {line}): {details}'**
  String fileReadReasonTdfFormat(String line, String details);

  /// Single-line target and status entry in a file read diagnostic summary.
  ///
  /// In en, this message translates to:
  /// **'{target}: {status}'**
  String fileReadStatusEntryLine(String target, String status);

  /// Error message shown when persisted application settings cannot be decoded.
  ///
  /// In en, this message translates to:
  /// **'Application settings could not be read.'**
  String get errorSettingsCorrupt;

  /// Error message shown when settings.json declares a schemaVersion newer than supported.
  ///
  /// In en, this message translates to:
  /// **'Settings were created by a newer TierTask version. Update TierTask to avoid data loss.'**
  String get errorSettingsUnsupportedVersion;

  /// Error message shown when OS secure storage fails while saving a WebDAV password.
  ///
  /// In en, this message translates to:
  /// **'Secure credential storage is unavailable. WebDAV password could not be saved.'**
  String get errorSettingsCredentialStorageUnavailable;

  /// Error message shown when host-local settings file persistence or locking fails.
  ///
  /// In en, this message translates to:
  /// **'Could not save application settings.'**
  String get errorSettingsSaveFailed;

  /// One-shot startup notice shown when settings.json was restored from settings.json.bak.
  ///
  /// In en, this message translates to:
  /// **'Settings were restored from backup after a file error.'**
  String get settingsRecoveredFromBackupNotice;

  /// One-shot startup notice shown when corrupt settings were quarantined and reset to defaults.
  ///
  /// In en, this message translates to:
  /// **'Corrupt settings were backed up and reset to defaults.'**
  String get settingsResetAfterQuarantineNotice;

  /// Name of the default Calm theme preset.
  ///
  /// In en, this message translates to:
  /// **'Calm'**
  String get themePaletteCalm;

  /// Name of the Plum Umber theme preset.
  ///
  /// In en, this message translates to:
  /// **'Plum Umber'**
  String get themePalettePlumUmber;

  /// Inline badge marking a development build in the top chrome bar.
  ///
  /// In en, this message translates to:
  /// **'DEV'**
  String get devBuildBadge;

  /// Subtitle for the Focus tier.
  ///
  /// In en, this message translates to:
  /// **'Three active tasks. One clear next step.'**
  String get tierFocusSubtitle;

  /// Subtitle for the Ready tier.
  ///
  /// In en, this message translates to:
  /// **'Up to five tasks queued to pull into Focus next.'**
  String get tierReadySubtitle;

  /// Subtitle for the Planned tier.
  ///
  /// In en, this message translates to:
  /// **'Active backlog feeding Ready automatically.'**
  String get tierPlannedSubtitle;

  /// Subtitle for the Blocked tier.
  ///
  /// In en, this message translates to:
  /// **'Suspended or waiting on prerequisites and activation conditions.'**
  String get tierBlockedSubtitle;

  /// Subtitle for the Someday tier.
  ///
  /// In en, this message translates to:
  /// **'Collected outside the active queue.'**
  String get tierSomedaySubtitle;

  /// Subtitle for the Completed tier.
  ///
  /// In en, this message translates to:
  /// **'Completed tasks are retained for 30 days (UTC).'**
  String get tierCompletedSubtitle;

  /// Sidebar section heading for the six task tiers.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get sectionTasksTitle;

  /// Sidebar section heading for utility views and Settings.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get sectionToolsTitle;

  /// Sidebar row clearing any active label filter.
  ///
  /// In en, this message translates to:
  /// **'All Tasks'**
  String get allTasksLabel;

  /// Tooltip for clearing the active label filter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter (All Tasks)'**
  String get activeFilterClearTooltip;

  /// Back button label returning to the Tasks view.
  ///
  /// In en, this message translates to:
  /// **'Back to tasks'**
  String get actionBackToTasks;

  /// Back button label returning to the Global Search view.
  ///
  /// In en, this message translates to:
  /// **'Back to search'**
  String get actionBackToSearch;

  /// Action label dismissing a banner or floating notice.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get actionDismiss;

  /// Banner action opening the Deletion Conflict view.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflict'**
  String get actionResolveConflict;

  /// Banner action opening the Generation Recovery view.
  ///
  /// In en, this message translates to:
  /// **'Open recovery'**
  String get actionResolveRecovery;

  /// Accessible action label completing an open task.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get actionComplete;

  /// Accessible action label restoring a completed task.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get actionRestore;

  /// Generic copy button label.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// Heading for the Global Search view.
  ///
  /// In en, this message translates to:
  /// **'All Tasks'**
  String get searchViewTitle;

  /// Subtitle for the Global Search view.
  ///
  /// In en, this message translates to:
  /// **'Searching across all six tiers in the active context.'**
  String get searchViewSubtitle;

  /// Empty state text when Global Search finds no matching tasks.
  ///
  /// In en, this message translates to:
  /// **'No matching tasks found.'**
  String get searchEmptyHint;

  /// Tooltip closing the Global Search bar.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get searchCloseTooltip;

  /// Heading shown during initial workspace loading.
  ///
  /// In en, this message translates to:
  /// **'Loading workspace...'**
  String get loadingBoardTitle;

  /// Subtitle shown during initial workspace loading.
  ///
  /// In en, this message translates to:
  /// **'Reading TDF document and evaluating six tiers.'**
  String get loadingBoardSubtitle;

  /// Placeholder for the sidebar label filter input.
  ///
  /// In en, this message translates to:
  /// **'Filter labels...'**
  String get sidebarFilterLabelsPlaceholder;

  /// Empty state when sidebar label filter finds no matches.
  ///
  /// In en, this message translates to:
  /// **'No matching labels.'**
  String get sidebarFilterLabelsEmpty;

  /// Tooltip toggling the sidebar label filter input.
  ///
  /// In en, this message translates to:
  /// **'Filter labels'**
  String get sidebarFilterLabelsToggle;

  /// Tooltip opening the Labels manager view.
  ///
  /// In en, this message translates to:
  /// **'Manage labels'**
  String get sidebarManageLabels;

  /// Tooltip collapsing the sidebar Labels section.
  ///
  /// In en, this message translates to:
  /// **'Collapse labels'**
  String get sidebarCollapseLabels;

  /// Tooltip expanding the sidebar Labels section.
  ///
  /// In en, this message translates to:
  /// **'Expand labels'**
  String get sidebarExpandLabels;

  /// Placeholder for the sidebar location filter input.
  ///
  /// In en, this message translates to:
  /// **'Filter locations...'**
  String get sidebarFilterLocationsPlaceholder;

  /// Empty state when sidebar location filter finds no matches.
  ///
  /// In en, this message translates to:
  /// **'No matching locations.'**
  String get sidebarFilterLocationsEmpty;

  /// Tooltip toggling the sidebar location filter input.
  ///
  /// In en, this message translates to:
  /// **'Filter locations'**
  String get sidebarFilterLocationsToggle;

  /// Tooltip opening the Locations manager view.
  ///
  /// In en, this message translates to:
  /// **'Manage locations'**
  String get sidebarManageLocations;

  /// Tooltip collapsing the sidebar Locations section.
  ///
  /// In en, this message translates to:
  /// **'Collapse locations'**
  String get sidebarCollapseLocations;

  /// Tooltip expanding the sidebar Locations section.
  ///
  /// In en, this message translates to:
  /// **'Expand locations'**
  String get sidebarExpandLocations;

  /// Tooltip navigating to a label card in Labels manager.
  ///
  /// In en, this message translates to:
  /// **'Open and expand label in Manage'**
  String get openLabelInManagerTooltip;

  /// Tooltip navigating to a location card in Locations manager.
  ///
  /// In en, this message translates to:
  /// **'Open and expand location in Manage'**
  String get openLocationInManagerTooltip;

  /// Chrome sync status label in Local storage mode.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get syncStatusLocalOnly;

  /// Chrome sync status label when synchronized.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get syncStatusSynced;

  /// Chrome sync status label while syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncStatusSyncing;

  /// Chrome sync status label on conflict or recovery required.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get syncStatusConflict;

  /// Chrome sync status label on sync failure.
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncStatusError;

  /// Title for the Raw TDF 0.8.0 preview view.
  ///
  /// In en, this message translates to:
  /// **'Raw TDF 0.8.0'**
  String get rawTdfPreviewTitle;

  /// Subtitle for the Raw TDF 0.8.0 preview view.
  ///
  /// In en, this message translates to:
  /// **'Canonical LF-terminated TDF 0.8.0 serialization of the current workspace board.'**
  String get rawTdfPreviewSubtitle;

  /// Telemetry summary showing byte and line counts of the serialized TDF document.
  ///
  /// In en, this message translates to:
  /// **'{bytes} bytes / 1 MiB · {lines} lines / 16,384 max'**
  String rawTdfStatsSummary(String bytes, String lines);

  /// Toast notice after copying raw TDF text.
  ///
  /// In en, this message translates to:
  /// **'TDF document copied to clipboard.'**
  String get rawTdfCopiedNotice;

  /// Alert title when serialized TDF exceeds Section 6.2 preview bounds.
  ///
  /// In en, this message translates to:
  /// **'Preview Limit Exceeded'**
  String get rawTdfLimitExceededTitle;

  /// Alert body when serialized TDF exceeds Section 6.2 preview bounds.
  ///
  /// In en, this message translates to:
  /// **'The serialized TDF document exceeds the canonical 1 MiB or 16,384-line limit (TDF 0.8.0 Section 6.2) and cannot be previewed inline.'**
  String get rawTdfLimitExceededDescription;

  /// Overflow badge showing hidden secondary indicators on a collapsed task card.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String badgeMoreIndicators(String count);

  /// Badge indicating automatic deadline lead-window priority escalation.
  ///
  /// In en, this message translates to:
  /// **'Due · Prioritized'**
  String get badgeAutoPriority;

  /// Collapsed task badge prefix for an overdue deadline.
  ///
  /// In en, this message translates to:
  /// **'Overdue: {date}'**
  String badgeOverduePrefix(String date);

  /// Collapsed task badge for a timed suspension.
  ///
  /// In en, this message translates to:
  /// **'Suspended until {date}'**
  String badgeSuspendedUntil(String date);

  /// Collapsed task badge for an indefinite suspension.
  ///
  /// In en, this message translates to:
  /// **'Suspended indefinitely'**
  String get badgeSuspendedForever;

  /// Collapsed task badge for unsatisfied prerequisites.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} prerequisites'**
  String badgeBlockedByProgress(String done, String total);

  /// Collapsed task badge for subtask progress.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} steps'**
  String badgeStepsProgress(String done, String total);

  /// Collapsed task badge for a single reference link.
  ///
  /// In en, this message translates to:
  /// **'1 link'**
  String get badgeLinkSingular;

  /// Collapsed task badge for history entry count.
  ///
  /// In en, this message translates to:
  /// **'{count} history'**
  String badgeHistoryCount(String count);

  /// Formatted repeat phrase for 1 day interval.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get repeatEveryDay;

  /// Formatted repeat phrase for 1 week interval.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get repeatEveryWeek;

  /// Formatted repeat phrase for 1 month interval.
  ///
  /// In en, this message translates to:
  /// **'Every month'**
  String get repeatEveryMonth;

  /// Status pill shown in expanded completed task cards.
  ///
  /// In en, this message translates to:
  /// **'Completed · restore task to edit'**
  String get completedReadOnlyPill;

  /// Tooltip for inline task title edit button.
  ///
  /// In en, this message translates to:
  /// **'Edit title'**
  String get inlineEditTitleTooltip;

  /// Tooltip for inline label or location name edit button.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get inlineEditNameTooltip;

  /// Add chip opening inline Note editor.
  ///
  /// In en, this message translates to:
  /// **'+ Note'**
  String get inlineAddNote;

  /// Add chip opening inline Links editor.
  ///
  /// In en, this message translates to:
  /// **'+ Links'**
  String get inlineAddLinks;

  /// Add chip opening inline Subtasks editor.
  ///
  /// In en, this message translates to:
  /// **'+ Subtasks'**
  String get inlineAddSubtasks;

  /// Add chip opening inline Label picker.
  ///
  /// In en, this message translates to:
  /// **'+ Labels'**
  String get inlineAddLabels;

  /// Add chip opening inline Due editor.
  ///
  /// In en, this message translates to:
  /// **'+ Due'**
  String get inlineAddDue;

  /// Add chip opening inline Repeat editor.
  ///
  /// In en, this message translates to:
  /// **'+ Repeat'**
  String get inlineAddRepeat;

  /// Add chip opening inline Suspend editor.
  ///
  /// In en, this message translates to:
  /// **'+ Suspend'**
  String get inlineAddSuspend;

  /// Add chip opening inline Prerequisites editor.
  ///
  /// In en, this message translates to:
  /// **'+ Prerequisites'**
  String get inlineAddPrerequisites;

  /// Add chip opening inline Activation Conditions editor.
  ///
  /// In en, this message translates to:
  /// **'+ Conditions'**
  String get inlineAddConditions;

  /// Danger action clearing an optional section inside an inline editor.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get inlineClearAction;

  /// Danger action disabling recurrence inside an inline editor.
  ///
  /// In en, this message translates to:
  /// **'Disable repeat'**
  String get inlineDisableRepeatAction;

  /// Danger action clearing suspension inside an inline editor.
  ///
  /// In en, this message translates to:
  /// **'Resume task'**
  String get inlineResumeTaskAction;

  /// Helper hint when configuring repeat lead days without a due date.
  ///
  /// In en, this message translates to:
  /// **'Set a due date to configure preparation lead days.'**
  String get inlineRepeatLeadNeedsDueHint;

  /// Section title for live task placement selector.
  ///
  /// In en, this message translates to:
  /// **'Queue & Priority'**
  String get inlinePlacementSectionTitle;

  /// Standard active queue placement option.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get placementQueueOption;

  /// Helper hint for standard queue placement.
  ///
  /// In en, this message translates to:
  /// **'Append at the end of the active queue.'**
  String get placementQueueHint;

  /// Helper hint for priority placement.
  ///
  /// In en, this message translates to:
  /// **'Prioritize ahead of regular tasks in Focus or Ready.'**
  String get placementPriorityHint;

  /// Helper hint for Someday placement.
  ///
  /// In en, this message translates to:
  /// **'Park outside the active queue in Someday.'**
  String get placementSomedayHint;

  /// Inline confirmation prompt for deleting a task.
  ///
  /// In en, this message translates to:
  /// **'Delete this task?'**
  String get inlineDeleteTaskConfirm;

  /// Inline confirmation prompt for deleting a label.
  ///
  /// In en, this message translates to:
  /// **'Delete this label?'**
  String get inlineDeleteLabelConfirm;

  /// Inline confirmation prompt for deleting a location.
  ///
  /// In en, this message translates to:
  /// **'Delete this location?'**
  String get inlineDeleteLocationConfirm;

  /// Button cancelling an inline delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get actionKeep;

  /// Button confirming an inline delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'Yes, delete'**
  String get actionConfirmDelete;

  /// Button closing a compact bottom sheet or inline picker.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// Button opening an uncommitted entity draft card.
  ///
  /// In en, this message translates to:
  /// **'Open as draft'**
  String get actionOpenAsDraft;

  /// Compact mobile trigger button expanding Quick-Add.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get actionNewTaskCompact;

  /// Primary commit button for an uncommitted Task Draft Card.
  ///
  /// In en, this message translates to:
  /// **'Create task'**
  String get actionCreateTask;

  /// Primary commit button for an uncommitted Label Draft Card.
  ///
  /// In en, this message translates to:
  /// **'Create label'**
  String get actionCreateLabel;

  /// Primary commit button for an uncommitted Location Draft Card.
  ///
  /// In en, this message translates to:
  /// **'Create location'**
  String get actionCreateLocation;

  /// Header title of an uncommitted Task Draft Card.
  ///
  /// In en, this message translates to:
  /// **'New Task (Draft)'**
  String get draftNewTaskTitle;

  /// Header title of an uncommitted Label Draft Card.
  ///
  /// In en, this message translates to:
  /// **'New Label (Draft)'**
  String get draftNewLabelTitle;

  /// Header title of an uncommitted Location Draft Card.
  ///
  /// In en, this message translates to:
  /// **'New Location (Draft)'**
  String get draftNewLocationTitle;

  /// Subtle status hint on an uncommitted Draft Card.
  ///
  /// In en, this message translates to:
  /// **'Uncommitted · saved to the TDF file only when you click Create.'**
  String get draftUncommittedHint;

  /// Input placeholder in the Labels manager quick-create bar.
  ///
  /// In en, this message translates to:
  /// **'Quick-create a new label...'**
  String get quickCreateLabelHint;

  /// Input placeholder in the Locations manager quick-create bar.
  ///
  /// In en, this message translates to:
  /// **'Quick-create a new location...'**
  String get quickCreateLocationHint;

  /// Subtitle for the Labels manager view.
  ///
  /// In en, this message translates to:
  /// **'Contexts, scoped queues, reference links, and inherited conditions.'**
  String get labelsManagerSubtitle;

  /// Subtitle for the Locations manager view.
  ///
  /// In en, this message translates to:
  /// **'Reusable locations for task and label GPS conditions.'**
  String get locationsManagerSubtitle;

  /// Placeholder in the Searchable Label Picker input.
  ///
  /// In en, this message translates to:
  /// **'Search or create label...'**
  String get labelPickerSearchPlaceholder;

  /// Scope filter chip showing all labels in the picker.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String labelPickerFilterAll(String count);

  /// Scope filter chip showing scoped queue labels in the picker.
  ///
  /// In en, this message translates to:
  /// **'Scoped ({count})'**
  String labelPickerFilterScoped(String count);

  /// Scope filter chip showing global context labels in the picker.
  ///
  /// In en, this message translates to:
  /// **'Global ({count})'**
  String labelPickerFilterGlobal(String count);

  /// Empty state when label picker filter matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No matching labels found.'**
  String get labelPickerNoMatches;

  /// Empty state in label picker when no labels exist yet.
  ///
  /// In en, this message translates to:
  /// **'No labels yet. Type a name above to create one.'**
  String get labelPickerEmptyHint;

  /// Inline creation row text inside the label picker.
  ///
  /// In en, this message translates to:
  /// **'Create & assign \"{name}\"'**
  String labelPickerCreateAndAssign(String name);

  /// Tooltip removing a label chip.
  ///
  /// In en, this message translates to:
  /// **'Remove label: {name}'**
  String labelPickerRemoveTooltip(String name);

  /// Count pill showing open tasks referencing a label or location.
  ///
  /// In en, this message translates to:
  /// **'{count} open'**
  String openTasksCountPill(String count);

  /// Disabled row hint preventing a prerequisite dependency cycle.
  ///
  /// In en, this message translates to:
  /// **'Cycle prevented'**
  String get prerequisiteCyclePreventedHint;

  /// Label board scope option for global context labels.
  ///
  /// In en, this message translates to:
  /// **'Global Context'**
  String get globalContextLabel;

  /// Label board scope option and badge for scoped queue labels.
  ///
  /// In en, this message translates to:
  /// **'Scoped Queue'**
  String get scopedQueueLabel;

  /// Condition dimension option inheriting label conditions.
  ///
  /// In en, this message translates to:
  /// **'Inherit label conditions'**
  String get conditionInheritLabel;

  /// Condition dimension option configuring custom task rules.
  ///
  /// In en, this message translates to:
  /// **'Custom condition'**
  String get conditionCustomLabel;

  /// Status line when activation conditions are currently satisfied.
  ///
  /// In en, this message translates to:
  /// **'Currently satisfied'**
  String get conditionSatisfiedStatus;

  /// Status line when activation conditions are currently unmet.
  ///
  /// In en, this message translates to:
  /// **'Currently unmet (blocked)'**
  String get conditionBlockedStatus;

  /// Suspension mode with an explicit timestamp.
  ///
  /// In en, this message translates to:
  /// **'Until a date and time'**
  String get suspendedUntilModeLabel;

  /// Suspension mode without an end timestamp.
  ///
  /// In en, this message translates to:
  /// **'Indefinitely'**
  String get suspendedForeverModeLabel;

  /// Tooltip toggling optional history timestamp override field.
  ///
  /// In en, this message translates to:
  /// **'Set timestamp'**
  String get historyTimestampToggleTooltip;

  /// Validation error when adding or editing a duplicate history entry.
  ///
  /// In en, this message translates to:
  /// **'An identical history entry with this timestamp already exists.'**
  String get historyErrorDuplicate;

  /// Formatted radius readout in expanded location card.
  ///
  /// In en, this message translates to:
  /// **'Radius: {radius}'**
  String locationRadiusReadout(String radius);

  /// Floating notice when an expanded or edited entity is deleted externally.
  ///
  /// In en, this message translates to:
  /// **'This item was removed by an external update.'**
  String get entityRemovedExternallyNotice;

  /// Floating notice when an edited task is completed externally.
  ///
  /// In en, this message translates to:
  /// **'This task was completed by an external update.'**
  String get taskCompletedExternallyNotice;

  /// Toast notice after copying a label ID.
  ///
  /// In en, this message translates to:
  /// **'Label ID copied to clipboard.'**
  String get labelIdCopiedNotice;

  /// Toast notice after copying a location ID.
  ///
  /// In en, this message translates to:
  /// **'Location ID copied to clipboard.'**
  String get locationIdCopiedNotice;

  /// Toast notice after restoring a completed task.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" restored.'**
  String taskRestoredNotice(String title);

  /// Toast notice after completing a recurring task.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" completed and rescheduled for the next cycle.'**
  String taskCompletedRepeatNotice(String title);

  /// Toast notice after undoing the last entry in the undo stack.
  ///
  /// In en, this message translates to:
  /// **'Action undone.'**
  String get actionUndoneNotice;

  /// Toast notice after undoing with remaining undo entries.
  ///
  /// In en, this message translates to:
  /// **'Action undone ({remaining} more in history).'**
  String actionUndoneRemainingNotice(String remaining);

  /// Toast notice after switching active workspace.
  ///
  /// In en, this message translates to:
  /// **'Switched workspace: {name}'**
  String workspaceSwitchedNotice(String name);

  /// Toast notice after applying current GPS fix to a location.
  ///
  /// In en, this message translates to:
  /// **'Current GPS position applied.'**
  String get gpsAppliedNotice;

  /// Toast notice after resolving an address or Plus Code.
  ///
  /// In en, this message translates to:
  /// **'Source resolved to coordinates.'**
  String get locationResolvedNotice;

  /// Toast notice after saving a label.
  ///
  /// In en, this message translates to:
  /// **'Label saved.'**
  String get labelSavedNotice;

  /// Toast notice after deleting a label.
  ///
  /// In en, this message translates to:
  /// **'Label deleted.'**
  String get labelDeletedNotice;

  /// Toast notice after saving a location.
  ///
  /// In en, this message translates to:
  /// **'Location saved.'**
  String get locationSavedNotice;

  /// Toast notice after deleting a location.
  ///
  /// In en, this message translates to:
  /// **'Location deleted.'**
  String get locationDeletedNotice;

  /// Toast notice after saving a task in the current tier.
  ///
  /// In en, this message translates to:
  /// **'Task saved.'**
  String get noticeTaskSaved;

  /// Toast notice when a saved or created task lands in another tier.
  ///
  /// In en, this message translates to:
  /// **'Saved · now in {tier}'**
  String noticeTaskSavedInTier(String tier);

  /// Toast notice when a task moves into a scoped queue.
  ///
  /// In en, this message translates to:
  /// **'Moved to scoped queue: {label}'**
  String noticeTaskMovedToScopedQueue(String label);

  /// Toast notice when priority placement is enabled.
  ///
  /// In en, this message translates to:
  /// **'Task prioritized'**
  String get noticePriorityEnabled;

  /// Toast notice when priority placement is cleared.
  ///
  /// In en, this message translates to:
  /// **'Priority cleared'**
  String get noticePriorityDisabled;

  /// Toast notice when task placement switches to Someday.
  ///
  /// In en, this message translates to:
  /// **'Moved to Someday'**
  String get noticeMovedToSomeday;

  /// Toast notice when task placement switches to active queue.
  ///
  /// In en, this message translates to:
  /// **'Activated in queue'**
  String get noticeMovedToQueue;

  /// Toast notice when assigning a label to a task.
  ///
  /// In en, this message translates to:
  /// **'Label added: {name}'**
  String noticeLabelAdded(String name);

  /// Toast notice when removing a label from a task.
  ///
  /// In en, this message translates to:
  /// **'Label removed: {name}'**
  String noticeLabelRemoved(String name);

  /// Toast notice when creating and assigning a label inline.
  ///
  /// In en, this message translates to:
  /// **'Label created and assigned: {name}'**
  String noticeLabelCreatedAndAssigned(String name);

  /// Subtitle in the Settings page header.
  ///
  /// In en, this message translates to:
  /// **'Configuration for active workspace \"{workspace}\".'**
  String settingsWorkspaceSubtitle(String workspace);

  /// Badge indicating a Settings card commits changes immediately.
  ///
  /// In en, this message translates to:
  /// **'Auto-saved'**
  String get settingsAutoSavedBadge;

  /// Warning badge indicating unsaved WebDAV edits in Settings.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get settingsUnsavedChangesBadge;

  /// Tooltip explaining why Local Move is disabled when unsupported.
  ///
  /// In en, this message translates to:
  /// **'Moving directories is available only on desktop platforms (Linux/Windows).'**
  String get settingsMoveDesktopOnlyTooltip;

  /// Validation error when a WebDAV URL contains userinfo.
  ///
  /// In en, this message translates to:
  /// **'URL must not contain embedded credentials (user:pass@).'**
  String get webDavUrlUserinfoError;

  /// Validation error when a WebDAV remote file path is invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid remote file path (\"..\", backslashes, and control characters are forbidden).'**
  String get webDavPathInvalidError;

  /// Subtitle for the Diagnostic Log view.
  ///
  /// In en, this message translates to:
  /// **'Structured runtime entries (credentials, raw GPS coordinates, and notes redacted).'**
  String get logViewerSubtitle;

  /// Dropdown label for diagnostic log subsystem tag filter.
  ///
  /// In en, this message translates to:
  /// **'Subsystem'**
  String get logFilterSubsystemLabel;

  /// Button label uploading diagnostic log to WebDAV.
  ///
  /// In en, this message translates to:
  /// **'Upload Log'**
  String get logActionUpload;

  /// Button label clearing diagnostic log entries.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logActionClear;

  /// Heading for the TDF-DEL-003 Deletion Conflict resolution view.
  ///
  /// In en, this message translates to:
  /// **'Resolve Deletion Conflicts (TDF-DEL-003)'**
  String get conflictResolutionTitle;

  /// Subtitle for the Deletion Conflict resolution view.
  ///
  /// In en, this message translates to:
  /// **'Choose whether to keep the concurrent local edit or confirm deletion for each conflicted item.'**
  String get conflictResolutionSubtitle;

  /// Segmented option keeping concurrent local edits in a deletion conflict.
  ///
  /// In en, this message translates to:
  /// **'Keep Edit (Undelete)'**
  String get conflictKeepEditOption;

  /// Segmented option confirming deletion in a deletion conflict.
  ///
  /// In en, this message translates to:
  /// **'Confirm Deletion'**
  String get conflictConfirmDeleteOption;

  /// Primary dock button applying deletion conflict decisions.
  ///
  /// In en, this message translates to:
  /// **'Apply Decisions & Sync'**
  String get conflictApplyAndSyncAction;

  /// Toast notice after resolving deletion conflicts.
  ///
  /// In en, this message translates to:
  /// **'Deletion conflicts resolved. Synchronization resumed.'**
  String get conflictResolvedNotice;

  /// Heading for the TDF-REC-002 Generation Recovery resolution view.
  ///
  /// In en, this message translates to:
  /// **'Recover After History Advancement (TDF-REC-002)'**
  String get recoveryResolutionTitle;

  /// Subtitle for the Generation Recovery resolution view.
  ///
  /// In en, this message translates to:
  /// **'Shared deletion history advanced past the last acknowledged state. Choose an action for each affected local item.'**
  String get recoveryResolutionSubtitle;

  /// Segmented option recovering a retired local entity under a fresh ID.
  ///
  /// In en, this message translates to:
  /// **'Recover as New (fresh ID)'**
  String get recoveryAsNewOption;

  /// Segmented option discarding an affected local change during recovery.
  ///
  /// In en, this message translates to:
  /// **'Discard Local Change'**
  String get recoveryDiscardLocalOption;

  /// Primary dock button applying generation recovery decisions.
  ///
  /// In en, this message translates to:
  /// **'Apply Recovery & Sync'**
  String get recoveryApplyAndSyncAction;

  /// Toast notice after completing generation recovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery completed. Synchronization resumed.'**
  String get recoveryResolvedNotice;

  /// Uppercase entity kind badge in conflict and recovery cards.
  ///
  /// In en, this message translates to:
  /// **'TASK'**
  String get entityKindTaskBadge;

  /// Uppercase entity kind badge in conflict and recovery cards.
  ///
  /// In en, this message translates to:
  /// **'LABEL'**
  String get entityKindLabelBadge;

  /// Uppercase entity kind badge in conflict and recovery cards.
  ///
  /// In en, this message translates to:
  /// **'LOCATION'**
  String get entityKindLocationBadge;

  /// Tooltip for the desktop top chrome window close button
  ///
  /// In en, this message translates to:
  /// **'Close TierTask'**
  String get tooltipCloseApp;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
