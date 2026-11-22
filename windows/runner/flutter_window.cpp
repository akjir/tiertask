#include "flutter_window.h"

#include <roapi.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <windows.devices.geolocation.h>
#include <windows.foundation.h>
#include <wlanapi.h>
#include <wrl/client.h>
#include <wrl/wrappers/corewrappers.h>

#include <cstdint>
#include <cstdio>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "generated_version.h"
#include "utils.h"

namespace {

constexpr UINT kWmLocationResult = WM_APP + 1;

constexpr std::string_view kBlockedUriSchemes[] = {
    "javascript",      "vbscript",   "jscript",         "livescript",
    "data",            "blob",       "about",           "view-source",
    "file",            "smb",        "cifs",            "nfs",
    "jar",             "shell",      "cmd",             "powershell",
    "wscript",         "cscript",    "ms-msdt",         "search-ms",
    "ms-appinstaller", "mhtml",      "its",             "mk",
    "hcp",             "res",        "intent",          "content",
};

// RAII guard for WinRT apartment initialization on background worker threads.
class ScopedWinRtApartment {
 public:
  explicit ScopedWinRtApartment(RO_INIT_TYPE init_type)
      : hr_(RoInitialize(init_type)) {}

  ~ScopedWinRtApartment() {
    if (SUCCEEDED(hr_)) {
      RoUninitialize();
    }
  }

  ScopedWinRtApartment(const ScopedWinRtApartment&) = delete;
  ScopedWinRtApartment& operator=(const ScopedWinRtApartment&) = delete;

  bool initialized() const { return SUCCEEDED(hr_); }

 private:
  HRESULT hr_;
};

// RAII guard releasing COM task-memory strings allocated by shell APIs.
class ScopedCoTaskMemString {
 public:
  ScopedCoTaskMemString() = default;
  ~ScopedCoTaskMemString() { reset(); }

  ScopedCoTaskMemString(const ScopedCoTaskMemString&) = delete;
  ScopedCoTaskMemString& operator=(const ScopedCoTaskMemString&) = delete;

  PWSTR* put() {
    reset();
    return &ptr_;
  }

  PWSTR get() const { return ptr_; }

  void reset() {
    if (ptr_ != nullptr) {
      CoTaskMemFree(ptr_);
      ptr_ = nullptr;
    }
  }

 private:
  PWSTR ptr_ = nullptr;
};

bool IsAsciiAlpha(wchar_t ch) {
  return (ch >= L'A' && ch <= L'Z') || (ch >= L'a' && ch <= L'z');
}

bool IsAsciiSchemeContinue(wchar_t ch) {
  return IsAsciiAlpha(ch) || (ch >= L'0' && ch <= L'9') || ch == L'+' ||
         ch == L'-' || ch == L'.';
}

bool IsWhitespaceCodeUnit(wchar_t ch) {
  const uint16_t code_unit = static_cast<uint16_t>(ch);
  return code_unit == 0x0020 ||
         (code_unit >= 0x0009 && code_unit <= 0x000D) || code_unit == 0x0085 ||
         code_unit == 0x00A0 || code_unit == 0x1680 ||
         (code_unit >= 0x2000 && code_unit <= 0x200A) || code_unit == 0x2028 ||
         code_unit == 0x2029 || code_unit == 0x202F || code_unit == 0x205F ||
         code_unit == 0x3000 || code_unit == 0xFEFF;
}

bool IsDisallowedUriCodeUnit(wchar_t ch) {
  const uint16_t code_unit = static_cast<uint16_t>(ch);
  if (ch == L'\\') {
    return true;
  }
  if (code_unit <= 0x001F || code_unit == 0x007F) {
    return true;
  }
  if (code_unit >= 0x0080 && code_unit <= 0x009F) {
    return true;
  }
  if (code_unit == 0x061C || code_unit == 0x200E || code_unit == 0x200F ||
      code_unit == 0x2028 || code_unit == 0x2029 ||
      (code_unit >= 0x202A && code_unit <= 0x202E) ||
      (code_unit >= 0x2066 && code_unit <= 0x2069)) {
    return true;
  }
  return false;
}

bool IsBlockedUriScheme(std::string_view scheme) {
  for (const std::string_view blocked : kBlockedUriSchemes) {
    if (scheme == blocked) {
      return true;
    }
  }
  return false;
}

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty() ||
      utf8_string.size() >
          static_cast<size_t>(std::numeric_limits<int>::max())) {
    return std::wstring();
  }
  const int input_length = static_cast<int>(utf8_string.size());
  const int target_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(), input_length, nullptr,
      0);
  if (target_length <= 0) {
    return std::wstring();
  }
  std::wstring utf16_string(static_cast<size_t>(target_length), L'\0');
  const int converted_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(), input_length,
      utf16_string.data(), target_length);
  if (converted_length != target_length) {
    return std::wstring();
  }
  return utf16_string;
}

