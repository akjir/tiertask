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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'TierTask (T2)'**
  String get appTitle;

  /// No description provided for @tier1Name.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get tier1Name;

  /// No description provided for @tier2Name.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get tier2Name;

  /// No description provided for @tier3Name.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get tier3Name;

  /// No description provided for @tier4Name.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get tier4Name;

  /// No description provided for @tier5Name.
  ///
  /// In en, this message translates to:
  /// **'Someday'**
  String get tier5Name;

  /// No description provided for @tier6Name.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get tier6Name;

  /// No description provided for @tier1Description.
  ///
  /// In en, this message translates to:
  /// **'Active top priority (Soft limit: 3)'**
  String get tier1Description;

  /// No description provided for @tier2Description.
  ///
  /// In en, this message translates to:
  /// **'Ready for Focus (Soft limit: 5)'**
  String get tier2Description;

  /// No description provided for @tier3Description.
  ///
  /// In en, this message translates to:
  /// **'Active backlog (automatically pulls into Ready)'**
  String get tier3Description;

  /// No description provided for @tier4Description.
  ///
  /// In en, this message translates to:
  /// **'Waiting on external events or third parties'**
  String get tier4Description;

  /// No description provided for @tier5Description.
  ///
  /// In en, this message translates to:
  /// **'Idea storage without automatic pull'**
  String get tier5Description;

  /// No description provided for @tier6Description.
  ///
  /// In en, this message translates to:
  /// **'Completed tasks (30-day retention)'**
  String get tier6Description;

  /// No description provided for @tabFocusAndReady.
  ///
  /// In en, this message translates to:
  /// **'[1] Focus & [2] Ready'**
  String get tabFocusAndReady;

  /// No description provided for @emptyFocusHint.
  ///
  /// In en, this message translates to:
  /// **'No tasks in # [1] Focus. Tasks from # [2] Ready or # [3] Planned automatically move up here.'**
  String get emptyFocusHint;

  /// No description provided for @emptyReadyHint.
  ///
  /// In en, this message translates to:
  /// **'No tasks in # [2] Ready.'**
  String get emptyReadyHint;

  /// No description provided for @emptyPlannedHint.
  ///
  /// In en, this message translates to:
  /// **'No tasks in active backlog (# [3] Planned).'**
  String get emptyPlannedHint;

  /// No description provided for @emptyBlockedHint.
  ///
  /// In en, this message translates to:
  /// **'No blocked tasks (# [4] Blocked).'**
  String get emptyBlockedHint;

  /// No description provided for @emptySomedayHint.
  ///
  /// In en, this message translates to:
  /// **'No ideas stored in # [5] Someday.'**
  String get emptySomedayHint;

  /// No description provided for @emptyCompletedHint.
  ///
  /// In en, this message translates to:
  /// **'No completed tasks from the last 30 days.'**
  String get emptyCompletedHint;

  /// No description provided for @emptySectionEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries in {heading}.'**
  String emptySectionEntries(String heading);

  /// No description provided for @tooltipSyncWebDav.
  ///
  /// In en, this message translates to:
  /// **'Synchronize with WebDAV'**
  String get tooltipSyncWebDav;

  /// No description provided for @tooltipMarkdownPreview.
  ///
  /// In en, this message translates to:
  /// **'Show Markdown preview'**
  String get tooltipMarkdownPreview;

  /// No description provided for @tooltipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// No description provided for @markdownPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Raw Markdown (Single Source of Truth)'**
  String get markdownPreviewTitle;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @unconfiguredBannerText.
  ///
  /// In en, this message translates to:
  /// **'Local mode active. Configure WebDAV for synchronization.'**
  String get unconfiguredBannerText;

  /// No description provided for @actionConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get actionConfigure;

  /// No description provided for @syncErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Synchronization Error'**
  String get syncErrorTitle;

  /// No description provided for @actionSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get actionSettings;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @defaultTierChipLabel.
  ///
  /// In en, this message translates to:
  /// **'{heading} (Default)'**
  String defaultTierChipLabel(String heading);

  /// No description provided for @quickAddHint.
  ///
  /// In en, this message translates to:
  /// **'Add new task to {heading}...'**
  String quickAddHint(String heading);

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @restoreTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Task'**
  String get restoreTaskTitle;

  /// No description provided for @moveTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Move Task'**
  String get moveTaskTitle;

  /// No description provided for @selectTargetTierSubtitle.
  ///
  /// In en, this message translates to:
  /// **'\"{taskTitle}\" - Select target tier:'**
  String selectTargetTierSubtitle(String taskTitle);

  /// No description provided for @completedOnDate.
  ///
  /// In en, this message translates to:
  /// **'Completed on {date}'**
  String completedOnDate(String date);

  /// No description provided for @tooltipDowngradeToReady.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to # [2] Ready'**
  String get tooltipDowngradeToReady;

  /// No description provided for @tooltipDowngradeToPlanned.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to # [3] Planned'**
  String get tooltipDowngradeToPlanned;

  /// No description provided for @tooltipBlockTask.
  ///
  /// In en, this message translates to:
  /// **'Move immediately to # [4] Blocked'**
  String get tooltipBlockTask;

  /// No description provided for @tooltipPromoteToPlanned.
  ///
  /// In en, this message translates to:
  /// **'Queue in # [3] Planned'**
  String get tooltipPromoteToPlanned;

  /// No description provided for @tooltipMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get tooltipMoreActions;

  /// No description provided for @menuMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to...'**
  String get menuMoveTo;

  /// No description provided for @menuEditText.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get menuEditText;

  /// No description provided for @menuDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get menuDelete;

  /// No description provided for @editTaskDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Task'**
  String get editTaskDialogTitle;

  /// No description provided for @editTaskFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Task text'**
  String get editTaskFieldLabel;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @languageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSectionTitle;

  /// No description provided for @languageSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the display language. System uses German on German systems and English otherwise.'**
  String get languageSectionDescription;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// No description provided for @webdavSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Synchronization (Single Source of Truth)'**
  String get webdavSectionTitle;

  /// No description provided for @webdavSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'TierTask stores all tasks in a single Markdown file (tiertask.md) on your WebDAV server. Use an application password when supported by your server.'**
  String get webdavSectionDescription;

  /// No description provided for @serverUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Server URL'**
  String get serverUrlLabel;

  /// No description provided for @serverUrlErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a server URL.'**
  String get serverUrlErrorEmpty;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @usernameErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username.'**
  String get usernameErrorEmpty;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'App Password / Password'**
  String get passwordLabel;

  /// No description provided for @tooltipShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get tooltipShowPassword;

  /// No description provided for @tooltipHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get tooltipHidePassword;

  /// No description provided for @passwordErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password or app password.'**
  String get passwordErrorEmpty;

  /// No description provided for @filePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Markdown File Name / Path'**
  String get filePathLabel;

  /// No description provided for @filePathHint.
  ///
  /// In en, this message translates to:
  /// **'tiertask.md or t2.md'**
  String get filePathHint;

  /// No description provided for @resolvedEndpointLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolved WebDAV Endpoint (GET / PUT):'**
  String get resolvedEndpointLabel;

  /// No description provided for @credentialsSavedBanner.
  ///
  /// In en, this message translates to:
  /// **'Settings saved locally.'**
  String get credentialsSavedBanner;

  /// No description provided for @connectionSuccessBanner.
  ///
  /// In en, this message translates to:
  /// **'Connection succeeded. Markdown file synchronized with WebDAV.'**
  String get connectionSuccessBanner;

  /// No description provided for @actionTestConnectionAndSync.
  ///
  /// In en, this message translates to:
  /// **'Test Connection / Sync Now'**
  String get actionTestConnectionAndSync;

  /// No description provided for @errorWebDavNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Please configure WebDAV in Settings first.'**
  String get errorWebDavNotConfigured;

  /// No description provided for @errorInvalidServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid WebDAV server URL.'**
  String get errorInvalidServerUrl;

  /// No description provided for @errorAuthFailedLoad.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Please check username and app password.'**
  String get errorAuthFailedLoad;

  /// No description provided for @errorLoadMarkdownFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load Markdown file from server.'**
  String get errorLoadMarkdownFailed;

  /// No description provided for @errorNetworkUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Network error: Server unreachable ({details}).'**
  String errorNetworkUnreachable(String details);

  /// No description provided for @errorTimeoutLoad.
  ///
  /// In en, this message translates to:
  /// **'Connection to WebDAV server timed out.'**
  String get errorTimeoutLoad;

  /// No description provided for @errorTlsLoad.
  ///
  /// In en, this message translates to:
  /// **'TLS/SSL connection error: {details}'**
  String errorTlsLoad(String details);

  /// No description provided for @errorUnexpectedLoad.
  ///
  /// In en, this message translates to:
  /// **'Unexpected WebDAV error while loading: {details}'**
  String errorUnexpectedLoad(String details);

  /// No description provided for @errorAuthFailedSave.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed while saving. Please check app password.'**
  String get errorAuthFailedSave;

  /// No description provided for @errorSaveMarkdownFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save Markdown file on server.'**
  String get errorSaveMarkdownFailed;

  /// No description provided for @errorNetworkSave.
  ///
  /// In en, this message translates to:
  /// **'Network error while saving ({details}).'**
  String errorNetworkSave(String details);

  /// No description provided for @errorTimeoutSave.
  ///
  /// In en, this message translates to:
  /// **'Timed out while saving to WebDAV server.'**
  String get errorTimeoutSave;

  /// No description provided for @errorTlsSave.
  ///
  /// In en, this message translates to:
  /// **'TLS/SSL error while saving: {details}'**
  String errorTlsSave(String details);

  /// No description provided for @errorUnexpectedSave.
  ///
  /// In en, this message translates to:
  /// **'Unexpected WebDAV error while saving: {details}'**
  String errorUnexpectedSave(String details);
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
