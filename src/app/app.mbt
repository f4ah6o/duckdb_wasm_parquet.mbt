///|
/// Main application logic for DuckDB-WASM Parquet Viewer
///
/// This module provides the core functionality for:
/// - DuckDB initialization with OPFS persistence
/// - Parquet file loading from S3-compatible storage
/// - SQL query execution
/// - UI wiring for the browser

///|
/// Global connection state (managed via JS side)
extern "js" fn js_set_connection(conn : @duckdb.Connection) -> Unit =
  #|(conn) => { window.__duckdb_conn = conn; }

///|
extern "js" fn js_get_connection() -> @duckdb.Connection? =
  #|() => {
  #|  const conn = window.__duckdb_conn;
  #|  return conn ? { $tag: 1, _0: conn } : { $tag: 0 };
  #|}

///|
extern "js" fn js_has_connection() -> Bool =
  #|() => !!window.__duckdb_conn

///|
/// Global state for parquet loaded status
extern "js" fn js_set_parquet_loaded(loaded : Bool) -> Unit =
  #|(loaded) => { window.__parquet_loaded = loaded; }

///|
extern "js" fn js_is_parquet_loaded() -> Bool =
  #|() => !!window.__parquet_loaded

///|
/// Storage mode tracking (set by OPFS init)
extern "js" fn js_get_storage_mode() -> String =
  #|() => window.__duckdb_storage || "unknown"

///|
extern "js" fn js_get_storage_name() -> String =
  #|() => window.__duckdb_storage_name || ""

///|
/// Console logging helpers
extern "js" fn log_info(msg : String) -> Unit =
  #|(msg) => console.log("[app] " + msg)

///|
extern "js" fn log_error(msg : String) -> Unit =
  #|(msg) => console.error("[app] " + msg)

///|
/// The default Parquet URL
extern "js" fn js_parquet_url() -> String =
  #|() => window.__parquet_url || ""

///|
/// The table name used for the loaded parquet data
let table_name : String = "stats"

///|
/// Update UI element inner HTML
extern "js" fn js_set_inner_html(selector : String, html : String) -> Unit =
  #|(selector, html) => {
  #|  const el = document.querySelector(selector);
  #|  if (el) el.innerHTML = html;
  #|}

///|
/// Update status display
fn update_status(message : String) -> Unit {
  js_set_inner_html("#status", message)
}

///|
/// Update result display with HTML
fn update_result(html : String) -> Unit {
  js_set_inner_html("#result", html)
}

///|
/// Update row count display
fn update_row_count(count : String) -> Unit {
  js_set_inner_html("#row-count", count)
}

///|
/// Enable/disable button by selector
extern "js" fn js_set_button_disabled(
  selector : String,
  disabled : Bool,
) -> Unit =
  #|(selector, disabled) => {
  #|  const el = document.querySelector(selector);
  #|  if (el) el.disabled = disabled;
  #|}

///|
/// Extract error message from DuckDBError
fn error_message(err : @duckdb.DuckDBError) -> String {
  match err {
    @duckdb.DuckDBError::Message(msg) => msg
  }
}

///|
/// Initialize the application
/// This is the main entry point called from JavaScript
pub fn app_init() -> Unit {
  log_info("Initializing application...")
  update_status("Initializing DuckDB...")

  // Check OPFS support and initialize database
  check_opfs_support(on_done=fn(result) {
    match result {
      Ok(supported) => {
        log_info("OPFS supported: " + supported.to_string())
        if supported {
          init_database_opfs()
        } else {
          init_database_memory()
        }
      }
      Err(err) => {
        log_error("OPFS check failed: " + err)
        init_database_memory()
      }
    }
  })
}

///|
/// Initialize database with OPFS persistence
fn init_database_opfs() -> Unit {
  log_info("Opening OPFS database...")
  update_status("Opening persistent database...")
  open_opfs_database("duckdb.db", on_done=fn(result) {
    match result {
      Ok(conn) => {
        js_set_connection(conn)
        let mode = js_get_storage_mode()
        let storage_name = js_get_storage_name()
        if mode == "opfs" {
          if storage_name == "" || storage_name == "duckdb.db" {
            log_info("OPFS database opened successfully")
          } else {
            log_info(
              "OPFS database opened with alternate name: " + storage_name,
            )
          }
        } else if mode == "memory" {
          log_info("OPFS unavailable, using in-memory database")
        } else {
          log_info("Database opened successfully")
        }
        install_extensions(conn)
      }
      Err(err) => {
        log_error("OPFS database failed: " + err)
        init_database_memory()
      }
    }
  })
}

