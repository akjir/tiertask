#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Completed background location payload queued for UI-thread delivery.
  struct CompletedLocationResult {
    uint64_t request_id;
    flutter::EncodableMap payload;
  };

  // Thread-safe dispatch state shared between FlutterWindow and location
  // worker threads so workers never dereference |this| or a destroyed HWND.
  struct LocationDispatchState {
    std::shared_ptr<std::atomic<bool>> alive =
        std::make_shared<std::atomic<bool>>(true);
    std::mutex mutex;
    HWND hwnd = nullptr;
    std::vector<CompletedLocationResult> completed_results;
  };

  // Invalidates background location dispatch and clears pending requests.
  void ClearPendingLocationState();

  // Delivers completed background location results on the Win32 UI thread.
  void DrainPendingLocationResults();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel for querying the compile-time application version and build metadata.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      app_version_channel_;

  // Channel for opening native Windows file and folder selection dialogs.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      directory_picker_channel_;

  // Channel for launching task link URIs via ShellExecuteW.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      link_launcher_channel_;

  // Channel for querying the Windows Location API.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      location_channel_;

  // Channel for custom desktop window drag, maximize, and close commands.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_controls_channel_;

  // Shared dispatch state for marshalling background location queries to UI.
  std::shared_ptr<LocationDispatchState> location_dispatch_state_;

  // Monotonically increasing identifier for in-flight location requests.
  uint64_t next_location_request_id_ = 1;

  // Pending Flutter method results awaiting background location completion.
  std::unordered_map<
      uint64_t,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
      pending_location_requests_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
