// TierTask
// Copyright (C) 2026  Stefan Stark
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'clearable_text_field.dart';
import 'settings_local_storage_section.dart';
import 'settings_preference_cards.dart';

/// WebDAV connection text fields and remote file path input.
class SettingsFormFields extends StatelessWidget {
  /// Creates [SettingsFormFields].
  const SettingsFormFields({
    super.key,
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
  });

  /// Controller for the remote TDF file path field.
  final TextEditingController filePathController;

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  /// Controller for the password field.
  final TextEditingController passwordController;

  /// Controller for the server URL field.
  final TextEditingController serverUrlController;

  /// Controller for the username field.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebDavCredentialsFields(
          serverUrlController: serverUrlController,
          usernameController: usernameController,
          passwordController: passwordController,
          obscurePassword: obscurePassword,
          onToggleObscurePassword: onToggleObscurePassword,
        ),
        const SizedBox(height: 16),
        ClearableTextField(
          useFormField: true,
          controller: filePathController,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: localizations.filePathLabel,
            hintText: localizations.filePathHint,
            prefixIcon: const Icon(Icons.description_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// Server URL, username, and password input fields for WebDAV authentication.
class WebDavCredentialsFields extends StatelessWidget {
  /// Creates [WebDavCredentialsFields].
  const WebDavCredentialsFields({
    super.key,
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
  });

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  /// Controller for the password field.
  final TextEditingController passwordController;

  /// Controller for the server URL field.
  final TextEditingController serverUrlController;

  /// Controller for the username field.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WebDavServerUrlField(controller: serverUrlController),
        const SizedBox(height: 16),
        _WebDavUsernameField(controller: usernameController),
        const SizedBox(height: 16),
        WebDavPasswordField(
          controller: passwordController,
          obscurePassword: obscurePassword,
          onToggleObscurePassword: onToggleObscurePassword,
        ),
      ],
    );
  }
}

/// Password text field with a visibility toggle button for WebDAV authentication.
class WebDavPasswordField extends StatelessWidget {
  /// Creates a [WebDavPasswordField].
  const WebDavPasswordField({
    super.key,
    required this.controller,
    required this.obscurePassword,
    required this.onToggleObscurePassword,
  });

  /// Controller for the password input.
  final TextEditingController controller;

  /// Whether the password text is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ClearableTextField(
      useFormField: true,
      controller: controller,
      obscureText: obscurePassword,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: localizations.passwordLabel,
        prefixIcon: const Icon(Icons.key_outlined),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: obscurePassword
              ? localizations.tooltipShowPassword
              : localizations.tooltipHidePassword,
          icon: Icon(
            obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: onToggleObscurePassword,
        ),
      ),
      validator: (value) => (value == null || value.isEmpty)
          ? localizations.passwordErrorEmpty
          : null,
    );
  }
}

/// Card grouping the WebDAV synchronization header, connection form fields, and resolved URI preview.
class WebDavStorageSection extends StatelessWidget {
  /// Creates a [WebDavStorageSection].
  const WebDavStorageSection({
    super.key,
    required this.serverUrlController,
    required this.usernameController,
    required this.passwordController,
    required this.filePathController,
    required this.obscurePassword,
    required this.resolvedUri,
    required this.onToggleObscurePassword,
    this.onWipeRemoteFile,
  });

  /// Controller for the remote TDF file path field.
  final TextEditingController filePathController;

  /// Whether the password input is obscured.
  final bool obscurePassword;

  /// Callback to toggle password visibility.
  final VoidCallback onToggleObscurePassword;

  /// Optional callback to open the confirmation dialog and wipe the remote WebDAV `.tdf` file.
  final VoidCallback? onWipeRemoteFile;

  /// Controller for the password field.
  final TextEditingController passwordController;

  /// Resolved WebDAV endpoint URI preview, or `null` if empty.
  final Uri? resolvedUri;

  /// Controller for the server URL field.
  final TextEditingController serverUrlController;

  /// Controller for the username field.
  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final endpointUri = resolvedUri;

    return SettingsSectionCard(
      icon: Icons.cloud_sync_outlined,
      title: localizations.webdavSectionTitle,
      description: localizations.webdavSectionDescription,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsFormFields(
            serverUrlController: serverUrlController,
            usernameController: usernameController,
            passwordController: passwordController,
            filePathController: filePathController,
            obscurePassword: obscurePassword,
            onToggleObscurePassword: onToggleObscurePassword,
          ),
          if (endpointUri != null) ...[
            const SizedBox(height: 12),
            ResolvedPathPreview(
              label: localizations.resolvedEndpointLabel,
              value: endpointUri.toString(),
            ),
          ],
          const SizedBox(height: 12),
          WipeStorageButton(
            buttonKey: const ValueKey('settings_wipe_remote_button'),
            label: localizations.actionWipeRemoteFile,
            onPressed: onWipeRemoteFile,
          ),
        ],
      ),
    );
  }
}

/// Validated text form field for the WebDAV server URL.
class _WebDavServerUrlField extends StatelessWidget {
  /// Creates a [_WebDavServerUrlField].
  const _WebDavServerUrlField({required this.controller});

  /// Controller for the server URL input.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ClearableTextField(
      useFormField: true,
      controller: controller,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: localizations.serverUrlLabel,
        hintText: 'https://cloud.example.com',
        prefixIcon: const Icon(Icons.dns_outlined),
        border: const OutlineInputBorder(),
      ),
      validator: (value) => (value == null || value.trim().isEmpty)
          ? localizations.serverUrlErrorEmpty
          : null,
    );
  }
}

/// Validated text form field for the WebDAV username.
class _WebDavUsernameField extends StatelessWidget {
  /// Creates a [_WebDavUsernameField].
  const _WebDavUsernameField({required this.controller});

  /// Controller for the username input.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ClearableTextField(
      useFormField: true,
      controller: controller,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: localizations.usernameLabel,
        hintText: 'example-user',
        prefixIcon: const Icon(Icons.person_outline_rounded),
        border: const OutlineInputBorder(),
      ),
      validator: (value) => (value == null || value.trim().isEmpty)
          ? localizations.usernameErrorEmpty
          : null,
    );
  }
}
