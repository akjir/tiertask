#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

#include <cstring>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "generated_version.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* app_version_channel;
  FlMethodChannel* directory_picker_channel;
  FlMethodChannel* link_launcher_channel;
  FlMethodChannel* location_channel;
  FlMethodChannel* window_controls_channel;
  GtkFileChooserNative* active_file_dialog;
  FlMethodCall* active_file_dialog_call;
  gulong active_file_dialog_response_handler;
  GCancellable* location_cancellable;
  guint64 engine_generation;
  gboolean engine_active;
  GtkGesture* window_press_gesture;
  GtkGesture* window_drag_gesture;
  GtkEventController* window_motion_controller;
  GdkCursor* active_resize_cursor;
  GdkWindowEdge active_resize_edge;
  gboolean has_resize_cursor;
  GtkWindow* main_window;
  GdkDevice* last_button_press_device;
  gint last_button_press_x_root;
  gint last_button_press_y_root;
  guint32 last_button_press_time;
  gboolean has_last_button_press;
  gboolean primary_button_pressed;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Releases all registered Flutter method channel instances.
static void clear_method_channels(MyApplication* self) {
  g_clear_object(&self->app_version_channel);
  g_clear_object(&self->directory_picker_channel);
  g_clear_object(&self->link_launcher_channel);
  g_clear_object(&self->location_channel);
  g_clear_object(&self->window_controls_channel);
}

// Cancels and clears the cancellable shared by in-flight location queries.
static void cancel_pending_location_queries(MyApplication* self) {
  if (self->location_cancellable != nullptr) {
    g_cancellable_cancel(self->location_cancellable);
    g_clear_object(&self->location_cancellable);
  }
}

// Disconnects signals, destroys an open native chooser, and releases its call.
static void cleanup_active_file_dialog(MyApplication* self) {
  if (self->active_file_dialog != nullptr) {
    GtkNativeDialog* dialog = GTK_NATIVE_DIALOG(self->active_file_dialog);
    self->active_file_dialog = nullptr;
    if (self->active_file_dialog_response_handler != 0) {
      g_signal_handler_disconnect(dialog,
                                  self->active_file_dialog_response_handler);
      self->active_file_dialog_response_handler = 0;
    }
    gtk_native_dialog_destroy(dialog);
    g_object_unref(dialog);
  }
  g_clear_object(&self->active_file_dialog_call);
}

// Releases window-attached input controllers, cursor cache, and pointer state.
static void clear_window_input_controllers(MyApplication* self) {
  g_clear_object(&self->window_press_gesture);
  g_clear_object(&self->window_drag_gesture);
  g_clear_object(&self->window_motion_controller);
  g_clear_object(&self->active_resize_cursor);
  g_clear_object(&self->last_button_press_device);
  self->has_resize_cursor = FALSE;
  self->has_last_button_press = FALSE;
  self->primary_button_pressed = FALSE;
}

// Handles the asynchronous response from the native GTK file/folder chooser.
static void on_directory_dialog_response(GtkNativeDialog* dialog,
                                         gint response_id,
                                         gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->active_file_dialog != GTK_FILE_CHOOSER_NATIVE(dialog)) {
    return;
  }

  g_autoptr(FlMethodCall) method_call = self->active_file_dialog_call;
  self->active_file_dialog_call = nullptr;

  if (self->active_file_dialog_response_handler != 0) {
    g_signal_handler_disconnect(dialog,
                                self->active_file_dialog_response_handler);
    self->active_file_dialog_response_handler = 0;
  }
  self->active_file_dialog = nullptr;

  if (method_call != nullptr && self->engine_active) {
    g_autoptr(FlMethodResponse) response = nullptr;
    if (response_id == GTK_RESPONSE_ACCEPT) {
      g_autofree gchar* selected_path =
          gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
      if (selected_path != nullptr) {
        g_autoptr(FlValue) result = fl_value_new_string(selected_path);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      } else {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      }
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    fl_method_call_respond(method_call, response, nullptr);
  }

  gtk_native_dialog_destroy(dialog);
  g_object_unref(dialog);
}

// Handles method calls on the de.akjir.tiertask/directory_picker channel.
static void on_directory_picker_method_call(FlMethodChannel* channel,
                                            FlMethodCall* method_call,
                                            gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  const gboolean is_pick_directory = g_strcmp0(method, "pickDirectory") == 0;
  const gboolean is_pick_file = g_strcmp0(method, "pickFile") == 0;

  if (!is_pick_directory && !is_pick_file) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (self->active_file_dialog != nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new(
            "BUSY", "A file or directory dialog is already open.", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (self->main_window == nullptr || !self->engine_active) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new(
            "NO_WINDOW", "Main window is unavailable.", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      is_pick_file ? "Select or Create TDF File" : "Select Directory",
      self->main_window,
      is_pick_file ? GTK_FILE_CHOOSER_ACTION_SAVE
                   : GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER,
      is_pick_file ? "_Select" : "_Open", "_Cancel");

  if (is_pick_file) {
    gtk_file_chooser_set_do_overwrite_confirmation(GTK_FILE_CHOOSER(dialog),
                                                   FALSE);
    GtkFileFilter* tdf_filter = gtk_file_filter_new();
    gtk_file_filter_set_name(tdf_filter, "TDF Files (*.tdf)");
    gtk_file_filter_add_pattern(tdf_filter, "*.tdf");
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), tdf_filter);

    GtkFileFilter* all_filter = gtk_file_filter_new();
    gtk_file_filter_set_name(all_filter, "All Files");
    gtk_file_filter_add_pattern(all_filter, "*");
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), all_filter);
  }

  FlValue* args = fl_method_call_get_args(method_call);
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* initial_dir = fl_value_lookup_string(args, "initialDirectory");
    if (initial_dir != nullptr &&
        fl_value_get_type(initial_dir) == FL_VALUE_TYPE_STRING) {
      const gchar* dir_str = fl_value_get_string(initial_dir);
      if (dir_str != nullptr && dir_str[0] != '\0') {
        gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dialog), dir_str);
      }
    }
    if (is_pick_file) {
      FlValue* current_name = fl_value_lookup_string(args, "currentFileName");
      if (current_name != nullptr &&
          fl_value_get_type(current_name) == FL_VALUE_TYPE_STRING) {
        const gchar* name_str = fl_value_get_string(current_name);
        if (name_str != nullptr && name_str[0] != '\0') {
          gtk_file_chooser_set_current_name(GTK_FILE_CHOOSER(dialog), name_str);
        }
      }
    }
  }

  self->active_file_dialog = dialog;
  self->active_file_dialog_call = FL_METHOD_CALL(g_object_ref(method_call));
  self->active_file_dialog_response_handler = g_signal_connect(
      dialog, "response", G_CALLBACK(on_directory_dialog_response), self);
  gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog));
}