// Validates a launch URI against RFC 3986 scheme syntax, character safety
// rules, and the blocked-scheme policy before converting it to UTF-16.
bool ValidateAndConvertLaunchUri(const std::string& uri,
                                 std::wstring* wide_uri_out,
                                 const char** error_message_out) {
  if (uri.empty()) {
    *error_message_out = "URI is empty.";
    return false;
  }
  std::wstring wide_uri = Utf16FromUtf8(uri);
  if (wide_uri.empty()) {
    *error_message_out = "Failed to convert URI to UTF-16.";
    return false;
  }
  if (IsWhitespaceCodeUnit(wide_uri.front()) ||
      IsWhitespaceCodeUnit(wide_uri.back())) {
    *error_message_out = "URI must not have leading or trailing whitespace.";
    return false;
  }
  for (const wchar_t unit : wide_uri) {
    if (IsDisallowedUriCodeUnit(unit)) {
      *error_message_out = "URI contains disallowed characters.";
      return false;
    }
  }

  const size_t colon_pos = wide_uri.find(L':');
  if (colon_pos == std::wstring::npos || colon_pos < 2 ||
      colon_pos + 1 >= wide_uri.size()) {
    *error_message_out =
        "URI must have a scheme of at least two characters and a non-empty "
        "body.";
    return false;
  }
  if (!IsAsciiAlpha(wide_uri[0])) {
    *error_message_out = "URI scheme must start with an ASCII letter.";
    return false;
  }

  std::string scheme;
  scheme.reserve(colon_pos);
  for (size_t i = 0; i < colon_pos; ++i) {
    const wchar_t scheme_unit = wide_uri[i];
    if (i > 0 && !IsAsciiSchemeContinue(scheme_unit)) {
      *error_message_out = "URI scheme contains invalid characters.";
      return false;
    }
    char ascii_char = static_cast<char>(scheme_unit);
    if (ascii_char >= 'A' && ascii_char <= 'Z') {
      ascii_char = static_cast<char>(ascii_char - 'A' + 'a');
    }
    scheme.push_back(ascii_char);
  }
  if (IsBlockedUriScheme(scheme)) {
    *error_message_out = "URI scheme is not permitted.";
    return false;
  }

  *wide_uri_out = std::move(wide_uri);
  return true;
}

flutter::EncodableList QueryWindowsWifiAccessPoints() {
  flutter::EncodableList ap_list;
  HANDLE client_handle = nullptr;
  DWORD negotiated_version = 0;
  if (WlanOpenHandle(2, nullptr, &negotiated_version, &client_handle) !=
          ERROR_SUCCESS ||
      client_handle == nullptr) {
    return ap_list;
  }

  PWLAN_INTERFACE_INFO_LIST interface_list = nullptr;
  if (WlanEnumInterfaces(client_handle, nullptr, &interface_list) ==
          ERROR_SUCCESS &&
      interface_list != nullptr) {
    for (DWORD i = 0;
         i < interface_list->dwNumberOfItems && ap_list.size() < 20; ++i) {
      PWLAN_BSS_LIST bss_list = nullptr;
      if (WlanGetNetworkBssList(client_handle,
                                &interface_list->InterfaceInfo[i].InterfaceGuid,
                                nullptr, dot11_BSS_type_any, FALSE, nullptr,
                                &bss_list) == ERROR_SUCCESS &&
          bss_list != nullptr) {
        for (DWORD j = 0;
             j < bss_list->dwNumberOfItems && ap_list.size() < 20; ++j) {
          const WLAN_BSS_ENTRY& entry = bss_list->wlanBssEntries[j];
          char mac_buf[20];
          std::snprintf(mac_buf, sizeof(mac_buf),
                        "%02x:%02x:%02x:%02x:%02x:%02x", entry.dot11Bssid[0],
                        entry.dot11Bssid[1], entry.dot11Bssid[2],
                        entry.dot11Bssid[3], entry.dot11Bssid[4],
                        entry.dot11Bssid[5]);
          flutter::EncodableMap ap_map{
              {flutter::EncodableValue("macAddress"),
               flutter::EncodableValue(std::string(mac_buf))},
              {flutter::EncodableValue("signalStrength"),
               flutter::EncodableValue(static_cast<int64_t>(entry.lRssi))},
          };
          ap_list.push_back(flutter::EncodableValue(ap_map));
        }
        WlanFreeMemory(bss_list);
      }
    }
    WlanFreeMemory(interface_list);
  }

  WlanCloseHandle(client_handle, nullptr);
  return ap_list;
}

