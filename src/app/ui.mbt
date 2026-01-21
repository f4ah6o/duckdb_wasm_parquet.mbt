///|
/// UI generation and event handling for DuckDB-WASM Parquet Viewer
///
/// This module provides helper functions for building the UI.

///|
/// Generate sample SQL queries for display
pub fn get_sample_queries() -> Array[(String, String)] {
  @app_core.get_sample_queries()
}