struct WifiAccessPoint {
  std::string mac_address;
  gint64 signal_strength;
};

struct LocationQueryResult {
  gboolean found = FALSE;
  gdouble latitude = 0.0;
  gdouble longitude = 0.0;
  std::vector<WifiAccessPoint> wifi_aps;
};

struct LocationTaskContext {
  GWeakRef app_ref;
  FlMethodCall* method_call = nullptr;
  guint64 engine_generation = 0;
};

static void destroy_location_query_result(gpointer data) {
  delete static_cast<LocationQueryResult*>(data);
}

static void destroy_location_task_context(gpointer data) {
  auto* context = static_cast<LocationTaskContext*>(data);
  if (context == nullptr) {
    return;
  }
  g_weak_ref_clear(&context->app_ref);
  g_clear_object(&context->method_call);
  delete context;
}

// Sleeps up to timeout_ms on the worker thread, waking early on cancellation.
static gboolean sleep_cancellable_ms(GCancellable* cancellable,
                                     gint timeout_ms) {
  if (cancellable == nullptr) {
    g_usleep(static_cast<gulong>(timeout_ms) * 1000UL);
    return TRUE;
  }
  if (g_cancellable_is_cancelled(cancellable)) {
    return FALSE;
  }
  GPollFD poll_fd;
  if (g_cancellable_make_pollfd(cancellable, &poll_fd)) {
    g_poll(&poll_fd, 1, timeout_ms);
    g_cancellable_release_fd(cancellable);
    return !g_cancellable_is_cancelled(cancellable);
  }
  g_usleep(static_cast<gulong>(timeout_ms) * 1000UL);
  return !g_cancellable_is_cancelled(cancellable);
}

// Reads a double property from a GeoClue2 Location D-Bus object.
static gboolean read_geoclue_double_property(GDBusConnection* bus,
                                             const gchar* object_path,
                                             const gchar* property_name,
                                             GCancellable* cancellable,
                                             gdouble* out_value) {
  GError* error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", object_path,
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", "org.freedesktop.GeoClue2.Location", property_name),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1500, cancellable, &error);
  if (reply == nullptr) {
    g_clear_error(&error);
    return FALSE;
  }
  g_autoptr(GVariant) boxed = nullptr;
  g_variant_get(reply, "(v)", &boxed);
  if (boxed == nullptr ||
      !g_variant_is_of_type(boxed, G_VARIANT_TYPE_DOUBLE)) {
    return FALSE;
  }
  *out_value = g_variant_get_double(boxed);
  return TRUE;
}

// Sets a property on a GeoClue2 Client D-Bus object (takes floating value ref).
static gboolean set_geoclue_client_property(GDBusConnection* bus,
                                            const gchar* client_path,
                                            const gchar* property_name,
                                            GVariant* value,
                                            GCancellable* cancellable) {
  GError* error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", client_path,
      "org.freedesktop.DBus.Properties", "Set",
      g_variant_new("(ssv)", "org.freedesktop.GeoClue2.Client", property_name,
                    value),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 1500, cancellable, &error);
  if (reply == nullptr) {
    g_clear_error(&error);
    return FALSE;
  }
  return TRUE;
}

// Deletes a GeoClue2 client on the Manager so system bus objects do not leak.
static void delete_geoclue_client(GDBusConnection* bus,
                                  const gchar* client_path) {
  GError* error = nullptr;
  g_autoptr(GVariant) delete_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager",
      "org.freedesktop.GeoClue2.Manager", "DeleteClient",
      g_variant_new("(o)", client_path), nullptr, G_DBUS_CALL_FLAGS_NONE, 1000,
      nullptr, &error);
  if (delete_reply == nullptr) {
    g_clear_error(&error);
  }
}

// Queries visible Wi-Fi AP BSSIDs and signal strengths via NetworkManager.
static void query_network_manager_wifi_aps(
    GDBusConnection* bus,
    GCancellable* cancellable,
    std::vector<WifiAccessPoint>* out_aps) {
  constexpr gsize kMaxWifiAccessPoints = 20;
  constexpr guint32 kNmDeviceTypeWifi = 2;

  GError* error = nullptr;
  g_autoptr(GVariant) dev_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
      "org.freedesktop.NetworkManager", "GetDevices", nullptr,
      G_VARIANT_TYPE("(ao)"), G_DBUS_CALL_FLAGS_NONE, 1500, cancellable,
      &error);
  if (dev_reply == nullptr) {
    g_clear_error(&error);
    return;
  }

  g_autoptr(GVariantIter) dev_iter = nullptr;
  g_variant_get(dev_reply, "(ao)", &dev_iter);
  const gchar* dev_path = nullptr;
  while (!g_cancellable_is_cancelled(cancellable) &&
         out_aps->size() < kMaxWifiAccessPoints &&
         g_variant_iter_loop(dev_iter, "&o", &dev_path)) {
    g_autoptr(GVariant) type_reply = g_dbus_connection_call_sync(
        bus, "org.freedesktop.NetworkManager", dev_path,
        "org.freedesktop.DBus.Properties", "Get",
        g_variant_new("(ss)", "org.freedesktop.NetworkManager.Device",
                      "DeviceType"),
        G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 500, cancellable,
        &error);
    if (type_reply == nullptr) {
      g_clear_error(&error);
      continue;
    }
    g_autoptr(GVariant) type_boxed = nullptr;
    g_variant_get(type_reply, "(v)", &type_boxed);
    if (type_boxed == nullptr ||
        !g_variant_is_of_type(type_boxed, G_VARIANT_TYPE_UINT32) ||
        g_variant_get_uint32(type_boxed) != kNmDeviceTypeWifi) {
      continue;
    }

    g_autoptr(GVariant) ap_reply = g_dbus_connection_call_sync(
        bus, "org.freedesktop.NetworkManager", dev_path,
        "org.freedesktop.NetworkManager.Device.Wireless", "GetAllAccessPoints",
        nullptr, G_VARIANT_TYPE("(ao)"), G_DBUS_CALL_FLAGS_NONE, 1000,
        cancellable, &error);
    if (ap_reply == nullptr) {
      g_clear_error(&error);
      continue;
    }

    g_autoptr(GVariantIter) ap_iter = nullptr;
    g_variant_get(ap_reply, "(ao)", &ap_iter);
    const gchar* ap_path = nullptr;
    while (!g_cancellable_is_cancelled(cancellable) &&
           out_aps->size() < kMaxWifiAccessPoints &&
           g_variant_iter_loop(ap_iter, "&o", &ap_path)) {
      g_autoptr(GVariant) props_reply = g_dbus_connection_call_sync(
          bus, "org.freedesktop.NetworkManager", ap_path,
          "org.freedesktop.DBus.Properties", "GetAll",
          g_variant_new("(s)", "org.freedesktop.NetworkManager.AccessPoint"),
          G_VARIANT_TYPE("(a{sv})"), G_DBUS_CALL_FLAGS_NONE, 500, cancellable,
          &error);
      if (props_reply == nullptr) {
        g_clear_error(&error);
        continue;
      }

      g_autoptr(GVariant) props_dict =
          g_variant_get_child_value(props_reply, 0);
      if (props_dict == nullptr) {
        continue;
      }

      g_autoptr(GVariant) hw_value = g_variant_lookup_value(
          props_dict, "HwAddress", G_VARIANT_TYPE_STRING);
      if (hw_value == nullptr) {
        continue;
      }
      const gchar* bssid = g_variant_get_string(hw_value, nullptr);
      if (bssid == nullptr || bssid[0] == '\0') {
        continue;
      }

      gint64 dbm = -70;
      g_autoptr(GVariant) strength_value =
          g_variant_lookup_value(props_dict, "Strength", G_VARIANT_TYPE_BYTE);
      if (strength_value != nullptr) {
        const guint8 pct = g_variant_get_byte(strength_value);
        dbm = static_cast<gint64>(pct / 2) - 100;
      }

      WifiAccessPoint access_point;
      access_point.mac_address = bssid;
      access_point.signal_strength = dbm;
      out_aps->push_back(std::move(access_point));
    }
  }
}