flutter::EncodableMap BuildUnavailableLocationMap() {
  return {
      {flutter::EncodableValue("status"),
       flutter::EncodableValue("unavailable")},
  };
}

flutter::EncodableMap BuildUnavailableWithWifiMap(
    const std::atomic<bool>& alive) {
  flutter::EncodableMap map = BuildUnavailableLocationMap();
  if (!alive.load(std::memory_order_acquire)) {
    return map;
  }
  flutter::EncodableList wifi_aps = QueryWindowsWifiAccessPoints();
  if (!wifi_aps.empty()) {
    map[flutter::EncodableValue("wifiAccessPoints")] =
        flutter::EncodableValue(std::move(wifi_aps));
  }
  return map;
}

flutter::EncodableMap QueryWindowsLocation(const std::atomic<bool>& alive) {
  if (!alive.load(std::memory_order_acquire)) {
    return BuildUnavailableLocationMap();
  }

  Microsoft::WRL::Wrappers::HStringReference class_id(
      RuntimeClass_Windows_Devices_Geolocation_Geolocator);
  Microsoft::WRL::ComPtr<IInspectable> inspectable;
  HRESULT hr = RoActivateInstance(class_id.Get(), &inspectable);
  if (FAILED(hr) || !inspectable) {
    return BuildUnavailableWithWifiMap(alive);
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeolocator>
      geolocator;
  hr = inspectable.As(&geolocator);
  if (FAILED(hr) || !geolocator) {
    return BuildUnavailableWithWifiMap(alive);
  }

  geolocator->put_DesiredAccuracy(
      ABI::Windows::Devices::Geolocation::PositionAccuracy_High);

  ABI::Windows::Devices::Geolocation::PositionStatus status =
      ABI::Windows::Devices::Geolocation::PositionStatus_NotAvailable;
  if (SUCCEEDED(geolocator->get_LocationStatus(&status)) &&
      (status == ABI::Windows::Devices::Geolocation::PositionStatus_Disabled ||
       status ==
           ABI::Windows::Devices::Geolocation::PositionStatus_NotAvailable)) {
    return BuildUnavailableWithWifiMap(alive);
  }

  ABI::Windows::Foundation::TimeSpan maximum_age{5LL * 60 * 10000000};
  ABI::Windows::Foundation::TimeSpan timeout{600LL * 10000};
  Microsoft::WRL::ComPtr<ABI::Windows::Foundation::IAsyncOperation<
      ABI::Windows::Devices::Geolocation::Geoposition*>>
      async_op;
  hr = geolocator->GetGeopositionAsyncWithAgeAndTimeout(maximum_age, timeout,
                                                        &async_op);
  if (FAILED(hr) || !async_op) {
    return BuildUnavailableWithWifiMap(alive);
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Foundation::IAsyncInfo> async_info;
  hr = async_op.As(&async_info);
  if (FAILED(hr) || !async_info) {
    return BuildUnavailableWithWifiMap(alive);
  }

  ABI::Windows::Foundation::AsyncStatus async_status =
      ABI::Windows::Foundation::AsyncStatus::Started;
  for (int attempt = 0; attempt < 5; ++attempt) {
    if (!alive.load(std::memory_order_acquire)) {
      async_info->Cancel();
      return BuildUnavailableLocationMap();
    }
    hr = async_info->get_Status(&async_status);
    if (FAILED(hr) ||
        async_status != ABI::Windows::Foundation::AsyncStatus::Started) {
      break;
    }
    Sleep(120);
  }
  if (async_status != ABI::Windows::Foundation::AsyncStatus::Completed) {
    async_info->Cancel();
    return BuildUnavailableWithWifiMap(alive);
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeoposition>
      geoposition;
  hr = async_op->GetResults(&geoposition);
  if (FAILED(hr) || !geoposition) {
    return BuildUnavailableWithWifiMap(alive);
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeocoordinate>
      coordinate;
  hr = geoposition->get_Coordinate(&coordinate);
  if (FAILED(hr) || !coordinate) {
    return BuildUnavailableWithWifiMap(alive);
  }

  Microsoft::WRL::ComPtr<
      ABI::Windows::Devices::Geolocation::IGeocoordinateWithPoint>
      coordinate_with_point;
  hr = coordinate.As(&coordinate_with_point);
  if (FAILED(hr) || !coordinate_with_point) {
    return BuildUnavailableWithWifiMap(alive);
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeopoint>
      geopoint;
  hr = coordinate_with_point->get_Point(&geopoint);
  if (FAILED(hr) || !geopoint) {
    return BuildUnavailableWithWifiMap(alive);
  }

  ABI::Windows::Devices::Geolocation::BasicGeoposition position{};
  if (FAILED(geopoint->get_Position(&position))) {
    return BuildUnavailableWithWifiMap(alive);
  }

  DOUBLE error_radius = 0.0;
  if (SUCCEEDED(coordinate->get_Accuracy(&error_radius)) &&
      error_radius > 5000.0) {
    return BuildUnavailableWithWifiMap(alive);
  }

  const char* source =
      (error_radius > 0.0 && error_radius <= 50.0) ? "gps" : "system";
  return {
      {flutter::EncodableValue("status"), flutter::EncodableValue("found")},
      {flutter::EncodableValue("latitude"),
       flutter::EncodableValue(position.Latitude)},
      {flutter::EncodableValue("longitude"),
       flutter::EncodableValue(position.Longitude)},
      {flutter::EncodableValue("source"), flutter::EncodableValue(source)},
  };
}

void ApplyInitialFolder(IFileDialog* file_dialog,
                        const std::string& initial_directory) {
  if (file_dialog == nullptr || initial_directory.empty()) {
    return;
  }
  const std::wstring wide_initial = Utf16FromUtf8(initial_directory);
  if (wide_initial.empty()) {
    return;
  }
  Microsoft::WRL::ComPtr<IShellItem> initial_folder;
  if (SUCCEEDED(SHCreateItemFromParsingName(
          wide_initial.c_str(), nullptr,
          IID_PPV_ARGS(initial_folder.GetAddressOf()))) &&
      initial_folder) {
    file_dialog->SetFolder(initial_folder.Get());
  }
}

std::optional<std::string> ShowDialogAndGetPath(IFileDialog* file_dialog,
                                                HWND owner_window) {
  if (file_dialog == nullptr) {
    return std::nullopt;
  }
  if (FAILED(file_dialog->Show(owner_window))) {
    return std::nullopt;
  }
  Microsoft::WRL::ComPtr<IShellItem> item;
  if (FAILED(file_dialog->GetResult(item.GetAddressOf())) || !item) {
    return std::nullopt;
  }
  ScopedCoTaskMemString file_path;
  if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, file_path.put())) ||
      file_path.get() == nullptr) {
    return std::nullopt;
  }
  return Utf8FromUtf16(file_path.get());
}

std::optional<std::string> PickFolderDialog(
    HWND owner_window, const std::string& initial_directory) {
  Microsoft::WRL::ComPtr<IFileOpenDialog> file_dialog;
  const HRESULT hr = CoCreateInstance(
      CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(file_dialog.GetAddressOf()));
  if (FAILED(hr) || !file_dialog) {
    return std::nullopt;
  }

  DWORD options = 0;
  if (SUCCEEDED(file_dialog->GetOptions(&options))) {
    file_dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                            FOS_PATHMUSTEXIST);
  }
  file_dialog->SetTitle(L"Select Directory");

  ApplyInitialFolder(file_dialog.Get(), initial_directory);
  return ShowDialogAndGetPath(file_dialog.Get(), owner_window);
}

std::optional<std::string> PickFileDialog(
    HWND owner_window,
    const std::string& initial_directory,
    const std::string& current_file_name) {
  Microsoft::WRL::ComPtr<IFileSaveDialog> file_dialog;
  const HRESULT hr = CoCreateInstance(
      CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(file_dialog.GetAddressOf()));
  if (FAILED(hr) || !file_dialog) {
    return std::nullopt;
  }

  DWORD options = 0;
  if (SUCCEEDED(file_dialog->GetOptions(&options))) {
    options &= ~static_cast<DWORD>(FOS_OVERWRITEPROMPT | FOS_CREATEPROMPT |
                                   FOS_FILEMUSTEXIST);
    file_dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
  }
  file_dialog->SetTitle(L"Select or Create TDF File");
  file_dialog->SetOkButtonLabel(L"Select");

  const COMDLG_FILTERSPEC filter_specs[] = {
      {L"TDF Files (*.tdf)", L"*.tdf"},
      {L"All Files (*.*)", L"*.*"},
  };
  file_dialog->SetFileTypes(2, filter_specs);
  file_dialog->SetDefaultExtension(L"tdf");

  ApplyInitialFolder(file_dialog.Get(), initial_directory);

  if (!current_file_name.empty()) {
    const std::wstring wide_name = Utf16FromUtf8(current_file_name);
    if (!wide_name.empty()) {
      file_dialog->SetFileName(wide_name.c_str());
    }
  }

  return ShowDialogAndGetPath(file_dialog.Get(), owner_window);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  ClearPendingLocationState();
}

void FlutterWindow::ClearPendingLocationState() {
  if (location_dispatch_state_) {
    location_dispatch_state_->alive->store(false, std::memory_order_release);
    {
      std::lock_guard<std::mutex> lock(location_dispatch_state_->mutex);
      location_dispatch_state_->hwnd = nullptr;
      location_dispatch_state_->completed_results.clear();
    }
    location_dispatch_state_.reset();
  }
  auto pending = std::move(pending_location_requests_);
  pending_location_requests_.clear();
  for (auto& entry : pending) {
    if (entry.second) {
      entry.second->Error("WINDOW_DESTROYED",
                          "Window destroyed before location query completed.");
    }
  }
}

void FlutterWindow::DrainPendingLocationResults() {
  if (!location_dispatch_state_) {
    return;
  }
  std::vector<CompletedLocationResult> completed;
  {
    std::lock_guard<std::mutex> lock(location_dispatch_state_->mutex);
    completed.swap(location_dispatch_state_->completed_results);
  }
  for (auto& item : completed) {
    auto it = pending_location_requests_.find(item.request_id);
    if (it == pending_location_requests_.end()) {
      continue;
    }
    auto result = std::move(it->second);
    pending_location_requests_.erase(it);
    if (result) {
      result->Success(flutter::EncodableValue(std::move(item.payload)));
    }
  }
}

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

  location_dispatch_state_ = std::make_shared<LocationDispatchState>();
  location_dispatch_state_->hwnd = GetHandle();

  app_version_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "de.akjir.tiertask/app_version",
          &flutter::StandardMethodCodec::GetInstance());
  app_version_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "getAppVersion") {
          result->Success(flutter::EncodableValue(TIERTASK_FULL_VERSION));
        } else {
          result->NotImplemented();
        }
      });

  directory_picker_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "de.akjir.tiertask/directory_picker",
          &flutter::StandardMethodCodec::GetInstance());
  directory_picker_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        if (method != "pickDirectory" && method != "pickFile") {
          result->NotImplemented();
          return;
        }
        std::string initial_directory;
        std::string current_file_name;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto it =
              arguments->find(flutter::EncodableValue("initialDirectory"));
          if (it != arguments->end()) {
            if (const auto* dir_str = std::get_if<std::string>(&it->second)) {
              initial_directory = *dir_str;
            }
          }
          auto name_it =
              arguments->find(flutter::EncodableValue("currentFileName"));
          if (name_it != arguments->end()) {
            if (const auto* name_str =
                    std::get_if<std::string>(&name_it->second)) {
              current_file_name = *name_str;
            }
          }
        }
        auto picked = method == "pickFile"
                          ? PickFileDialog(GetHandle(), initial_directory,
                                           current_file_name)
                          : PickFolderDialog(GetHandle(), initial_directory);
        if (picked.has_value()) {
          result->Success(flutter::EncodableValue(picked.value()));
        } else {
          result->Success(flutter::EncodableValue());
        }
      });

  link_launcher_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "de.akjir.tiertask/link_launcher",
          &flutter::StandardMethodCodec::GetInstance());
  link_launcher_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "openLink") {
          result->NotImplemented();
          return;
        }
        std::string uri;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto it = arguments->find(flutter::EncodableValue("uri"));
          if (it != arguments->end()) {
            if (const auto* uri_str = std::get_if<std::string>(&it->second)) {
              uri = *uri_str;
            }
          }
        }
        std::wstring wide_uri;
        const char* validation_error = "Invalid URI.";
        if (!ValidateAndConvertLaunchUri(uri, &wide_uri, &validation_error)) {
          result->Error("INVALID_URI", validation_error);
          return;
        }
        HINSTANCE instance = ShellExecuteW(
            GetHandle(), L"open", wide_uri.c_str(), nullptr, nullptr,
            SW_SHOWNORMAL);
        if (reinterpret_cast<INT_PTR>(instance) > 32) {
          result->Success(flutter::EncodableValue(true));
        } else {
          result->Error("LAUNCH_FAILED", "Failed to open URI.");
        }
      });

  location_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "de.akjir.tiertask/location",
          &flutter::StandardMethodCodec::GetInstance());
  location_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "getLocation") {
          result->NotImplemented();
          return;
        }
        if (!location_dispatch_state_ || GetHandle() == nullptr) {
          result->Success(
              flutter::EncodableValue(BuildUnavailableLocationMap()));
          return;
        }
        const uint64_t request_id = next_location_request_id_++;
        pending_location_requests_.emplace(request_id, std::move(result));
        std::thread([dispatch_state = location_dispatch_state_,
                     alive_token = location_dispatch_state_->alive,
                     request_id]() {
          flutter::EncodableMap payload;
          if (alive_token->load(std::memory_order_acquire)) {
            ScopedWinRtApartment winrt_apartment(RO_INIT_MULTITHREADED);
            payload = winrt_apartment.initialized()
                          ? QueryWindowsLocation(*alive_token)
                          : BuildUnavailableWithWifiMap(*alive_token);
          }
          if (!alive_token->load(std::memory_order_acquire)) {
            return;
          }
          std::lock_guard<std::mutex> lock(dispatch_state->mutex);
          if (!alive_token->load(std::memory_order_acquire) ||
              dispatch_state->hwnd == nullptr) {
            return;
          }
          dispatch_state->completed_results.push_back(
              CompletedLocationResult{request_id, std::move(payload)});
          PostMessageW(dispatch_state->hwnd, kWmLocationResult, 0, 0);
        }).detach();
      });

  window_controls_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "de.akjir.tiertask/window_controls",
          &flutter::StandardMethodCodec::GetInstance());
  window_controls_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        HWND hwnd = GetHandle();
        if (method == "closeWindow") {
          if (hwnd != nullptr) {
            PostMessage(hwnd, WM_CLOSE, 0, 0);
          }
          result->Success(flutter::EncodableValue(hwnd != nullptr));
        } else if (method == "startDragging") {
          if (hwnd != nullptr) {
            const int primary_button =
                GetSystemMetrics(SM_SWAPBUTTON) != 0 ? VK_RBUTTON : VK_LBUTTON;
            if ((GetAsyncKeyState(primary_button) & 0x8000) != 0) {
              POINT cursor{};
              GetCursorPos(&cursor);
              result->Success(flutter::EncodableValue(true));
              ReleaseCapture();
              PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION,
                          MAKELPARAM(static_cast<WORD>(cursor.x),
                                     static_cast<WORD>(cursor.y)));
              return;
            }
          }
          result->Success(flutter::EncodableValue(false));
        } else if (method == "toggleMaximize") {
          if (hwnd != nullptr) {
            ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          }
          result->Success(flutter::EncodableValue(hwnd != nullptr));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ClearPendingLocationState();
  app_version_channel_ = nullptr;
  directory_picker_channel_ = nullptr;
  link_launcher_channel_ = nullptr;
  location_channel_ = nullptr;
  window_controls_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kWmLocationResult) {
    DrainPendingLocationResults();
    return 0;
  }

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
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
