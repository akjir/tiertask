#include "flutter_window.h"

#include <shobjidl.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return std::wstring();
  }
  int target_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
      static_cast<int>(utf8_string.length()), nullptr, 0);
  if (target_length <= 0) {
    return std::wstring();
  }
  std::wstring utf16_string(target_length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
                      static_cast<int>(utf8_string.length()),
                      &utf16_string[0], target_length);
  return utf16_string;
}

std::optional<std::string> PickFolderDialog(
    HWND owner_window, const std::string& initial_directory) {
  IFileOpenDialog* file_dialog = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&file_dialog));
  if (FAILED(hr) || file_dialog == nullptr) {
    return std::nullopt;
  }

  DWORD options = 0;
  if (SUCCEEDED(file_dialog->GetOptions(&options))) {
    file_dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                            FOS_PATHMUSTEXIST);
  }

  if (!initial_directory.empty()) {
    std::wstring wide_initial = Utf16FromUtf8(initial_directory);
    if (!wide_initial.empty()) {
      IShellItem* initial_folder = nullptr;
      if (SUCCEEDED(SHCreateItemFromParsingName(
              wide_initial.c_str(), nullptr, IID_PPV_ARGS(&initial_folder))) &&
          initial_folder != nullptr) {
        file_dialog->SetFolder(initial_folder);
        initial_folder->Release();
      }
    }
  }

  std::optional<std::string> selected_path = std::nullopt;
  hr = file_dialog->Show(owner_window);
  if (SUCCEEDED(hr)) {
    IShellItem* item = nullptr;
    if (SUCCEEDED(file_dialog->GetResult(&item)) && item != nullptr) {
      PWSTR psz_file_path = nullptr;
      if (SUCCEEDED(
              item->GetDisplayName(SIGDN_FILESYSPATH, &psz_file_path)) &&
          psz_file_path != nullptr) {
        selected_path = Utf8FromUtf16(psz_file_path);
        CoTaskMemFree(psz_file_path);
      }
      item->Release();
    }
  }

  file_dialog->Release();
  return selected_path;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  directory_picker_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "de.akjir.tiertask/directory_picker",
          &flutter::StandardMethodCodec::GetInstance());
  directory_picker_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "pickDirectory") {
          result->NotImplemented();
          return;
        }
        std::string initial_directory;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto it =
              arguments->find(flutter::EncodableValue("initialDirectory"));
          if (it != arguments->end()) {
            if (const auto* dir_str = std::get_if<std::string>(&it->second)) {
              initial_directory = *dir_str;
            }
          }
        }
        auto picked = PickFolderDialog(GetHandle(), initial_directory);
        if (picked.has_value()) {
          result->Success(flutter::EncodableValue(picked.value()));
        } else {
          result->Success(flutter::EncodableValue());
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  directory_picker_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