// Queries GeoClue2 location off the main thread, falling back to Wi-Fi APs.
static std::unique_ptr<LocationQueryResult> query_geoclue2_location(
    GCancellable* cancellable) {
  std::unique_ptr<LocationQueryResult> result(new LocationQueryResult());
  if (g_cancellable_is_cancelled(cancellable)) {
    return result;
  }

  GError* error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SYSTEM, cancellable, &error);
  if (bus == nullptr) {
    g_clear_error(&error);
    return result;
  }

  g_autoptr(GVariant) client_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager",
      "org.freedesktop.GeoClue2.Manager", "GetClient", nullptr,
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 1500, cancellable, &error);
  if (client_reply == nullptr) {
    g_clear_error(&error);
    query_network_manager_wifi_aps(bus, cancellable, &result->wifi_aps);
    return result;
  }

  const gchar* client_path = nullptr;
  g_variant_get(client_reply, "(&o)", &client_path);
  if (client_path == nullptr || g_strcmp0(client_path, "/") == 0) {
    query_network_manager_wifi_aps(bus, cancellable, &result->wifi_aps);
    return result;
  }

  gdouble latitude = 0.0;
  gdouble longitude = 0.0;
  gdouble accuracy = 100000.0;
  gboolean has_coords = FALSE;

  const gboolean configured =
      set_geoclue_client_property(bus, client_path, "DesktopId",
                                  g_variant_new_string(APPLICATION_ID),
                                  cancellable) &&
      set_geoclue_client_property(bus, client_path, "RequestedAccuracyLevel",
                                  g_variant_new_uint32(8), cancellable) &&
      set_geoclue_client_property(bus, client_path, "DistanceThreshold",
                                  g_variant_new_uint32(100), cancellable) &&
      set_geoclue_client_property(bus, client_path, "TimeThreshold",
                                  g_variant_new_uint32(300), cancellable);

  if (configured) {
    g_autoptr(GVariant) start_reply = g_dbus_connection_call_sync(
        bus, "org.freedesktop.GeoClue2", client_path,
        "org.freedesktop.GeoClue2.Client", "Start", nullptr, nullptr,
        G_DBUS_CALL_FLAGS_NONE, 1500, cancellable, &error);
    if (start_reply == nullptr) {
      g_clear_error(&error);
    } else {
      for (int attempt = 0; attempt < 5; ++attempt) {
        if (g_cancellable_is_cancelled(cancellable)) {
          break;
        }
        g_autoptr(GVariant) loc_prop_reply = g_dbus_connection_call_sync(
            bus, "org.freedesktop.GeoClue2", client_path,
            "org.freedesktop.DBus.Properties", "Get",
            g_variant_new("(ss)", "org.freedesktop.GeoClue2.Client",
                          "Location"),
            G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1500, cancellable,
            &error);
        const gchar* location_path = nullptr;
        g_autoptr(GVariant) loc_boxed = nullptr;
        if (loc_prop_reply == nullptr) {
          g_clear_error(&error);
        } else {
          g_variant_get(loc_prop_reply, "(v)", &loc_boxed);
          if (loc_boxed != nullptr &&
              g_variant_is_of_type(loc_boxed, G_VARIANT_TYPE_OBJECT_PATH)) {
            location_path = g_variant_get_string(loc_boxed, nullptr);
          }
        }
        if (location_path != nullptr && g_strcmp0(location_path, "/") != 0 &&
            read_geoclue_double_property(bus, location_path, "Latitude",
                                         cancellable, &latitude) &&
            read_geoclue_double_property(bus, location_path, "Longitude",
                                         cancellable, &longitude)) {
          read_geoclue_double_property(bus, location_path, "Accuracy",
                                       cancellable, &accuracy);
          has_coords = (accuracy <= 5000.0);
          break;
        }
        if (attempt + 1 < 5 && !sleep_cancellable_ms(cancellable, 120)) {
          break;
        }
      }

      g_autoptr(GVariant) stop_reply = g_dbus_connection_call_sync(
          bus, "org.freedesktop.GeoClue2", client_path,
          "org.freedesktop.GeoClue2.Client", "Stop", nullptr, nullptr,
          G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
      if (stop_reply == nullptr) {
        g_clear_error(&error);
      }
    }
  }

  delete_geoclue_client(bus, client_path);

  if (has_coords) {
    result->found = TRUE;
    result->latitude = latitude;
    result->longitude = longitude;
    return result;
  }

  if (!g_cancellable_is_cancelled(cancellable)) {
    query_network_manager_wifi_aps(bus, cancellable, &result->wifi_aps);
  }
  return result;
}

