///|
/// Entry point for DuckDB-WASM Parquet Viewer
///
/// This module initializes the application in browser environments.

///|
/// Check if we're in a browser environment
extern "js" fn is_browser() -> Bool =
  #|() => typeof document !== 'undefined'

///|
fn init {
  // Only auto-initialize in browser environment
  if is_browser() {
    // Application initialization is triggered via JavaScript
    // to ensure proper DOM readiness
    ()
  }
}

///|
fn main {
  // For moon run compatibility
  ()
}

// Re-export app functions for JS access

///|
pub fn app_init() -> Unit {
  @app.app_init()
}

///|
pub fn run_sql_query() -> Unit {
  @app.run_sql_query()
}

///|
pub fn fetch_parquet() -> Unit {
  @app.fetch_parquet()
}

///|
pub fn purge_cache() -> Unit {
  @app.purge_cache()
}

///|
pub fn get_row_count() -> Unit {
  @app.get_row_count()
}

///|
pub fn run_preset_query(preset : String) -> Unit {
  @app.run_preset_query(preset)
}

///|
pub fn perform_search(search_term : String) -> Unit {
  @app.perform_search(search_term)
}
