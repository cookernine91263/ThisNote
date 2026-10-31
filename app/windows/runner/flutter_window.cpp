#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {
// Single-window app: the subclassed child window finds its owner here.
// Do not use GWLP_USERDATA: Flutter's own view window keeps its state there.
FlutterWindow* g_drop_window = nullptr;
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

  drop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "this_note/drop",
          &flutter::StandardMethodCodec::GetInstance());

  // The Flutter view is a separate child window, so file drops are delivered
  // there. Subclass it and turn WM_DROPFILES into a Dart method call.
  child_hwnd_ = GetWindow(GetHandle(), GW_CHILD);
  if (child_hwnd_ != nullptr) {
    g_drop_window = this;
    original_child_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
        child_hwnd_, GWLP_WNDPROC,
        reinterpret_cast<LONG_PTR>(FlutterWindow::ChildWndProc)));
    DragAcceptFiles(child_hwnd_, TRUE);
  }

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
  if (child_hwnd_ != nullptr && original_child_proc_ != nullptr) {
    SetWindowLongPtr(child_hwnd_, GWLP_WNDPROC,
                     reinterpret_cast<LONG_PTR>(original_child_proc_));
    original_child_proc_ = nullptr;
    child_hwnd_ = nullptr;
  }
  g_drop_window = nullptr;
  drop_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT CALLBACK FlutterWindow::ChildWndProc(HWND window, UINT message,
                                             WPARAM wparam, LPARAM lparam) {
  auto* self = g_drop_window;
  if (self != nullptr) {
    if (message == WM_DROPFILES) {
      self->HandleDroppedFiles(reinterpret_cast<HDROP>(wparam));
      return 0;
    }
    if (self->original_child_proc_ != nullptr) {
      return CallWindowProc(self->original_child_proc_, window, message, wparam,
                            lparam);
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

void FlutterWindow::HandleDroppedFiles(HDROP drop) {
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  flutter::EncodableList paths;
  for (UINT i = 0; i < count; i++) {
    const UINT length = DragQueryFileW(drop, i, nullptr, 0);
    if (length == 0) {
      continue;
    }
    std::wstring buffer(length + 1, L'\0');
    const UINT copied = DragQueryFileW(drop, i, buffer.data(),
                                       static_cast<UINT>(buffer.size()));
    if (copied == 0) {
      continue;
    }
    buffer.resize(copied);
    paths.push_back(flutter::EncodableValue(Utf8FromUtf16(buffer.c_str())));
  }
  DragFinish(drop);
  if (drop_channel_ && !paths.empty()) {
    drop_channel_->InvokeMethod(
        "drop", std::make_unique<flutter::EncodableValue>(paths));
  }
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