// Builds an unavailable location payload map on the GTK main thread.
static FlValue* build_unavailable_location_map() {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string("unavailable"));
  return map;
}

// Converts a worker-thread LocationQueryResult into a Flutter method payload.
static FlValue* build_location_result_map(const LocationQueryResult* result) {
  if (result == nullptr) {
    return build_unavailable_location_map();
  }
  if (result->found) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "status", fl_value_new_string("found"));
    fl_value_set_string_take(map, "latitude",
                             fl_value_new_float(result->latitude));
    fl_value_set_string_take(map, "longitude",
                             fl_value_new_float(result->longitude));
    fl_value_set_string_take(map, "source", fl_value_new_string("system"));
    return map;
  }

  FlValue* map = build_unavailable_location_map();
  if (!result->wifi_aps.empty()) {
    FlValue* ap_list = fl_value_new_list();
    for (const WifiAccessPoint& access_point : result->wifi_aps) {
      FlValue* ap_map = fl_value_new_map();
      fl_value_set_string_take(
          ap_map, "macAddress",
          fl_value_new_string(access_point.mac_address.c_str()));
      fl_value_set_string_take(ap_map, "signalStrength",
                               fl_value_new_int(access_point.signal_strength));
      fl_value_append_take(ap_list, ap_map);
    }
    fl_value_set_string_take(map, "wifiAccessPoints", ap_list);
  }
  return map;
}

// GTask worker function executing blocking D-Bus location calls off-thread.
static void location_query_thread_func(GTask* task,
                                       gpointer source_object,
                                       gpointer task_data,
                                       GCancellable* cancellable) {
  (void)source_object;
  (void)task_data;
  std::unique_ptr<LocationQueryResult> result =
      query_geoclue2_location(cancellable);
  g_task_return_pointer(task, result.release(), destroy_location_query_result);
}

// GTask completion callback responding on the GTK main loop if still alive.
static void on_location_query_complete(GObject* source_object,
                                       GAsyncResult* async_result,
                                       gpointer user_data) {
  (void)source_object;
  (void)user_data;
  GTask* task = G_TASK(async_result);
  auto* context = static_cast<LocationTaskContext*>(g_task_get_task_data(task));

  GError* error = nullptr;
  std::unique_ptr<LocationQueryResult> query_result(
      static_cast<LocationQueryResult*>(
          g_task_propagate_pointer(task, &error)));
  if (error != nullptr) {
    g_clear_error(&error);
  }

  if (context == nullptr || context->method_call == nullptr) {
    return;
  }

  g_autoptr(FlMethodCall) method_call = context->method_call;
  context->method_call = nullptr;

  gpointer raw_app = g_weak_ref_get(&context->app_ref);
  g_autoptr(MyApplication) app =
      raw_app != nullptr ? MY_APPLICATION(raw_app) : nullptr;
  GCancellable* cancellable = g_task_get_cancellable(task);
  if (app == nullptr || !app->engine_active ||
      app->engine_generation != context->engine_generation ||
      (cancellable != nullptr && g_cancellable_is_cancelled(cancellable))) {
    return;
  }

  g_autoptr(FlValue) result_map = build_location_result_map(query_result.get());
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result_map));
  fl_method_call_respond(method_call, response, nullptr);
}

static void on_location_method_call(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "getLocation") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (!self->engine_active) {
    return;
  }

  if (self->location_cancellable == nullptr) {
    self->location_cancellable = g_cancellable_new();
  }

  auto* context = new LocationTaskContext();
  g_weak_ref_init(&context->app_ref, self);
  context->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  context->engine_generation = self->engine_generation;

  g_autoptr(GTask) task = g_task_new(nullptr, self->location_cancellable,
                                     on_location_query_complete, nullptr);
  g_task_set_task_data(task, context, destroy_location_task_context);
  g_task_run_in_thread(task, location_query_thread_func);
}

static gboolean is_ascii_alpha(gchar ch) {
  return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
}

static gboolean is_rfc3986_scheme_char(gchar ch) {
  return is_ascii_alpha(ch) || (ch >= '0' && ch <= '9') || ch == '+' ||
         ch == '-' || ch == '.';
}

// Rejects ASCII controls, C1 controls, Unicode line/paragraph separators, and
// BiDi control/override/isolate marks.
static gboolean is_forbidden_uri_char(gunichar ch) {
  if (ch <= 0x1F || ch == 0x7F) {
    return TRUE;
  }
  if (ch >= 0x80 && ch <= 0x9F) {
    return TRUE;
  }
  if (ch == 0x061C || ch == 0x200E || ch == 0x200F) {
    return TRUE;
  }
  if (ch == 0x2028 || ch == 0x2029) {
    return TRUE;
  }
  if (ch >= 0x202A && ch <= 0x202E) {
    return TRUE;
  }
  if (ch >= 0x2066 && ch <= 0x2069) {
    return TRUE;
  }
  return FALSE;
}

