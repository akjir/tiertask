#include "flutter_window.h"

#include <roapi.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <windows.devices.geolocation.h>
#include <windows.foundation.h>
#include <wlanapi.h>
#include <wrl/client.h>
#include <wrl/wrappers/corewrappers.h>

#include <cstdio>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "generated_version.h"
#include "utils.h"

namespace {

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

flutter::EncodableMap BuildUnavailableWithWifiMap() {
  flutter::EncodableMap map{
      {flutter::EncodableValue("status"),
       flutter::EncodableValue("unavailable")},
  };
  flutter::EncodableList wifi_aps = QueryWindowsWifiAccessPoints();
  if (!wifi_aps.empty()) {
    map[flutter::EncodableValue("wifiAccessPoints")] =
        flutter::EncodableValue(wifi_aps);
  }
  return map;
}

flutter::EncodableMap QueryWindowsLocation() {
  Microsoft::WRL::Wrappers::HStringReference class_id(
      RuntimeClass_Windows_Devices_Geolocation_Geolocator);
  Microsoft::WRL::ComPtr<IInspectable> inspectable;
  HRESULT hr = RoActivateInstance(class_id.Get(), &inspectable);
  if (FAILED(hr) || !inspectable) {
    return BuildUnavailableWithWifiMap();
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeolocator>
      geolocator;
  hr = inspectable.As(&geolocator);
  if (FAILED(hr) || !geolocator) {
    return BuildUnavailableWithWifiMap();
  }

  geolocator->put_DesiredAccuracy(
      ABI::Windows::Devices::Geolocation::PositionAccuracy_High);

  ABI::Windows::Devices::Geolocation::PositionStatus status =
      ABI::Windows::Devices::Geolocation::PositionStatus_NotAvailable;
  if (SUCCEEDED(geolocator->get_LocationStatus(&status)) &&
      (status == ABI::Windows::Devices::Geolocation::PositionStatus_Disabled ||
       status ==
           ABI::Windows::Devices::Geolocation::PositionStatus_NotAvailable)) {
    return BuildUnavailableWithWifiMap();
  }

  ABI::Windows::Foundation::TimeSpan maximum_age{5LL * 60 * 10000000};
  ABI::Windows::Foundation::TimeSpan timeout{600LL * 10000};
  Microsoft::WRL::ComPtr<ABI::Windows::Foundation::IAsyncOperation<
      ABI::Windows::Devices::Geolocation::Geoposition*>>
      async_op;
  hr = geolocator->GetGeopositionAsyncWithAgeAndTimeout(maximum_age, timeout,
                                                        &async_op);
  if (FAILED(hr) || !async_op) {
    return BuildUnavailableWithWifiMap();
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Foundation::IAsyncInfo> async_info;
  hr = async_op.As(&async_info);
  if (FAILED(hr) || !async_info) {
    return BuildUnavailableWithWifiMap();
  }

  ABI::Windows::Foundation::AsyncStatus async_status =
      ABI::Windows::Foundation::AsyncStatus::Started;
  for (int attempt = 0; attempt < 5; ++attempt) {
    hr = async_info->get_Status(&async_status);
    if (FAILED(hr) ||
        async_status != ABI::Windows::Foundation::AsyncStatus::Started) {
      break;
    }
    Sleep(120);
  }
  if (async_status != ABI::Windows::Foundation::AsyncStatus::Completed) {
    async_info->Cancel();
    return BuildUnavailableWithWifiMap();
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeoposition>
      geoposition;
  hr = async_op->GetResults(&geoposition);
  if (FAILED(hr) || !geoposition) {
    return BuildUnavailableWithWifiMap();
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeocoordinate>
      coordinate;
  hr = geoposition->get_Coordinate(&coordinate);
  if (FAILED(hr) || !coordinate) {
    return BuildUnavailableWithWifiMap();
  }

  Microsoft::WRL::ComPtr<
      ABI::Windows::Devices::Geolocation::IGeocoordinateWithPoint>
      coordinate_with_point;
  hr = coordinate.As(&coordinate_with_point);
  if (FAILED(hr) || !coordinate_with_point) {
    return BuildUnavailableWithWifiMap();
  }

  Microsoft::WRL::ComPtr<ABI::Windows::Devices::Geolocation::IGeopoint>
      geopoint;
  hr = coordinate_with_point->get_Point(&geopoint);
  if (FAILED(hr) || !geopoint) {
    return BuildUnavailableWithWifiMap();
  }

  ABI::Windows::Devices::Geolocation::BasicGeoposition position{};
  if (FAILED(geopoint->get_Position(&position))) {
    return BuildUnavailableWithWifiMap();
  }

  DOUBLE error_radius = 0.0;
  if (SUCCEEDED(coordinate->get_Accuracy(&error_radius)) &&
      error_radius > 5000.0) {
    return BuildUnavailableWithWifiMap();
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
        if (uri.empty()) {
          result->Error("INVALID_URI", "URI is empty.");
          return;
        }
        int wide_len = MultiByteToWideChar(CP_UTF8, 0, uri.c_str(), -1,
                                           nullptr, 0);
        if (wide_len <= 0) {
          result->Error("INVALID_URI", "Failed to convert URI to UTF-16.");
          return;
        }
        std::wstring wide_uri(static_cast<size_t>(wide_len), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, uri.c_str(), -1, &wide_uri[0],
                            wide_len);
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
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "getLocation") {
          result->Success(flutter::EncodableValue(QueryWindowsLocation()));
        } else {
          result->NotImplemented();
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
  app_version_channel_ = nullptr;
  directory_picker_channel_ = nullptr;
  link_launcher_channel_ = nullptr;
  location_channel_ = nullptr;
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
