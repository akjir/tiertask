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
  /// **'Raw TDF (Single Source of Truth)'**
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

  /// Section heading for open task count visibility selection in settings.
  ///
  /// In en, this message translates to:
  /// **'Open Task Count'**
  String get openTaskCountSectionTitle;

  /// Helper description explaining the open task count visibility setting.
  ///
  /// In en, this message translates to:
  /// **'Show or hide the total number of open tasks on label cards.'**
  String get openTaskCountSectionDescription;

  /// Option label to hide the total open task count on label cards.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get openTaskCountOff;

  /// Option label to show the total open task count on label cards.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get openTaskCountOn;

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
  /// **'WebDAV Synchronization (Single Source of Truth)'**
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

  /// Uppercase section label above the label chips or summary cards.
  ///
  /// In en, this message translates to:
  /// **'LABELS'**
  String get sectionLabels;

  /// Total task counter label displayed at the top of label cards.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks'**
  String taskCountLabel(int count);

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
  /// **'Search focus tasks...'**
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

  /// Tooltip for the button that renames or saves a label.
  ///
  /// In en, this message translates to:
  /// **'Rename label'**
  String get tooltipRenameLabel;

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