// Checks whether a lowercase URI scheme is blocked by the launch security policy.
static gboolean is_blocked_uri_scheme(const gchar* lowercase_scheme) {
  static const gchar* const kBlockedSchemes[] = {
      "javascript",      "vbscript",    "jscript", "livescript", "data",
      "blob",            "about",       "view-source", "file",   "smb",
      "cifs",            "nfs",         "jar",     "shell",      "cmd",
      "powershell",      "wscript",     "cscript", "ms-msdt",    "search-ms",
      "ms-appinstaller", "mhtml",       "its",     "mk",         "hcp",
      "res",             "intent",      "content",
  };
  for (gsize i = 0; i < G_N_ELEMENTS(kBlockedSchemes); ++i) {
    if (g_strcmp0(lowercase_scheme, kBlockedSchemes[i]) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

// Validates a launch URI against RFC 3986 scheme syntax and the blocklist.
static gboolean validate_launch_uri(const gchar* uri,
                                    const gchar** out_reason) {
  if (uri == nullptr || uri[0] == '\0') {
    *out_reason = "URI is empty.";
    return FALSE;
  }
  if (!g_utf8_validate(uri, -1, nullptr)) {
    *out_reason = "URI is not valid UTF-8.";
    return FALSE;
  }

  gboolean is_first = TRUE;
  gunichar last_char = 0;
  for (const gchar* cursor = uri; *cursor != '\0';
       cursor = g_utf8_next_char(cursor)) {
    const gunichar ch = g_utf8_get_char(cursor);
    if (is_first) {
      if (g_unichar_isspace(ch)) {
        *out_reason = "URI must not contain leading whitespace.";
        return FALSE;
      }
      is_first = FALSE;
    }
    if (is_forbidden_uri_char(ch)) {
      *out_reason = "URI contains forbidden control or BiDi characters.";
      return FALSE;
    }
    last_char = ch;
  }
  if (is_first || g_unichar_isspace(last_char)) {
    *out_reason = "URI must not be empty or contain trailing whitespace.";
    return FALSE;
  }

  const gchar* colon = std::strchr(uri, ':');
  if (colon == nullptr || colon == uri) {
    *out_reason = "URI must start with a valid scheme.";
    return FALSE;
  }
  const gsize scheme_length = static_cast<gsize>(colon - uri);
  if (scheme_length < 2) {
    *out_reason = "URI scheme must be at least two characters.";
    return FALSE;
  }
  if (colon[1] == '\0') {
    *out_reason = "URI must have a non-empty remainder after the scheme.";
    return FALSE;
  }
  if (!is_ascii_alpha(uri[0])) {
    *out_reason = "URI scheme must start with an ASCII letter.";
    return FALSE;
  }
  for (const gchar* cursor = uri + 1; cursor < colon; ++cursor) {
    if (!is_rfc3986_scheme_char(*cursor)) {
      *out_reason = "URI scheme contains invalid characters.";
      return FALSE;
    }
  }

  g_autofree gchar* lowercase_scheme =
      g_ascii_strdown(uri, static_cast<gssize>(scheme_length));
  if (is_blocked_uri_scheme(lowercase_scheme)) {
    *out_reason = "URI scheme is blocked by security policy.";
    return FALSE;
  }
  return TRUE;
}

static void on_link_launcher_method_call(FlMethodChannel* channel,
                                         FlMethodCall* method_call,
                                         gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "openLink") != 0) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  const gchar* uri = nullptr;
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* uri_val = fl_value_lookup_string(args, "uri");
    if (uri_val != nullptr &&
        fl_value_get_type(uri_val) == FL_VALUE_TYPE_STRING) {
      uri = fl_value_get_string(uri_val);
    }
  }

  const gchar* reject_reason = "Invalid URI.";
  if (!validate_launch_uri(uri, &reject_reason)) {
    response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_URI", reject_reason, nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(GError) error = nullptr;
  if (g_app_info_launch_default_for_uri(uri, nullptr, &error)) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "LAUNCH_FAILED",
        error != nullptr ? error->message : "Failed to launch URI.", nullptr));
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void on_app_version_method_call(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "getAppVersion") == 0) {
    g_autoptr(FlValue) result = fl_value_new_string(TIERTASK_FULL_VERSION);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Locates Flutter 3.50's Wayland subsurface renderer widget inside FlView.
static GtkWidget* find_subsurface_renderer(FlView* view) {
  if (view == nullptr || !GTK_IS_CONTAINER(view)) {
    return nullptr;
  }
  g_autoptr(GList) children = gtk_container_get_children(GTK_CONTAINER(view));
  for (GList* item = children; item != nullptr; item = item->next) {
    GtkWidget* child = GTK_WIDGET(item->data);
    if (GTK_IS_BIN(child)) {
      GtkWidget* grandchild = gtk_bin_get_child(GTK_BIN(child));
      if (grandchild != nullptr &&
          g_strcmp0(G_OBJECT_TYPE_NAME(grandchild),
                    "FlViewRendererSubsurface") == 0) {
        return grandchild;
      }
    }
  }
  return nullptr;
}

// Recreates FlViewRendererSubsurface's Wayland subsurface when the GTK scale
// factor changes across mixed-DPI Wayland outputs (Flutter 3.50 sets
// wl_surface_set_buffer_scale only once during subsurface creation).
static void sync_wayland_subsurface_scale(FlView* view) {
  GtkWidget* renderer = find_subsurface_renderer(view);
  if (renderer == nullptr || !gtk_widget_get_realized(renderer)) {
    return;
  }
  GtkWidget* toplevel = gtk_widget_get_toplevel(renderer);
  if (toplevel == nullptr || !GTK_IS_WINDOW(toplevel)) {
    return;
  }
  GdkWindow* gdk_window = gtk_widget_get_window(toplevel);
  if (gdk_window == nullptr) {
    return;
  }

  const gint current_scale = gtk_widget_get_scale_factor(renderer);
  const gint previous_scale = GPOINTER_TO_INT(
      g_object_get_data(G_OBJECT(renderer), "tiertask-subsurface-scale"));
  if (current_scale == previous_scale) {
    return;
  }
  g_object_set_data(G_OBJECT(renderer), "tiertask-subsurface-scale",
                    GINT_TO_POINTER(current_scale));

  GtkAllocation allocation;
  gtk_widget_get_allocation(renderer, &allocation);
  GtkWidgetClass* widget_class = GTK_WIDGET_GET_CLASS(renderer);
  if (widget_class == nullptr || widget_class->size_allocate == nullptr) {
    return;
  }

  g_object_ref(gdk_window);
  g_object_freeze_notify(G_OBJECT(toplevel));
  gtk_widget_set_window(toplevel, nullptr);
  widget_class->size_allocate(renderer, &allocation);
  gtk_widget_set_window(toplevel, gdk_window);
  g_object_thaw_notify(G_OBJECT(toplevel));
  widget_class->size_allocate(renderer, &allocation);
  g_object_unref(gdk_window);
}

static void on_wayland_scale_factor_notify(GObject* object,
                                           GParamSpec* pspec,
                                           gpointer user_data) {
  (void)object;
  (void)pspec;
  sync_wayland_subsurface_scale(FL_VIEW(user_data));
}

// Returns TRUE when the window is resizable and neither maximized nor fullscreen.
static gboolean is_window_resizable_state(GtkWindow* window) {
  if (window == nullptr || !gtk_window_get_resizable(window) ||
      gtk_window_is_maximized(window)) {
    return FALSE;
  }
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr) {
    return FALSE;
  }
  const GdkWindowState state = gdk_window_get_state(gdk_window);
  return (state & GDK_WINDOW_STATE_FULLSCREEN) == 0;
}

