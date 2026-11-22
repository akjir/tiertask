#include "win32_window.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include <algorithm>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr UINT_PTR kChildContentSubclassId = 1;

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);
using GetSystemMetricsForDpiFn = int __stdcall(int index, UINT dpi);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Returns the active monitor DPI for |hwnd|, falling back to 96 DPI.
UINT GetDpiForWindowSafe(HWND hwnd) {
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr) {
    return 96;
  }
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  return dpi > 0 ? dpi : 96;
}

// Queries a DPI-aware Win32 system metric, falling back to scaled GetSystemMetrics.
int GetSystemMetricsForDpiSafe(int index, UINT dpi) {
  static const auto get_metrics_for_dpi = []() -> GetSystemMetricsForDpiFn* {
    HMODULE user32_module = GetModuleHandleA("User32.dll");
    if (user32_module == nullptr) {
      return nullptr;
    }
    return reinterpret_cast<GetSystemMetricsForDpiFn*>(
        GetProcAddress(user32_module, "GetSystemMetricsForDpi"));
  }();
  if (get_metrics_for_dpi != nullptr) {
    return get_metrics_for_dpi(index, dpi);
  }
  return Scale(GetSystemMetrics(index), dpi / 96.0);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  // Remove the native title bar while preserving DWM shadow, Windows 11 rounded
  // corners, Aero Snap, and invisible resize handles.
  MARGINS margins = {0, 0, 1, 0};
  DwmExtendFrameIntoClientArea(window, &margins);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCCALCSIZE: {
      if (wparam != 0) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const LONG original_top = params->rgrc[0].top;
        const LRESULT result = DefWindowProc(hwnd, message, wparam, lparam);
        if (result != 0) {
          return result;
        }
        params->rgrc[0].top = original_top;
        if (IsZoomed(hwnd)) {
          const UINT dpi = GetDpiForWindowSafe(hwnd);
          const int top_inset =
              GetSystemMetricsForDpiSafe(SM_CYFRAME, dpi) +
              GetSystemMetricsForDpiSafe(SM_CXPADDEDBORDER, dpi);
          params->rgrc[0].top += top_inset;
        }
        return 0;
      }
      break;
    }

    case WM_NCHITTEST: {
      const LRESULT default_hit = DefWindowProc(hwnd, message, wparam, lparam);
      if (default_hit != HTCLIENT) {
        return default_hit;
      }
      if (!IsZoomed(hwnd)) {
        POINT cursor_pos = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ScreenToClient(hwnd, &cursor_pos);
        const int top_border = GetTopResizeBorderHeight();
        if (cursor_pos.y >= 0 && cursor_pos.y < top_border) {
          RECT client_rect = GetClientArea();
          const int corner_width = top_border * 2;
          if (cursor_pos.x < corner_width) {
            return HTTOPLEFT;
          }
          if (cursor_pos.x >= client_rect.right - corner_width) {
            return HTTOPRIGHT;
          }
          return HTTOP;
        }
      }
      return HTCLIENT;
    }

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void Win32Window::Destroy() {
  if (child_content_ != nullptr) {
    if (IsWindow(child_content_)) {
      RemoveWindowSubclass(child_content_, ChildContentSubclassProc,
                           kChildContentSubclassId);
    }
    child_content_ = nullptr;
  }

  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

// static
LRESULT CALLBACK Win32Window::ChildContentSubclassProc(HWND hwnd,
                                                       UINT message,
                                                       WPARAM wparam,
                                                       LPARAM lparam,
                                                       UINT_PTR subclass_id,
                                                       DWORD_PTR ref_data) {
  if (message == WM_NCHITTEST) {
    auto* self = reinterpret_cast<Win32Window*>(ref_data);
    if (self != nullptr && self->window_handle_ != nullptr &&
        !IsZoomed(self->window_handle_)) {
      POINT cursor_pos = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(self->window_handle_, &cursor_pos);
      const int top_border = self->GetTopResizeBorderHeight();
      if (cursor_pos.y >= 0 && cursor_pos.y < top_border) {
        return HTTRANSPARENT;
      }
    }
  } else if (message == WM_NCDESTROY) {
    auto* self = reinterpret_cast<Win32Window*>(ref_data);
    if (self != nullptr && self->child_content_ == hwnd) {
      self->child_content_ = nullptr;
    }
    RemoveWindowSubclass(hwnd, ChildContentSubclassProc, subclass_id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

int Win32Window::GetTopResizeBorderHeight() const {
  const UINT dpi =
      window_handle_ != nullptr ? GetDpiForWindowSafe(window_handle_) : 96;
  return std::max(4, Scale(5, dpi / 96.0));
}

void Win32Window::SetChildContent(HWND content) {
  if (child_content_ != nullptr && IsWindow(child_content_)) {
    RemoveWindowSubclass(child_content_, ChildContentSubclassProc,
                         kChildContentSubclassId);
  }
  child_content_ = content;
  SetParent(content, window_handle_);
  SetWindowSubclass(content, ChildContentSubclassProc, kChildContentSubclassId,
                    reinterpret_cast<DWORD_PTR>(this));
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