///|
/// Initialize database in memory (fallback)
fn init_database_memory() -> Unit {
  log_info("Opening in-memory database...")
  update_status("Opening in-memory database...")
  open_opfs_database(":memory:", on_done=fn(result) {
    match result {
      Ok(conn) => {
        js_set_connection(conn)
        log_info("In-memory database opened successfully")
        install_extensions(conn)
      }
      Err(err) => {
        log_error("Failed to open database: " + err)
        update_status("Error: Failed to initialize database - " + err)
      }
    }
  })
}

///|
/// Install required extensions (parquet, json)
fn install_extensions(conn : @duckdb.Connection) -> Unit {
  log_info("Installing extensions...")
  update_status("Installing extensions...")

  // Install parquet extension
  conn.query("INSTALL parquet; LOAD parquet;", on_done=fn(result) {
    match result {
      Ok(_) => {
        log_info("Parquet extension installed")
        // Install json extension
        conn.query("INSTALL json; LOAD json;", on_done=fn(result2) {
          match result2 {
            Ok(_) => {
              log_info("JSON extension installed")
              on_database_ready()
            }
            Err(err) => {
              log_error("JSON extension failed: " + error_message(err))
              // Continue anyway
              on_database_ready()
            }
          }
        })
      }
      Err(err) => {
        log_error("Parquet extension failed: " + error_message(err))
        // Continue anyway
        on_database_ready()
      }
    }
  })
}

///|
/// Called when database is ready
fn on_database_ready() -> Unit {
  log_info("Database ready!")
  let mode = js_get_storage_mode()
  let storage_name = js_get_storage_name()
  let status = if mode == "opfs" {
    let suffix = if storage_name == "" || storage_name == "duckdb.db" {
      ""
    } else {
      " (" + storage_name + ")"
    }
    "Ready (OPFS)" + suffix + ". Click 'Fetch Parquet' to load data."
  } else if mode == "memory" {
    "Ready (in-memory). Click 'Fetch Parquet' to load data."
  } else {
    "Ready. Click 'Fetch Parquet' to load data."
  }
  update_status(status)
  js_set_button_disabled("#btn-fetch", false)
  js_set_button_disabled("#btn-execute", false)
}

///|
/// Fetch and register the parquet file
pub fn fetch_parquet() -> Unit {
  guard js_has_connection() else {
    update_status("Error: Database not initialized")
    return
  }
  let conn = js_get_connection()
  guard conn is Some(c) else {
    update_status("Error: No connection")
    return
  }
  log_info("Fetching parquet file...")
  update_status("Fetching parquet file...")
  js_set_button_disabled("#btn-fetch", true)

  // Register the remote parquet file
  let url = js_parquet_url()
  if url == "" {
    let msg = "Error: Parquet URL not set (VITE_PARQUET_URL)"
    log_error(msg)
    update_status(msg)
    js_set_button_disabled("#btn-fetch", false)
    return
  }
  register_remote_file(c, "stats.parquet", url, on_done=fn(result) {
    match result {
      Ok(_) => {
        log_info("Remote file registered")
        create_table_from_parquet(c)
      }
      Err(err) => {
        log_error("Failed to register file: " + err)
        // Try direct URL query instead
        create_table_from_url(c)
      }
    }
  })
}

///|
/// Create table from registered parquet file
fn create_table_from_parquet(conn : @duckdb.Connection) -> Unit {
  let sql = "CREATE OR REPLACE TABLE " +
    table_name +
    " AS SELECT * FROM read_parquet('stats.parquet')"
  conn.query(sql, on_done=fn(result) {
    match result {
      Ok(_) => {
        js_set_parquet_loaded(true)
        log_info("Table created from parquet")
        update_status("Parquet data loaded successfully!")
        js_set_button_disabled("#btn-fetch", false)
        get_row_count()
      }
      Err(err) => {
        log_error("Table creation failed: " + error_message(err))
        // Try direct URL
        create_table_from_url(conn)
      }
    }
  })
}

///|
/// Create table directly from URL (fallback)
fn create_table_from_url(conn : @duckdb.Connection) -> Unit {
  let url = js_parquet_url()
  if url == "" {
    let msg = "Error: Parquet URL not set (VITE_PARQUET_URL)"
    log_error(msg)
    update_status(msg)
    js_set_button_disabled("#btn-fetch", false)
    return
  }
  let sql = "CREATE OR REPLACE TABLE " +
    table_name +
    " AS SELECT * FROM read_parquet('" +
    url +
    "')"
  conn.query(sql, on_done=fn(result) {
    match result {
      Ok(_) => {
        js_set_parquet_loaded(true)
        log_info("Table created from URL")
        update_status("Parquet data loaded successfully!")
        js_set_button_disabled("#btn-fetch", false)
        get_row_count()
      }
      Err(err) => {
        let msg = error_message(err)
        log_error("Direct URL query failed: " + msg)
        update_status("Error: Failed to load parquet - " + msg)
        js_set_button_disabled("#btn-fetch", false)
      }
    }
  })
}