// Resolves the resize edge when (x, y) lies inside the frameless border strip.
static gboolean hit_test_resize_edge(GtkWindow* window,
                                     gdouble x,
                                     gdouble y,
                                     GdkWindowEdge* out_edge) {
  constexpr gdouble kResizeBorder = 5.0;
  constexpr gdouble kCornerSize = 12.0;

  const gint width = gtk_widget_get_allocated_width(GTK_WIDGET(window));
  const gint height = gtk_widget_get_allocated_height(GTK_WIDGET(window));
  if (width <= 0 || height <= 0 || x < 0.0 || y < 0.0 || x >= width ||
      y >= height) {
    return FALSE;
  }

  const gboolean near_left = x < kResizeBorder;
  const gboolean near_right = x >= width - kResizeBorder;
  const gboolean near_top = y < kResizeBorder;
  const gboolean near_bottom = y >= height - kResizeBorder;
  if (!near_left && !near_right && !near_top && !near_bottom) {
    return FALSE;
  }

  const gboolean corner_left = x < kCornerSize;
  const gboolean corner_right = x >= width - kCornerSize;
  const gboolean corner_top = y < kCornerSize;
  const gboolean corner_bottom = y >= height - kCornerSize;

  if ((near_top && corner_left) || (near_left && corner_top)) {
    *out_edge = GDK_WINDOW_EDGE_NORTH_WEST;
  } else if ((near_top && corner_right) || (near_right && corner_top)) {
    *out_edge = GDK_WINDOW_EDGE_NORTH_EAST;
  } else if ((near_bottom && corner_left) || (near_left && corner_bottom)) {
    *out_edge = GDK_WINDOW_EDGE_SOUTH_WEST;
  } else if ((near_bottom && corner_right) || (near_right && corner_bottom)) {
    *out_edge = GDK_WINDOW_EDGE_SOUTH_EAST;
  } else if (near_top) {
    *out_edge = GDK_WINDOW_EDGE_NORTH;
  } else if (near_bottom) {
    *out_edge = GDK_WINDOW_EDGE_SOUTH;
  } else if (near_left) {
    *out_edge = GDK_WINDOW_EDGE_WEST;
  } else {
    *out_edge = GDK_WINDOW_EDGE_EAST;
  }
  return TRUE;
}

// Maps a frameless window resize edge to its standard CSS cursor name.
static const gchar* cursor_name_for_resize_edge(GdkWindowEdge edge) {
  switch (edge) {
    case GDK_WINDOW_EDGE_NORTH_WEST:
      return "nw-resize";
    case GDK_WINDOW_EDGE_NORTH:
      return "n-resize";
    case GDK_WINDOW_EDGE_NORTH_EAST:
      return "ne-resize";
    case GDK_WINDOW_EDGE_WEST:
      return "w-resize";
    case GDK_WINDOW_EDGE_EAST:
      return "e-resize";
    case GDK_WINDOW_EDGE_SOUTH_WEST:
      return "sw-resize";
    case GDK_WINDOW_EDGE_SOUTH:
      return "s-resize";
    case GDK_WINDOW_EDGE_SOUTH_EAST:
      return "se-resize";
  }
  return nullptr;
}

static void set_cursor_if_needed(GdkWindow* gdk_window, GdkCursor* cursor) {
  if (gdk_window == nullptr || gdk_window_is_destroyed(gdk_window)) {
    return;
  }
  if (gdk_window_get_cursor(gdk_window) != cursor) {
    gdk_window_set_cursor(gdk_window, cursor);
  }
}

// Applies or resets the resize cursor across the toplevel and Flutter surfaces.
static void apply_cursor_to_window_hierarchy(MyApplication* self,
                                             GdkCursor* cursor,
                                             GdkWindow* event_window) {
  if (self->main_window == nullptr) {
    return;
  }
  GdkWindow* toplevel_gdk_window =
      gtk_widget_get_window(GTK_WIDGET(self->main_window));
  if (toplevel_gdk_window == nullptr ||
      gdk_window_is_destroyed(toplevel_gdk_window)) {
    return;
  }
  set_cursor_if_needed(toplevel_gdk_window, cursor);

  GtkWidget* child_view = gtk_bin_get_child(GTK_BIN(self->main_window));
  GdkWindow* view_gdk_window =
      child_view != nullptr ? gtk_widget_get_window(child_view) : nullptr;
  if (view_gdk_window != nullptr && view_gdk_window != toplevel_gdk_window) {
    set_cursor_if_needed(view_gdk_window, cursor);
  }

  if (child_view != nullptr && FL_IS_VIEW(child_view)) {
    GtkWidget* renderer = find_subsurface_renderer(FL_VIEW(child_view));
    GdkWindow* renderer_window =
        renderer != nullptr ? gtk_widget_get_window(renderer) : nullptr;
    if (renderer_window != nullptr &&
        renderer_window != toplevel_gdk_window &&
        renderer_window != view_gdk_window) {
      set_cursor_if_needed(renderer_window, cursor);
    }
  }

  if (event_window != nullptr && !gdk_window_is_destroyed(event_window) &&
      gdk_window_get_toplevel(event_window) == toplevel_gdk_window &&
      event_window != toplevel_gdk_window && event_window != view_gdk_window) {
    set_cursor_if_needed(event_window, cursor);
  }
}

// Restores default cursor handling once the pointer leaves resize zones.
static void clear_resize_cursor(MyApplication* self, GdkWindow* event_window) {
  if (self->has_resize_cursor) {
    apply_cursor_to_window_hierarchy(self, nullptr, event_window);
  }
  g_clear_object(&self->active_resize_cursor);
  self->has_resize_cursor = FALSE;
}

// Updates the frameless border resize cursor for pointer coordinates (x, y).
static void update_resize_hover_cursor(MyApplication* self,
                                       gdouble x,
                                       gdouble y) {
  GdkEvent* current_event = gtk_get_current_event();
  GdkWindow* event_window =
      current_event != nullptr ? current_event->any.window : nullptr;

  GdkWindowEdge edge = GDK_WINDOW_EDGE_EAST;
  if (!self->primary_button_pressed &&
      is_window_resizable_state(self->main_window) &&
      hit_test_resize_edge(self->main_window, x, y, &edge)) {
    GdkWindow* toplevel_gdk_window =
        gtk_widget_get_window(GTK_WIDGET(self->main_window));
    GdkDisplay* display = toplevel_gdk_window != nullptr
                              ? gdk_window_get_display(toplevel_gdk_window)
                              : nullptr;
    if (display != nullptr) {
      if (!self->has_resize_cursor || self->active_resize_edge != edge ||
          self->active_resize_cursor == nullptr) {
        const gchar* cursor_name = cursor_name_for_resize_edge(edge);
        g_clear_object(&self->active_resize_cursor);
        if (cursor_name != nullptr) {
          self->active_resize_cursor =
              gdk_cursor_new_from_name(display, cursor_name);
        }
        self->active_resize_edge = edge;
        self->has_resize_cursor = (self->active_resize_cursor != nullptr);
      }
      if (self->active_resize_cursor != nullptr) {
        apply_cursor_to_window_hierarchy(self, self->active_resize_cursor,
                                         event_window);
      }
    }
  } else if (self->has_resize_cursor) {
    clear_resize_cursor(self, event_window);
  }

  if (current_event != nullptr) {
    gdk_event_free(current_event);
  }
}

