#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* directory_picker_channel;
  FlMethodChannel* location_channel;
  GtkWindow* main_window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Handles the asynchronous response from the native GTK folder chooser dialog.
static void on_directory_dialog_response(GtkNativeDialog* dialog,
                                         gint response_id,
                                         gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = FL_METHOD_CALL(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (response_id == GTK_RESPONSE_ACCEPT) {
    g_autofree gchar* folder_path =
        gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
    if (folder_path != nullptr) {
      g_autoptr(FlValue) result = fl_value_new_string(folder_path);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  fl_method_call_respond(method_call, response, nullptr);
  gtk_native_dialog_destroy(dialog);
  g_object_unref(dialog);
}

// Handles method calls on the de.akjir.tiertask/directory_picker channel.
static void on_directory_picker_method_call(FlMethodChannel* channel,
                                            FlMethodCall* method_call,
                                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "pickDirectory") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      "Select Directory", self->main_window,
      GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, "_Open", "_Cancel");

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
  }

  g_signal_connect(dialog, "response", G_CALLBACK(on_directory_dialog_response),
                   g_object_ref(method_call));
  gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog));
}

static FlValue* build_unavailable_location_map() {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string("unavailable"));
  return map;
}

static gboolean read_geoclue_double_property(GDBusConnection* bus,
                                             const gchar* object_path,
                                             const gchar* property_name,
                                             gdouble* out_value) {
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", object_path,
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", "org.freedesktop.GeoClue2.Location", property_name),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
  if (reply == nullptr) {
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

static FlValue* query_network_manager_wifi_aps(GDBusConnection* bus) {
  FlValue* ap_list = fl_value_new_list();
  g_autoptr(GVariant) dev_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
      "org.freedesktop.NetworkManager", "GetDevices", nullptr,
      G_VARIANT_TYPE("(ao)"), G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
  if (dev_reply == nullptr) {
    return ap_list;
  }

  g_autoptr(GVariantIter) dev_iter = nullptr;
  g_variant_get(dev_reply, "(ao)", &dev_iter);
  const gchar* dev_path = nullptr;
  while (g_variant_iter_loop(dev_iter, "&o", &dev_path) &&
         fl_value_get_length(ap_list) < 20) {
    g_autoptr(GVariant) ap_reply = g_dbus_connection_call_sync(
        bus, "org.freedesktop.NetworkManager", dev_path,
        "org.freedesktop.NetworkManager.Device.Wireless", "GetAllAccessPoints",
        nullptr, G_VARIANT_TYPE("(ao)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr,
        nullptr);
    if (ap_reply == nullptr) {
      continue;
    }
    g_autoptr(GVariantIter) ap_iter = nullptr;
    g_variant_get(ap_reply, "(ao)", &ap_iter);
    const gchar* ap_path = nullptr;
    while (g_variant_iter_loop(ap_iter, "&o", &ap_path) &&
           fl_value_get_length(ap_list) < 20) {
      g_autoptr(GVariant) hw_reply = g_dbus_connection_call_sync(
          bus, "org.freedesktop.NetworkManager", ap_path,
          "org.freedesktop.DBus.Properties", "Get",
          g_variant_new("(ss)", "org.freedesktop.NetworkManager.AccessPoint",
                        "HwAddress"),
          G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 500, nullptr, nullptr);
      if (hw_reply == nullptr) {
        continue;
      }
      g_autoptr(GVariant) hw_boxed = nullptr;
      g_variant_get(hw_reply, "(v)", &hw_boxed);
      if (hw_boxed == nullptr ||
          !g_variant_is_of_type(hw_boxed, G_VARIANT_TYPE_STRING)) {
        continue;
      }
      const gchar* bssid = g_variant_get_string(hw_boxed, nullptr);
      if (bssid == nullptr || bssid[0] == '\0') {
        continue;
      }

      gint64 dbm = -70;
      g_autoptr(GVariant) str_reply = g_dbus_connection_call_sync(
          bus, "org.freedesktop.NetworkManager", ap_path,
          "org.freedesktop.DBus.Properties", "Get",
          g_variant_new("(ss)", "org.freedesktop.NetworkManager.AccessPoint",
                        "Strength"),
          G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 500, nullptr, nullptr);
      if (str_reply != nullptr) {
        g_autoptr(GVariant) str_boxed = nullptr;
        g_variant_get(str_reply, "(v)", &str_boxed);
        if (str_boxed != nullptr &&
            g_variant_is_of_type(str_boxed, G_VARIANT_TYPE_BYTE)) {
          guint8 pct = g_variant_get_byte(str_boxed);
          dbm = static_cast<gint64>(pct / 2) - 100;
        }
      }

      FlValue* ap_map = fl_value_new_map();
      fl_value_set_string_take(ap_map, "macAddress",
                               fl_value_new_string(bssid));
      fl_value_set_string_take(ap_map, "signalStrength",
                               fl_value_new_int(dbm));
      fl_value_append_take(ap_list, ap_map);
    }
  }
  return ap_list;
}

static FlValue* build_unavailable_with_wifi_map(GDBusConnection* bus) {
  FlValue* map = build_unavailable_location_map();
  if (bus != nullptr) {
    FlValue* wifi_aps = query_network_manager_wifi_aps(bus);
    if (fl_value_get_length(wifi_aps) > 0) {
      fl_value_set_string_take(map, "wifiAccessPoints", wifi_aps);
    } else {
      fl_value_unref(wifi_aps);
    }
  }
  return map;
}

static FlValue* query_geoclue2_location() {
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, nullptr);
  if (bus == nullptr) {
    return build_unavailable_location_map();
  }

  g_autoptr(GVariant) client_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager",
      "org.freedesktop.GeoClue2.Manager", "GetClient", nullptr,
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
  if (client_reply == nullptr) {
    return build_unavailable_with_wifi_map(bus);
  }

  const gchar* client_path = nullptr;
  g_variant_get(client_reply, "(&o)", &client_path);
  if (client_path == nullptr || g_strcmp0(client_path, "/") == 0) {
    return build_unavailable_with_wifi_map(bus);
  }

  g_autoptr(GVariant) desktop_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", client_path,
      "org.freedesktop.DBus.Properties", "Set",
      g_variant_new("(ssv)", "org.freedesktop.GeoClue2.Client", "DesktopId",
                    g_variant_new_string(APPLICATION_ID)),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
  g_autoptr(GVariant) acc_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", client_path,
      "org.freedesktop.DBus.Properties", "Set",
      g_variant_new("(ssv)", "org.freedesktop.GeoClue2.Client",
                    "RequestedAccuracyLevel", g_variant_new_uint32(8)),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
  g_autoptr(GVariant) dist_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", client_path,
      "org.freedesktop.DBus.Properties", "Set",
      g_variant_new("(ssv)", "org.freedesktop.GeoClue2.Client",
                    "DistanceThreshold", g_variant_new_uint32(100)),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
  g_autoptr(GVariant) time_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", client_path,
      "org.freedesktop.DBus.Properties", "Set",
      g_variant_new("(ssv)", "org.freedesktop.GeoClue2.Client",
                    "TimeThreshold", g_variant_new_uint32(300)),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);

  g_autoptr(GVariant) start_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", client_path,
      "org.freedesktop.GeoClue2.Client", "Start", nullptr, nullptr,
      G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
  if (start_reply == nullptr) {
    return build_unavailable_with_wifi_map(bus);
  }

  gdouble latitude = 0.0;
  gdouble longitude = 0.0;
  gdouble accuracy = 100000.0;
  gboolean has_coords = FALSE;

  for (int attempt = 0; attempt < 5; ++attempt) {
    g_autoptr(GVariant) loc_prop_reply = g_dbus_connection_call_sync(
        bus, "org.freedesktop.GeoClue2", client_path,
        "org.freedesktop.DBus.Properties", "Get",
        g_variant_new("(ss)", "org.freedesktop.GeoClue2.Client", "Location"),
        G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1500, nullptr, nullptr);
    const gchar* location_path = nullptr;
    g_autoptr(GVariant) loc_boxed = nullptr;
    if (loc_prop_reply != nullptr) {
      g_variant_get(loc_prop_reply, "(v)", &loc_boxed);
      if (loc_boxed != nullptr &&
          g_variant_is_of_type(loc_boxed, G_VARIANT_TYPE_OBJECT_PATH)) {
        location_path = g_variant_get_string(loc_boxed, nullptr);
      }
    }
    if (location_path != nullptr && g_strcmp0(location_path, "/") != 0 &&
        read_geoclue_double_property(bus, location_path, "Latitude",
                                     &latitude) &&
        read_geoclue_double_property(bus, location_path, "Longitude",
                                     &longitude)) {
      read_geoclue_double_property(bus, location_path, "Accuracy", &accuracy);
      has_coords = (accuracy <= 5000.0);
      break;
    }
    g_usleep(120000);
  }

  g_autoptr(GVariant) stop_reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.GeoClue2", client_path,
      "org.freedesktop.GeoClue2.Client", "Stop", nullptr, nullptr,
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);

  if (!has_coords) {
    return build_unavailable_with_wifi_map(bus);
  }

  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string("found"));
  fl_value_set_string_take(map, "latitude", fl_value_new_float(latitude));
  fl_value_set_string_take(map, "longitude", fl_value_new_float(longitude));
  fl_value_set_string_take(map, "source", fl_value_new_string("system"));
  return map;
}

static void on_location_method_call(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "getLocation") == 0) {
    g_autoptr(FlValue) result = query_geoclue2_location();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "TierTask");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }
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
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  self->main_window = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  self->directory_picker_channel = fl_method_channel_new(
      messenger, "de.akjir.tiertask/directory_picker", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->directory_picker_channel, on_directory_picker_method_call, self,
      nullptr);
  self->location_channel = fl_method_channel_new(
      messenger, "de.akjir.tiertask/location", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->location_channel, on_location_method_call, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
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
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->directory_picker_channel);
  g_clear_object(&self->location_channel);
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

static void my_application_init(MyApplication* self) {}

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
