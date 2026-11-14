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

  /// Tab label for the combined Focus and Ready view.
  ///
  /// In en, this message translates to:
  /// **'Focus & Ready'**
  String get tabFocusAndReady;

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

  /// Fallback empty-state message for a section with the given heading.
  ///
  /// In en, this message translates to:
  /// **'No entries in {heading}.'**
  String emptySectionEntries(String heading);

  /// Tooltip for the WebDAV synchronization button in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Synchronize with WebDAV'**
  String get tooltipSyncWebDav;

  /// Tooltip for the raw TDF preview button in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Show TDF preview'**
  String get tooltipMarkdownPreview;

  /// Tooltip for the settings button in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// Dialog title for the raw TDF preview dialog.
  ///
  /// In en, this message translates to:
  /// **'Raw TDF'**
  String get markdownPreviewTitle;

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

  /// Heading for the WebDAV synchronization error card.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Synchronization Error'**
  String get syncErrorTitle;

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

  /// Button label in the quick-add bar to open the extended task view.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get quickAddAdvanced;

  /// Header title for the extended task creation view.
  ///
  /// In en, this message translates to:
  /// **'Extended Task View'**
  String get advancedTaskTitle;

  /// Header title when editing an existing task in the extended task view.
  ///
  /// In en, this message translates to:
  /// **'Edit Task'**
  String get editTaskTitle;

  /// Tooltip for the downward arrow button that downgrades a task.
  ///
  /// In en, this message translates to:
  /// **'Downgrade task'**
  String get tooltipDowngradeTask;

  /// Tooltip for the edit button on a task card.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get tooltipEditTask;

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

  /// Input label for the local TDF file name or path field.
  ///
  /// In en, this message translates to:
  /// **'Local TDF File Name'**
  String get localFilePathLabel;

  /// Placeholder hint for the local TDF file name field.
  ///
  /// In en, this message translates to:
  /// **'tiertask.tdf or t2.tdf'**
  String get localFilePathHint;

  /// Validation error shown when the local file name field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a local file name.'**
  String get localFilePathErrorEmpty;

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

  /// Uppercase section label above the Focus tasks list on the landing page.
  ///
  /// In en, this message translates to:
  /// **'FOCUS TASKS'**
  String get sectionFocusTasks;

  /// Uppercase section label above the Ready tasks list on the Ready tier panel.
  ///
  /// In en, this message translates to:
  /// **'READY TASKS'**
  String get sectionReadyTasks;

  /// Uppercase section label above the Planned tasks list on the Planned tier panel.
  ///
  /// In en, this message translates to:
  /// **'PLANNED TASKS'**
  String get sectionPlannedTasks;

  /// Uppercase section label above the Blocked tasks list on the Blocked tier panel.
  ///
  /// In en, this message translates to:
  /// **'BLOCKED TASKS'**
  String get sectionBlockedTasks;

  /// Uppercase section label above the Someday tasks list on the Someday tier panel.
  ///
  /// In en, this message translates to:
  /// **'SOMEDAY TASKS'**
  String get sectionSomedayTasks;

  /// Uppercase section label above the Completed tasks list on the Completed tier panel.
  ///
  /// In en, this message translates to:
  /// **'COMPLETED TASKS'**
  String get sectionCompletedTasks;

  /// Uppercase section label above the All Tasks list in the search view.
  ///
  /// In en, this message translates to:
  /// **'ALL TASKS'**
  String get sectionAllTasks;

  /// Uppercase section label above the label chips or summary cards.
  ///
  /// In en, this message translates to:
  /// **'LABELS'**
  String get sectionLabels;

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

  /// Input label for the direct hexadecimal color field.
  ///
  /// In en, this message translates to:
  /// **'Hex Color'**
  String get colorHexLabel;

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

  /// Action label and input hint for creating a new label.
  ///
  /// In en, this message translates to:
  /// **'Create new label'**
  String get createNewLabel;

  /// Screen title for the label management screen.
  ///
  /// In en, this message translates to:
  /// **'Edit labels'**
  String get editLabelsTitle;

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

  /// Placeholder hint inside the suspended-until timestamp field.
  ///
  /// In en, this message translates to:
  /// **'YYYY-MM-DD [HH:MM] (empty = indefinite)'**
  String get taskSuspendedUntilHint;

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

  /// Input hint for latitude in a GPS location condition.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get conditionLocationLatHint;

  /// Input hint for longitude in a GPS location condition.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get conditionLocationLonHint;

  /// Input hint for radius in a GPS location condition.
  ///
  /// In en, this message translates to:
  /// **'Radius (m/km)'**
  String get conditionLocationRadiusHint;

  /// Validation error shown when a GPS location condition input is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter valid latitude, longitude, and radius (e.g. 200m or 1.5km).'**
  String get conditionLocationErrorInvalid;

  /// Tooltip for the button that adds a GPS location condition.
  ///
  /// In en, this message translates to:
  /// **'Add location rule'**
  String get tooltipAddLocationCondition;

  /// Tooltip for the button that removes a GPS location condition.
  ///
  /// In en, this message translates to:
  /// **'Remove location rule'**
  String get tooltipRemoveLocationCondition;

  /// Section card title for task name and note in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Task Details'**
  String get taskDetailsSectionTitle;

  /// Section card title for scheduling mode and suspension in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Scheduling & Status'**
  String get taskSchedulingSectionTitle;

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

  /// Section card description for activation conditions in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Restrict when and where this task becomes active, or override inherited label conditions.'**
  String get taskConditionsSectionDescription;

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

  /// Tooltip for clearing the suspended timestamp field.
  ///
  /// In en, this message translates to:
  /// **'Clear timestamp'**
  String get tooltipClearDate;

  /// Tooltip for the start time picker button in time window conditions.
  ///
  /// In en, this message translates to:
  /// **'Pick start time'**
  String get tooltipPickStartTime;

  /// Tooltip for the end time picker button in time window conditions.
  ///
  /// In en, this message translates to:
  /// **'Pick end time'**
  String get tooltipPickEndTime;

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

  /// Label for the Slate Material 3 color palette.
  ///
  /// In en, this message translates to:
  /// **'Slate'**
  String get themePaletteSlate;

  /// Label for the Navy Material 3 color palette.
  ///
  /// In en, this message translates to:
  /// **'Navy'**
  String get themePaletteNavy;

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

  /// Button label to select a different local TDF directory on desktop platforms.
  ///
  /// In en, this message translates to:
  /// **'Change Directory'**
  String get actionChangeDirectory;

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

  /// Tooltip for the passive priority indicator icon on a task card.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get tooltipIndicatorPriority;

  /// Tooltip for the passive repeat indicator icon on a task card.
  ///
  /// In en, this message translates to:
  /// **'Repeating task'**
  String get tooltipIndicatorRepeat;

  /// Tooltip for the passive subtasks indicator icon on a task card when auto-finish is disabled.
  ///
  /// In en, this message translates to:
  /// **'Subtasks'**
  String get tooltipIndicatorSubtasks;

  /// Tooltip for the passive subtasks indicator icon on a task card when auto-finish is enabled.
  ///
  /// In en, this message translates to:
  /// **'Subtasks (auto-finish)'**
  String get tooltipIndicatorSubtasksAutoFinish;

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

  /// Header title when editing a label in the label editor screen.
  ///
  /// In en, this message translates to:
  /// **'Edit Label'**
  String get editLabelTitle;

  /// Tooltip for the edit button on a label row.
  ///
  /// In en, this message translates to:
  /// **'Edit label'**
  String get tooltipEditLabel;

  /// Section card title for label name and note in the label editor.
  ///
  /// In en, this message translates to:
  /// **'Label Details'**
  String get labelDetailsSectionTitle;

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

  /// Tooltip for the passive link indicator icon on a task pill.
  ///
  /// In en, this message translates to:
  /// **'Has links'**
  String get tooltipIndicatorLinks;

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

  /// Tooltip for the Clear Log button in the diagnostic log viewer.
  ///
  /// In en, this message translates to:
  /// **'Clear Log'**
  String get tooltipClearLog;

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

  /// Error message shown when the local TDF file uses an unsupported version, recommending an application update.
  ///
  /// In en, this message translates to:
  /// **'The local file uses unsupported file version {version}. Please update TierTask to a newer version.'**
  String errorUnsupportedTdfVersionLocal(String version);

  /// Error message shown when the remote WebDAV TDF file uses an unsupported version, recommending an application update.
  ///
  /// In en, this message translates to:
  /// **'The remote file uses unsupported file version {version}. Please update TierTask to a newer version.'**
  String errorUnsupportedTdfVersionRemote(String version);

  /// Error message shown when both the local and remote WebDAV TDF files use an unsupported version, recommending an application update.
  ///
  /// In en, this message translates to:
  /// **'The local and remote files use unsupported file version {version}. Please update TierTask to a newer version.'**
  String errorUnsupportedTdfVersionBoth(String version);

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

  /// Localized string for logMetadataSectionTitle
  ///
  /// In en, this message translates to:
  /// **'Session Metadata'**
  String get logMetadataSectionTitle;

  /// Localized string for logMetadataFile
  ///
  /// In en, this message translates to:
  /// **'File: {fileName}'**
  String logMetadataFile(String fileName);

  /// Localized string for logMetadataVersion
  ///
  /// In en, this message translates to:
  /// **'Version: {version}'**
  String logMetadataVersion(String version);

  /// Localized string for logMetadataPlatform
  ///
  /// In en, this message translates to:
  /// **'Platform: {platform}'**
  String logMetadataPlatform(String platform);

  /// Localized string for logMetadataWorkspace
  ///
  /// In en, this message translates to:
  /// **'Workspace: {workspace}'**
  String logMetadataWorkspace(String workspace);

  /// Localized string for logMetadataTimeZone
  ///
  /// In en, this message translates to:
  /// **'Time Zone: {timeZone}'**
  String logMetadataTimeZone(String timeZone);

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

  /// Localized string for tooltipSyncLogWebDav
  ///
  /// In en, this message translates to:
  /// **'Sync log to WebDAV'**
  String get tooltipSyncLogWebDav;

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

  /// Tooltip for the Any day condition reset chip in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Explicitly overrides all weekday restrictions from assigned labels so this task is active on any day.'**
  String get tooltipConditionDayAny;

  /// Tooltip for the Any time condition reset chip in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Explicitly overrides all time window restrictions from assigned labels so this task is active at any time.'**
  String get tooltipConditionTimeAny;

  /// Tooltip for the Any location condition reset chip in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Explicitly overrides all location restrictions from assigned labels so this task is active at any location.'**
  String get tooltipConditionLocationAny;

  /// Tooltip for the Priority toggle chip in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Marks this task as priority so it is pulled into Focus or Ready ahead of standard tasks.'**
  String get tooltipTaskEditorPriority;

  /// Tooltip for the Someday toggle chip in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Parks this task in the Someday backlog without pulling it into active tiers.'**
  String get tooltipTaskEditorSomeday;

  /// Tooltip for the Suspended toggle chip in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Defers this task to Blocked (optionally until a chosen timestamp) and disables condition evaluation while active.'**
  String get tooltipTaskEditorSuspended;

  /// Tooltip for the Repeat toggle chip in the task editor.
  ///
  /// In en, this message translates to:
  /// **'Automatically reschedules this task after the configured interval upon completion and resets all subtasks.'**
  String get tooltipTaskEditorRepeat;

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

  /// Action label and input hint for creating a new location.
  ///
  /// In en, this message translates to:
  /// **'Create new location'**
  String get createNewLocation;

  /// Screen title for the location management screen.
  ///
  /// In en, this message translates to:
  /// **'Edit locations'**
  String get editLocationsTitle;

  /// Header title when editing a location in the location editor screen.
  ///
  /// In en, this message translates to:
  /// **'Edit Location'**
  String get editLocationTitle;

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

  /// Tooltip for the edit button on a location row.
  ///
  /// In en, this message translates to:
  /// **'Edit location'**
  String get tooltipEditLocation;

  /// Section card title for location name, source, and note in the location editor.
  ///
  /// In en, this message translates to:
  /// **'Location Details'**
  String get locationDetailsSectionTitle;

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

  /// Switch title for marking a label as scoped in the label editor.
  ///
  /// In en, this message translates to:
  /// **'Scoped Label'**
  String get labelScopedSwitchTitle;

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

  /// Tooltip for clearing the due timestamp field.
  ///
  /// In en, this message translates to:
  /// **'Clear due timestamp'**
  String get taskDueClearTooltip;

  /// Badge text on a task pill showing the due date.
  ///
  /// In en, this message translates to:
  /// **'Due: {date}'**
  String pillDuePrefix(String date);

  /// Error message shown when concurrent local file edits exceed maxCasRetries.
  ///
  /// In en, this message translates to:
  /// **'Local file was modified concurrently and exceeded maximum merge retries.'**
  String get errorLocalFileCasExhausted;

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

  /// Tooltip for the suspended task indicator icon.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get tooltipIndicatorSuspended;

  /// Tooltip for the prerequisite tasks indicator icon.
  ///
  /// In en, this message translates to:
  /// **'Prerequisite tasks'**
  String get tooltipIndicatorBlockedBy;

  /// Tooltip for the activation conditions indicator icon.
  ///
  /// In en, this message translates to:
  /// **'Activation conditions'**
  String get tooltipIndicatorConditions;

  /// Tooltip for the summary indicator icon when more than 3 indicators are active.
  ///
  /// In en, this message translates to:
  /// **'Task information ({count} indicators)'**
  String tooltipIndicatorSummary(String count);

  /// Dialog title for the task information overlay.
  ///
  /// In en, this message translates to:
  /// **'Task Information'**
  String get taskInfoDialogTitle;

  /// Value text shown for a prioritized task in the task information dialog.
  ///
  /// In en, this message translates to:
  /// **'Prioritized in queue'**
  String get taskInfoPriorityValue;

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

  /// Value text shown when a task's suspension timestamp is in the past.
  ///
  /// In en, this message translates to:
  /// **'Elapsed ({timestamp})'**
  String taskInfoSuspendedElapsed(String timestamp);

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

  /// Dialog title when confirming deletion of a task.
  ///
  /// In en, this message translates to:
  /// **'Delete Task'**
  String get deleteTaskDialogTitle;

  /// Confirmation prompt shown before deleting a task.
  ///
  /// In en, this message translates to:
  /// **'Delete task \"{title}\"? This action can be undone while the workspace remains open.'**
  String deleteTaskConfirmMessage(String title);

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