static void on_window_motion_enter(GtkEventControllerMotion* controller,
                                   gdouble x,
                                   gdouble y,
                                   gpointer user_data) {
  (void)controller;
  update_resize_hover_cursor(MY_APPLICATION(user_data), x, y);
}

static void on_window_motion(GtkEventControllerMotion* controller,
                             gdouble x,
                             gdouble y,
                             gpointer user_data) {
  (void)controller;
  update_resize_hover_cursor(MY_APPLICATION(user_data), x, y);
}

static void on_window_motion_leave(GtkEventControllerMotion* controller,
                                   gpointer user_data) {
  (void)controller;
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->has_resize_cursor) {
    return;
  }
  GdkEvent* current_event = gtk_get_current_event();
  GdkWindow* event_window =
      current_event != nullptr ? current_event->any.window : nullptr;
  clear_resize_cursor(self, event_window);
  if (current_event != nullptr) {
    gdk_event_free(current_event);
  }
}

// Records primary button press coordinates, timestamp, and master pointer.
static void record_primary_button_press(MyApplication* self,
                                        const GdkEvent* event) {
  if (event == nullptr || event->type != GDK_BUTTON_PRESS) {
    return;
  }
  const GdkEventButton* button_event = &event->button;
  if (button_event->button != GDK_BUTTON_PRIMARY) {
    return;
  }
  self->last_button_press_x_root = static_cast<gint>(button_event->x_root);
  self->last_button_press_y_root = static_cast<gint>(button_event->y_root);
  self->last_button_press_time = button_event->time;
  g_set_object(&self->last_button_press_device, gdk_event_get_device(event));
  self->has_last_button_press = TRUE;
}

// Captures primary pointer presses on the toplevel window before FlView to
// record the Wayland/X11 event metadata and handle frameless edge resizing.
static void on_window_gesture_pressed(GtkGestureMultiPress* gesture,
                                      gint n_press,
                                      gdouble x,
                                      gdouble y,
                                      gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  GdkEvent* event = gtk_get_current_event();
  if (event == nullptr) {
    return;
  }

  if (event->type == GDK_BUTTON_PRESS) {
    const GdkEventButton* button_event = &event->button;
    record_primary_button_press(self, event);

    if (n_press == 1 && button_event->button == GDK_BUTTON_PRIMARY &&
        is_window_resizable_state(self->main_window)) {
      GdkWindowEdge edge = GDK_WINDOW_EDGE_EAST;
      if (hit_test_resize_edge(self->main_window, x, y, &edge)) {
        self->primary_button_pressed = FALSE;
        gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
        gtk_window_begin_resize_drag(
            self->main_window, edge, static_cast<gint>(button_event->button),
            static_cast<gint>(button_event->x_root),
            static_cast<gint>(button_event->y_root), button_event->time);
      }
    }
  }
  gdk_event_free(event);
}

// Tracks primary button press state across drag motion for startDragging.
static void on_window_drag_begin(GtkGestureDrag* gesture,
                                 gdouble start_x,
                                 gdouble start_y,
                                 gpointer user_data) {
  (void)gesture;
  (void)start_x;
  (void)start_y;
  MyApplication* self = MY_APPLICATION(user_data);
  GdkEvent* event = gtk_get_current_event();
  if (event != nullptr) {
    if (event->type == GDK_BUTTON_PRESS &&
        event->button.button == GDK_BUTTON_PRIMARY) {
      record_primary_button_press(self, event);
      self->primary_button_pressed = TRUE;
    }
    gdk_event_free(event);
  }
}

static void on_window_drag_end(GtkGestureDrag* gesture,
                               gdouble offset_x,
                               gdouble offset_y,
                               gpointer user_data) {
  (void)gesture;
  (void)offset_x;
  (void)offset_y;
  MyApplication* self = MY_APPLICATION(user_data);
  self->primary_button_pressed = FALSE;
}

static void on_window_drag_cancel(GtkGesture* gesture,
                                  GdkEventSequence* sequence,
                                  gpointer user_data) {
  (void)gesture;
  (void)sequence;
  MyApplication* self = MY_APPLICATION(user_data);
  self->primary_button_pressed = FALSE;
}

