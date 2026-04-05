#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use tauri::{CustomMenuItem, Menu, MenuItem, Submenu};
use std::sync::Mutex;

mod commands;
use commands::{AppState, Vault};

fn main() {
    let menu = Menu::new()
        .add_submenu(Submenu::new(
            "ClawPass",
            Menu::new()
                .add_native_item(MenuItem::About("ClawPass".to_string()))
                .add_native_item(MenuItem::Separator)
                .add_item(CustomMenuItem::new("preferences".to_string(), "Preferences...").accelerator("CmdOrCtrl+,"))
                .add_native_item(MenuItem::Separator)
                .add_native_item(MenuItem::Quit),
        ))
        .add_submenu(Submenu::new(
            "Edit",
            Menu::new()
                .add_native_item(MenuItem::Undo)
                .add_native_item(MenuItem::Redo)
                .add_native_item(MenuItem::Separator)
                .add_native_item(MenuItem::Cut)
                .add_native_item(MenuItem::Copy)
                .add_native_item(MenuItem::Paste)
                .add_native_item(MenuItem::Separator)
                .add_item(CustomMenuItem::new("generate_password".to_string(), "Generate Password").accelerator("CmdOrCtrl+G")),
        ))
        .add_submenu(Submenu::new(
            "Sync",
            Menu::new()
                .add_item(CustomMenuItem::new("start_listening".to_string(), "Start Listening"))
                .add_item(CustomMenuItem::new("discover_devices".to_string(), "Discover Devices")),
        ));

    tauri::Builder::default()
        .manage(AppState {
            vault: Mutex::new(None),
        })
        .menu(menu)
        .on_menu_event(|event| {
            match event.menu_item_id() {
                "preferences" => {
                    event.window().emit("show_preferences", ()).unwrap();
                }
                "generate_password" => {
                    event.window().emit("generate_password", ()).unwrap();
                }
                _ => {}
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::unlock_vault,
            commands::lock_vault,
            commands::create_vault,
            commands::get_entries,
            commands::add_entry,
            commands::update_entry,
            commands::delete_entry,
            commands::decrypt_password,
            commands::decrypt_notes,
            commands::generate_password,
            commands::import_from_keeper,
            commands::export_vault,
            commands::start_sync_listener,
            commands::discover_sync_peers,
            commands::connect_to_peer
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
