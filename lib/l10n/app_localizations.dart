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

  /// Subtitle description for tier 1 (Focus).
  ///
  /// In en, this message translates to:
  /// **'Active top priority (Soft limit: 3)'**
  String get tier1Description;

  /// Subtitle description for tier 2 (Ready).
  ///
  /// In en, this message translates to:
  /// **'Ready for Focus (Soft limit: 5)'**
  String get tier2Description;

  /// Subtitle description for tier 3 (Planned).
  ///
  /// In en, this message translates to:
  /// **'Active backlog (automatically pulls into Ready)'**
  String get tier3Description;

  /// Subtitle description for tier 4 (Blocked).
  ///
  /// In en, this message translates to:
  /// **'Waiting on external events or third parties'**
  String get tier4Description;

  /// Subtitle description for tier 5 (Someday).
  ///
  /// In en, this message translates to:
  /// **'Idea storage without automatic pull'**
  String get tier5Description;

  /// Subtitle description for tier 6 (Completed).
  ///
  /// In en, this message translates to:
  /// **'Completed tasks (30-day retention)'**
  String get tier6Description;

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

  /// Tooltip for the raw Markdown preview button in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Show Markdown preview'**
  String get tooltipMarkdownPreview;

  /// Tooltip for the settings button in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// Dialog title for the raw Markdown preview dialog.
  ///
  /// In en, this message translates to:
  /// **'Raw Markdown (Single Source of Truth)'**
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

  /// Chip label indicating the default target tier in the quick-add bar.
  ///
  /// In en, this message translates to:
  /// **'{heading} (Default)'**
  String defaultTierChipLabel(String heading);

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

  /// Bottom sheet title when restoring a completed task to an active tier.
  ///
  /// In en, this message translates to:
  /// **'Restore Task'**
  String get restoreTaskTitle;

  /// Bottom sheet title when moving an active task to another tier.
  ///
  /// In en, this message translates to:
  /// **'Move Task'**
  String get moveTaskTitle;

  /// Subtitle in the move or restore sheet prompting selection of a target tier.
  ///
  /// In en, this message translates to:
  /// **'\"{taskTitle}\" - Select target tier:'**
  String selectTargetTierSubtitle(String taskTitle);

  /// Subtitle displaying the ISO completion date of a completed task.
  ///
  /// In en, this message translates to:
  /// **'Completed on {date}'**
  String completedOnDate(String date);

  /// Tooltip for downgrading a task from Focus to Ready.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to Ready'**
  String get tooltipDowngradeToReady;

  /// Tooltip for downgrading a task from Ready to Planned.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to Planned'**
  String get tooltipDowngradeToPlanned;

  /// Tooltip for moving a task directly to the Blocked tier.
  ///
  /// In en, this message translates to:
  /// **'Move immediately to Blocked'**
  String get tooltipBlockTask;

  /// Tooltip for promoting a task into the Planned tier.
  ///
  /// In en, this message translates to:
  /// **'Queue in Planned'**
  String get tooltipPromoteToPlanned;

  /// Tooltip for the task overflow action menu button.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get tooltipMoreActions;

  /// Menu item label to move a task to another tier.
  ///
  /// In en, this message translates to:
  /// **'Move to...'**
  String get menuMoveTo;

  /// Menu item label to edit a task title.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get menuEditText;

  /// Menu item label to delete a task.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get menuDelete;

  /// Dialog title for editing an existing task.
  ///
  /// In en, this message translates to:
  /// **'Edit Task'**
  String get editTaskDialogTitle;

  /// Input field label for the task title in the edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Task text'**
  String get editTaskFieldLabel;

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
  /// **'Select whether tasks are stored in a local Markdown file, on a WebDAV server, or in both locations.'**
  String get storageModeSectionDescription;

  /// Option label for local-only Markdown file storage.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get storageModeLocal;

  /// Option label for WebDAV-only Markdown synchronization.
  ///
  /// In en, this message translates to:
  /// **'WebDAV'**
  String get storageModeWebDav;

  /// Option label for combined local and WebDAV Markdown storage.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get storageModeBoth;

  /// Section heading for local Markdown file settings.
  ///
  /// In en, this message translates to:
  /// **'Local Markdown File'**
  String get localSectionTitle;

  /// Helper description explaining local Markdown file persistence.
  ///
  /// In en, this message translates to:
  /// **'Stores all tasks in a local Markdown file on this device.'**
  String get localSectionDescription;

  /// Input label for the local Markdown file name or path field.
  ///
  /// In en, this message translates to:
  /// **'Local Markdown File Name'**
  String get localFilePathLabel;

  /// Placeholder hint for the local Markdown file name field.
  ///
  /// In en, this message translates to:
  /// **'tiertask.md or t2.md'**
  String get localFilePathHint;

  /// Validation error shown when the local file name field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a local file name.'**
  String get localFilePathErrorEmpty;

  /// Label above the resolved local Markdown file path preview.
  ///
  /// In en, this message translates to:
  /// **'Resolved Local File Path:'**
  String get resolvedLocalPathLabel;

  /// Section heading for WebDAV synchronization settings.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Synchronization (Single Source of Truth)'**
  String get webdavSectionTitle;

  /// Helper description explaining WebDAV Markdown synchronization.
  ///
  /// In en, this message translates to:
  /// **'TierTask stores all tasks in a single Markdown file (tiertask.md) on your WebDAV server. Use an application password when supported by your server.'**
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

  /// Input label for the remote Markdown file name or path field.
  ///
  /// In en, this message translates to:
  /// **'Markdown File Name / Path'**
  String get filePathLabel;

  /// Placeholder hint for the remote Markdown file name field.
  ///
  /// In en, this message translates to:
  /// **'tiertask.md or t2.md'**
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
  /// **'Connection succeeded. Markdown file synchronized with WebDAV.'**
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

  /// Error message shown when loading the Markdown file fails with a non-success status.
  ///
  /// In en, this message translates to:
  /// **'Failed to load Markdown file from server.'**
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

  /// Error message shown when saving the Markdown file fails with a non-success status.
  ///
  /// In en, this message translates to:
  /// **'Failed to save Markdown file on server.'**
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

  /// Error message shown when the configured local Markdown file path is invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid local Markdown file name or path.'**
  String get errorInvalidLocalFilePath;

  /// Error message shown when a Markdown file exceeds maxFileBytes.
  ///
  /// In en, this message translates to:
  /// **'Markdown file exceeds the maximum allowed size.'**
  String get errorLocalFileTooLarge;

  /// Error message shown when reading the local Markdown file fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to read local Markdown file ({details}).'**
  String errorLoadLocalFileFailed(String details);

  /// Error message shown when writing the local Markdown file fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to write local Markdown file ({details}).'**
  String errorSaveLocalFileFailed(String details);
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