// Handles custom desktop chrome commands on de.akjir.tiertask/window_controls.
static void on_window_controls_method_call(FlMethodChannel* channel,
                                           FlMethodCall* method_call,
                                           gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "closeWindow") == 0) {
    if (self->main_window != nullptr) {
      gtk_window_close(self->main_window);
    }
    g_autoptr(FlValue) result = fl_value_new_bool(self->main_window != nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "startDragging") == 0) {
    gboolean started = FALSE;
    if (self->main_window != nullptr) {
      GdkWindow* gdk_window =
          gtk_widget_get_window(GTK_WIDGET(self->main_window));
      GdkDisplay* display =
          gdk_window != nullptr ? gdk_window_get_display(gdk_window) : nullptr;
      GdkSeat* seat =
          display != nullptr ? gdk_display_get_default_seat(display) : nullptr;
      GdkDevice* pointer = nullptr;
      if (self->last_button_press_device != nullptr &&
          gdk_device_get_display(self->last_button_press_device) == display &&
          gdk_device_get_device_type(self->last_button_press_device) !=
              GDK_DEVICE_TYPE_SLAVE) {
        pointer = self->last_button_press_device;
      } else if (seat != nullptr) {
        pointer = gdk_seat_get_pointer(seat);
      }

      if (gdk_window != nullptr && pointer != nullptr) {
        gboolean button_active = self->primary_button_pressed;
        if (!button_active) {
          GdkModifierType modifiers = static_cast<GdkModifierType>(0);
          gdk_window_get_device_position(gdk_window, pointer, nullptr, nullptr,
                                         &modifiers);
          button_active = (modifiers & GDK_BUTTON1_MASK) != 0;
        }
        if (button_active) {
          gint root_x = self->last_button_press_x_root;
          gint root_y = self->last_button_press_y_root;
          guint32 timestamp = self->last_button_press_time;
          if (!self->has_last_button_press) {
            gdk_device_get_position(pointer, nullptr, &root_x, &root_y);
            timestamp = GDK_CURRENT_TIME;
          }
          gdk_window_begin_move_drag_for_device(gdk_window, pointer,
                                                GDK_BUTTON_PRIMARY, root_x,
                                                root_y, timestamp);
          self->primary_button_pressed = FALSE;
          started = TRUE;
        }
      }
    }
    g_autoptr(FlValue) result = fl_value_new_bool(started);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
    if (self->main_window != nullptr) {
      if (gtk_window_is_maximized(self->main_window)) {
        gtk_window_unmaximize(self->main_window);
      } else {
        clear_resize_cursor(self, nullptr);
        gtk_window_maximize(self->main_window);
      }
    }
    g_autoptr(FlValue) result = fl_value_new_bool(self->main_window != nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// Clears window-scoped state and active async tasks on toplevel destroy.
static void on_main_window_destroy(GtkWidget* widget, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (GTK_WIDGET(self->main_window) == widget) {
    self->engine_active = FALSE;
    cancel_pending_location_queries(self);
    cleanup_active_file_dialog(self);
    clear_window_input_controllers(self);
    self->main_window = nullptr;
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  (void)self;
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  sync_wayland_subsurface_scale(view);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  cancel_pending_location_queries(self);
  cleanup_active_file_dialog(self);
  clear_method_channels(self);
  clear_resize_cursor(self, nullptr);
  clear_window_input_controllers(self);

  self->engine_generation += 1;
  self->engine_active = TRUE;
  self->location_cancellable = g_cancellable_new();

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Disable native GTK/WM decorations so TierTask renders its own frameless
  // desktop chrome bar with drag, double-click maximize, and close controls.
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_resizable(window, TRUE);
  gtk_window_set_title(window, "TierTask");

  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path = g_build_filename(
        exe_dir, "data", "flutter_assets", "assets", "logo",
        "tiertask_logo.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_add_events(GTK_WIDGET(window),
                        GDK_POINTER_MOTION_MASK | GDK_ENTER_NOTIFY_MASK |
                            GDK_LEAVE_NOTIFY_MASK);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_object(view, "first-frame", G_CALLBACK(first_frame_cb), self,
                          G_CONNECT_SWAPPED);
  gtk_widget_realize(GTK_WIDGET(view));
  GtkWidget* subsurface_renderer = find_subsurface_renderer(view);
  if (subsurface_renderer != nullptr) {
    g_object_set_data(
        G_OBJECT(subsurface_renderer), "tiertask-subsurface-scale",
        GINT_TO_POINTER(gtk_widget_get_scale_factor(subsurface_renderer)));
    g_signal_connect_object(view, "notify::scale-factor",
                            G_CALLBACK(on_wayland_scale_factor_notify), view,
                            G_CONNECT_AFTER);
    g_signal_connect_object(subsurface_renderer, "notify::scale-factor",
                            G_CALLBACK(on_wayland_scale_factor_notify), view,
                            G_CONNECT_AFTER);
  }

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  self->main_window = window;
  g_signal_connect_object(window, "destroy",
                          G_CALLBACK(on_main_window_destroy), self,
                          static_cast<GConnectFlags>(0));

  self->window_press_gesture = gtk_gesture_multi_press_new(GTK_WIDGET(window));
  gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(self->window_press_gesture),
                                GDK_BUTTON_PRIMARY);
  gtk_event_controller_set_propagation_phase(
      GTK_EVENT_CONTROLLER(self->window_press_gesture), GTK_PHASE_CAPTURE);
  g_signal_connect_object(self->window_press_gesture, "pressed",
                          G_CALLBACK(on_window_gesture_pressed), self,
                          static_cast<GConnectFlags>(0));

  self->window_drag_gesture = gtk_gesture_drag_new(GTK_WIDGET(window));
  gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(self->window_drag_gesture),
                                GDK_BUTTON_PRIMARY);
  gtk_event_controller_set_propagation_phase(
      GTK_EVENT_CONTROLLER(self->window_drag_gesture), GTK_PHASE_CAPTURE);
  g_signal_connect_object(self->window_drag_gesture, "drag-begin",
                          G_CALLBACK(on_window_drag_begin), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(self->window_drag_gesture, "drag-end",
                          G_CALLBACK(on_window_drag_end), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(self->window_drag_gesture, "cancel",
                          G_CALLBACK(on_window_drag_cancel), self,
                          static_cast<GConnectFlags>(0));

  self->window_motion_controller =
      gtk_event_controller_motion_new(GTK_WIDGET(window));
  gtk_event_controller_set_propagation_phase(self->window_motion_controller,
                                             GTK_PHASE_CAPTURE);
  g_signal_connect_object(self->window_motion_controller, "enter",
                          G_CALLBACK(on_window_motion_enter), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(self->window_motion_controller, "motion",
                          G_CALLBACK(on_window_motion), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(self->window_motion_controller, "leave",
                          G_CALLBACK(on_window_motion_leave), self,
                          static_cast<GConnectFlags>(0));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  self->app_version_channel = fl_method_channel_new(
      messenger, "de.akjir.tiertask/app_version", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->app_version_channel, on_app_version_method_call, self, nullptr);
  self->directory_picker_channel = fl_method_channel_new(
      messenger, "de.akjir.tiertask/directory_picker", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->directory_picker_channel, on_directory_picker_method_call, self,
      nullptr);
  self->link_launcher_channel = fl_method_channel_new(
      messenger, "de.akjir.tiertask/link_launcher", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->link_launcher_channel, on_link_launcher_method_call, self, nullptr);
  self->location_channel = fl_method_channel_new(
      messenger, "de.akjir.tiertask/location", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->location_channel, on_location_method_call, self, nullptr);
  self->window_controls_channel = fl_method_channel_new(
      messenger, "de.akjir.tiertask/window_controls", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_controls_channel, on_window_controls_method_call, self,
      nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  self->engine_active = FALSE;
  cancel_pending_location_queries(self);
  cleanup_active_file_dialog(self);

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  self->engine_active = FALSE;
  cancel_pending_location_queries(self);
  cleanup_active_file_dialog(self);
  clear_method_channels(self);
  clear_window_input_controllers(self);
  self->main_window = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  (void)self;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("TierTask");

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
