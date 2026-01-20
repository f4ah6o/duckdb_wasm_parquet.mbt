///|
/// UI generation and event handling for DuckDB-WASM Parquet Viewer
///
/// This module provides helper functions for building the UI.

///|
/// Generate sample SQL queries for display
pub fn get_sample_queries() -> Array[(String, String)] {
  [
    ("Sample 1%", "SELECT * FROM stats USING SAMPLE 1%"),
    (
      "Count by Hour", "SELECT date_trunc('hour', timestamp) as hour, COUNT(*) as count FROM stats GROUP BY 1 ORDER BY 1",
    ),
    ("Describe Table", "DESCRIBE stats"),
    ("First 100 Rows", "SELECT * FROM stats LIMIT 100"),
    (
      "Schema Info", "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'stats'",
    ),
  ]
}