///|
/// Get the row count from the loaded table
pub fn get_row_count() -> Unit {
  guard js_has_connection() else { return }
  guard js_is_parquet_loaded() else {
    update_row_count("No data loaded")
    return
  }
  let conn = js_get_connection()
  guard conn is Some(c) else { return }
  let sql = "SELECT COUNT(*) as cnt FROM " + table_name
  c.query(sql, on_done=fn(result) {
    match result {
      Ok(res) =>
        if res.row_count() > 0 {
          let count = res.rows[0][0]
          update_row_count("Total rows: " + count)
        }
      Err(_) => update_row_count("Error counting rows")
    }
  })
}

///|
/// Escape SQL string to prevent injection
fn escape_sql_string(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    if c == '\'' {
      buf.write_string("''")
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Perform instant search
pub fn perform_search(search_term : String) -> Unit {
  // If search term is empty, clear results
  if search_term.length() == 0 {
    update_result("")
    return
  }
  guard js_has_connection() else { return }
  guard js_is_parquet_loaded() else { return }
  let conn = js_get_connection()
  guard conn is Some(c) else { return }
  let escaped_term = escape_sql_string(search_term)
  let sql = "SELECT timestamp, connection_id, rtc_type FROM " +
    table_name +
    " WHERE connection_id LIKE '%" +
    escaped_term +
    "%' OR channel_id LIKE '%" +
    escaped_term +
    "%' OR timestamp LIKE '%" +
    escaped_term +
    "%' OR rtc_type LIKE '%" +
    escaped_term +
    "%' USING SAMPLE 1 PERCENT (bernoulli)"
  log_info("Search: " + search_term)
  c.query(sql, on_done=fn(result) {
    match result {
      Ok(res) => {
        log_info("Search returned " + res.row_count().to_string() + " rows")
        render_result_table(res)
      }
      Err(err) => {
        let msg = error_message(err)
        log_error("Search failed: " + msg)
        update_result("")
      }
    }
  })
}

///|
/// Get SQL from textarea
extern "js" fn js_get_sql_input() -> String =
  #|() => {
  #|  const el = document.querySelector('#sql-input');
  #|  return el ? el.value : '';
  #|}

///|
/// Execute a SQL query from the input field
pub fn run_sql_query() -> Unit {
  guard js_has_connection() else {
    update_status("Error: Database not initialized")
    return
  }
  let conn = js_get_connection()
  guard conn is Some(c) else {
    update_status("Error: No connection")
    return
  }
  let sql = js_get_sql_input()
  if sql.length() == 0 {
    update_status("Please enter a SQL query")
    return
  }
  log_info("Executing: " + sql)
  update_status("Executing query...")
  c.query(sql, on_done=fn(result) {
    match result {
      Ok(res) => {
        log_info("Query returned " + res.row_count().to_string() + " rows")
        update_status(
          "Query completed: " + res.row_count().to_string() + " rows",
        )
        render_result_table(res)
      }
      Err(err) => {
        let msg = error_message(err)
        log_error("Query failed: " + msg)
        update_status("Error: " + msg)
        update_result("<div class=\"error\">Error: (check console)</div>")
      }
    }
  })
}

///|
/// Run a preset query by name
pub fn run_preset_query(preset : String) -> Unit {
  guard js_has_connection() else {
    update_status("Error: Database not initialized")
    return
  }
  guard js_is_parquet_loaded() else {
    update_status("Please load parquet data first")
    return
  }
  let conn = js_get_connection()
  guard conn is Some(c) else {
    update_status("Error: No connection")
    return
  }
  let sql = match preset {
    "samples" =>
      "SELECT timestamp, connection_id, rtc_type FROM " +
      table_name +
      " USING SAMPLE 1 PERCENT (bernoulli)"
    "aggregation" =>
      "SELECT time_bucket, channel_id, session_id, connection_id, bytes_sent_diff, bytes_received_diff, packets_sent_diff, packets_received_diff FROM ( SELECT time_bucket, channel_id, session_id, connection_id, bytes_sent - LAG(bytes_sent) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS bytes_sent_diff, bytes_received - LAG(bytes_received) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS bytes_received_diff, packets_sent - LAG(packets_sent) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS packets_sent_diff, packets_received - LAG(packets_received) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS packets_received_diff FROM ( SELECT strftime(time_bucket('15 seconds', strptime(timestamp, '%Y-%m-%dT%H:%M:%S.%fZ')), '%Y-%m-%d %H:%M:%S') AS time_bucket, channel_id, session_id, connection_id, MAX(CAST(rtc_data->'$.bytesSent' AS BIGINT)) AS bytes_sent, MAX(CAST(rtc_data->'$.bytesReceived' AS BIGINT)) AS bytes_received, MAX(CAST(rtc_data->'$.packetsSent' AS BIGINT)) AS packets_sent, MAX(CAST(rtc_data->'$.packetsReceived' AS BIGINT)) AS packets_received FROM " +
      table_name +
      " WHERE rtc_type = 'transport' GROUP BY time_bucket, channel_id, session_id, connection_id ) ) WHERE bytes_sent_diff IS NOT NULL AND bytes_received_diff IS NOT NULL AND packets_sent_diff IS NOT NULL AND packets_received_diff IS NOT NULL ORDER BY time_bucket ASC"
    "describe" => "DESCRIBE " + table_name
    _ => "SELECT * FROM " + table_name + " LIMIT 10"
  }
  log_info("Preset query: " + preset)
  update_status("Running preset: " + preset)
  c.query(sql, on_done=fn(result) {
    match result {
      Ok(res) => {
        log_info(
          "Preset query returned " + res.row_count().to_string() + " rows",
        )
        update_status("Completed: " + res.row_count().to_string() + " rows")
        render_result_table(res)
      }
      Err(err) => {
        let msg = error_message(err)
        log_error("Preset query failed: " + msg)
        update_status("Error: " + msg)
        update_result("<div class=\"error\">Error: (check console)</div>")
      }
    }
  })
}

///|
/// Purge the OPFS cache
pub fn purge_cache() -> Unit {
  log_info("Purging cache...")
  update_status("Purging cache...")

  // Close current connection if any
  let conn = js_get_connection()
  match conn {
    Some(c) => c.close(on_done=fn(_) { delete_opfs_files() })
    None => delete_opfs_files()
  }
}

///|
/// Delete OPFS files
fn delete_opfs_files() -> Unit {
  delete_opfs_file("duckdb.db", on_done=fn(result) {
    match result {
      Ok(_) =>
        delete_opfs_file("duckdb.db-wal", on_done=fn(result2) {
          match result2 {
            Ok(_) => {
              js_set_parquet_loaded(false)
              update_status("Cache purged. Reload the page to restart.")
              update_result("")
              update_row_count("")
              log_info("Cache purged")
            }
            Err(err) => {
              log_error("Failed to delete duckdb.db-wal: " + err)
              update_status(
                "Cache purge failed (db-wal locked). Close other tabs and retry.",
              )
            }
          }
        })
      Err(err) => {
        log_error("Failed to delete duckdb.db: " + err)
        update_status(
          "Cache purge failed (db locked). Close other tabs and retry.",
        )
      }
    }
  })
}

///|
/// Render query result as HTML table
fn render_result_table(result : @duckdb.QueryResult) -> Unit {
  let buf = StringBuilder::new()

  // Limit rows for display
  let max_rows = 1000
  let row_count = result.row_count()
  let display_rows = if row_count > max_rows { max_rows } else { row_count }

  // Build table header
  buf.write_string("<table class=\"result-table\"><thead><tr>")
  for i = 0; i < result.columns.length(); i = i + 1 {
    buf.write_string("<th>")
    buf.write_string(escape_html(result.columns[i]))
    buf.write_string("</th>")
  }
  buf.write_string("</tr></thead><tbody>")

  // Build table body
  for row = 0; row < display_rows; row = row + 1 {
    buf.write_string("<tr>")
    for col = 0; col < result.columns.length(); col = col + 1 {
      buf.write_string("<td>")
      if result.nulls[row][col] {
        buf.write_string("<span class=\"null\">NULL</span>")
      } else {
        buf.write_string(escape_html(result.rows[row][col]))
      }
      buf.write_string("</td>")
    }
    buf.write_string("</tr>")
  }
  buf.write_string("</tbody></table>")

  // Add truncation notice if needed
  if row_count > max_rows {
    buf.write_string(
      "<p class=\"notice\">Showing " +
      max_rows.to_string() +
      " of " +
      row_count.to_string() +
      " rows</p>",
    )
  }
  update_result(buf.to_string())
}

///|
/// Escape HTML special characters
fn escape_html(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    if c == '<' {
      buf.write_string("&lt;")
    } else if c == '>' {
      buf.write_string("&gt;")
    } else if c == '&' {
      buf.write_string("&amp;")
    } else if c == '"' {
      buf.write_string("&quot;")
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}
