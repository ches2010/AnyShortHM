use serde::Serialize;
use tauri::Manager;

#[derive(Serialize)]
struct AppInfo {
    name: String,
    version: String,
    platform: String,
}

/// 供前端查询运行环境（决定是否走 ohos 专用路径）
#[tauri::command]
fn app_info(app: tauri::AppHandle) -> AppInfo {
    let pkg = app.package_info();
    AppInfo {
        name: pkg.name.clone(),
        version: pkg.version.to_string(),
        platform: std::env::consts::OS.to_string(),
    }
}

/// 透传日志到 Rust 侧（便于 ohos 上抓日志）
#[tauri::command]
fn log_message(level: String, msg: String) {
    match level.as_str() {
        "error" => eprintln!("[web][error] {msg}"),
        "warn" => eprintln!("[web][warn] {msg}"),
        _ => println!("[web] {msg}"),
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // HTTP 在 Rust 侧发起，绕开 WebView 的 CORS 限制
        .plugin(tauri_plugin_http::init())
        .invoke_handler(tauri::generate_handler![app_info, log_message])
        .setup(|app| {
            #[cfg(debug_assertions)]
            {
                if let Some(w) = app.get_webview_window("main") {
                    w.open_devtools();
                }
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
