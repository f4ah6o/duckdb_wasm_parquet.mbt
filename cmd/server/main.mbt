///|
using @js {run_async}

///|
using @url {type URL}

///|
using @node_http {type IncomingMessage, type ServerResponse, createServer}

///|
extern "js" fn js_env(key : String) -> String? =
  #|(key) => {
  #|  const env = globalThis.process ? globalThis.process.env : undefined;
  #|  const value = env ? env[key] : undefined;
  #|  return typeof value === "string" ? value : undefined;
  #|}

///|
let parquet_url : String = match js_env("PARQUET_URL") {
  Some(v) => v
  None => "https://duckdb-wasm-mbt.f12o.com/P78BHZM3MD3MV47JDZG47PB8PW.parquet"
}

///|
/// Internal state for the DuckDB connection.
priv enum DbState {
  Empty
  Loading
  Ready(@duckdb.Connection)
  Failed(String)
}

///|
let db_state : Ref[DbState] = Ref::new(Empty)

///|
let parquet_loaded : Ref[Bool] = Ref::new(false)

///|
/// Extract error message from DuckDBError.
fn error_message(err : @duckdb.DuckDBError) -> String {
  match err {
    @duckdb.DuckDBError::Message(msg) => msg
  }
}

///|
extern "js" fn respond_html(
  res : ServerResponse,
  status : Int,
  body : String,
) -> Unit =
  #| (res, status, body) => {
  #|   res.statusCode = status;
  #|   res.setHeader("Content-Type", "text/html; charset=utf-8");
  #|   res.end(body);
  #| }

///|
extern "js" fn respond_redirect(
  res : ServerResponse,
  location : String,
) -> Unit =
  #| (res, location) => {
  #|   res.statusCode = 302;
  #|   res.setHeader("Location", location);
  #|   res.end("");
  #| }

///|
fn status_oob(message : String) -> String {
  "<div id=\"status\" hx-swap-oob=\"true\">" +
  @app_core.escape_html(message) +
  "</div>"
}

///|
fn row_count_oob(message : String) -> String {
  "<div id=\"row-count\" hx-swap-oob=\"true\">" +
  @app_core.escape_html(message) +
  "</div>"
}

///|
fn fragment_with_meta(
  body : String,
  status_msg : String,
  row_msg : String,
) -> String {
  body + status_oob(status_msg) + row_count_oob(row_msg)
}

///|
async fn query_result(
  conn : @duckdb.Connection,
  sql : String,
) -> Result[@duckdb.QueryResult, String] {
  let { promise, resolve, .. } = @core.Promise::withResolvers()
  conn.query(sql, on_done=fn(result) { resolve(result) })
  let result = promise.wait()
  match result {
    Ok(res) => Ok(res)
    Err(err) => Err(error_message(err))
  }
}

///|
async fn exec_sql(
  conn : @duckdb.Connection,
  sql : String,
) -> Result[Unit, String] {
  let result = query_result(conn, sql)
  match result {
    Ok(_) => Ok(())
    Err(err) => Err(err)
  }
}

///|
async fn install_extensions(conn : @duckdb.Connection) -> Result[Unit, String] {
  let parquet_result = exec_sql(conn, "INSTALL parquet; LOAD parquet;")
  match parquet_result {
    Ok(_) => {
      let json_result = exec_sql(conn, "INSTALL json; LOAD json;")
      match json_result {
        Ok(_) => Ok(())
        Err(err) => Err(err)
      }
    }
    Err(err) => Err(err)
  }
}

///|
async fn connect_node() -> Result[@duckdb.Connection, String] {
  let { promise, resolve, .. } = @core.Promise::withResolvers()
  @duckdb.connect(
    on_ready=fn(result) { resolve(result) },
    backend=@duckdb.JsBackend::Node,
  )
  let result = promise.wait()
  match result {
    Ok(conn) => Ok(conn)
    Err(err) => Err(error_message(err))
  }
}

///|
async fn ensure_connection() -> Result[@duckdb.Connection, String] {
  match db_state.val {
    Ready(conn) => Ok(conn)
    Failed(msg) => Err(msg)
    Loading => Err("Database is initializing")
    Empty => {
      db_state.update(fn(_) { Loading })
      let conn_result = connect_node()
      match conn_result {
        Ok(conn) => {
          let install_result = install_extensions(conn)
          match install_result {
            Ok(_) => {
              db_state.update(fn(_) { Ready(conn) })
              Ok(conn)
            }
            Err(err) => {
              db_state.update(fn(_) { Failed(err) })
              Err(err)
            }
          }
        }
        Err(err) => {
          db_state.update(fn(_) { Failed(err) })
          Err(err)
        }
      }
    }
  }
}

///|
async fn ensure_parquet_loaded(
  conn : @duckdb.Connection,
) -> Result[Unit, String] {
  if parquet_loaded.val {
    return Ok(())
  }
  let sql = "CREATE OR REPLACE TABLE " +
    @app_core.table_name +
    " AS SELECT * FROM read_parquet('" +
    parquet_url +
    "')"
  let create_result = exec_sql(conn, sql)
  match create_result {
    Ok(_) => {
      parquet_loaded.update(fn(_) { true })
      Ok(())
    }
    Err(err) => Err(err)
  }
}

///|
async fn load_handler(conn : @duckdb.Connection) -> (Int, String) {
  let load_result = ensure_parquet_loaded(conn)
  match load_result {
    Ok(_) => {
      let count_result = query_result(conn, @app_core.count_sql())
      match count_result {
        Ok(res) => {
          let count = if res.row_count() > 0 { res.rows[0][0] } else { "0" }
          let body = fragment_with_meta(
            "<div>Parquet loaded.</div>",
            "Parquet data loaded successfully!",
            "Total rows: " + count,
          )
          (200, body)
        }
        Err(err) => {
          let body = fragment_with_meta(
            @app_core.render_error("Row count failed: " + err),
            "Row count failed",
            "",
          )
          (200, body)
        }
      }
    }
    Err(err) => {
      let body = fragment_with_meta(
        @app_core.render_error("Load failed: " + err),
        "Load failed",
        "",
      )
      (500, body)
    }
  }
}

///|
async fn purge_handler(conn : @duckdb.Connection) -> (Int, String) {
  let drop_result = exec_sql(
    conn,
    "DROP TABLE IF EXISTS " + @app_core.table_name,
  )
  match drop_result {
    Ok(_) => {
      parquet_loaded.update(fn(_) { false })
      let body = fragment_with_meta(
        "<div>Cache purged.</div>", "Cache purged", "",
      )
      (200, body)
    }
    Err(err) => {
      let body = fragment_with_meta(
        @app_core.render_error("Purge failed: " + err),
        "Purge failed",
        "",
      )
      (500, body)
    }
  }
}

///|
async fn query_handler(
  conn : @duckdb.Connection,
  sql : String,
  label : String,
) -> (Int, String) {
  let load_result = ensure_parquet_loaded(conn)
  match load_result {
    Ok(_) => {
      let result = query_result(conn, sql)
      match result {
        Ok(res) => {
          let body = fragment_with_meta(
            @app_core.render_result_table(res),
            label + ": " + res.row_count().to_string() + " rows",
            "Rows: " + res.row_count().to_string(),
          )
          (200, body)
        }
        Err(err) => {
          let body = fragment_with_meta(
            @app_core.render_error("Query failed: " + err),
            "Query failed",
            "",
          )
          (500, body)
        }
      }
    }
    Err(err) => {
      let body = fragment_with_meta(
        @app_core.render_error("Load failed: " + err),
        "Load failed",
        "",
      )
      (500, body)
    }
  }
}

///|
fn extract_url(req : IncomingMessage) -> URL {
  let req_any : @core.Any = @core.identity(req)
  let raw : String = @core.identity(req_any._get("url"))
  URL::new("http://localhost" + raw) catch {
    _ => try! URL::new("http://localhost/")
  }
}

///|
fn handle_request(req : IncomingMessage, res : ServerResponse) -> Unit {
  run_async(async fn() noraise {
    let url = extract_url(req)
    let path = url.pathname
    if path == "/parquet" {
      respond_redirect(res, parquet_url)
      return
    }
    let conn_result = ensure_connection() catch {
      err => {
        let body = fragment_with_meta(
          @app_core.render_error("DB init failed: " + err.to_string()),
          "DB init failed",
          "",
        )
        respond_html(res, 500, body)
        return
      }
    }
    match conn_result {
      Err(err) => {
        let body = fragment_with_meta(
          @app_core.render_error("DB init failed: " + err),
          "DB init failed",
          "",
        )
        respond_html(res, 500, body)
      }
      Ok(conn) => {
        if path == "/" {
          respond_html(res, 200, @app_core.page_html(parquet_url))
          return
        }
        if path == "/api/load" {
          let (status, body) = load_handler(conn) catch {
            err =>
              (
                500,
                fragment_with_meta(
                  @app_core.render_error("Load failed: " + err.to_string()),
                  "Load failed",
                  "",
                ),
              )
          }
          respond_html(res, status, body)
          return
        }
        if path == "/api/purge" {
          let (status, body) = purge_handler(conn) catch {
            err =>
              (
                500,
                fragment_with_meta(
                  @app_core.render_error("Purge failed: " + err.to_string()),
                  "Purge failed",
                  "",
                ),
              )
          }
          respond_html(res, status, body)
          return
        }
        if path == "/api/preset" {
          let preset = match url.searchParams().get("p") {
            Some(v) => v
            None => ""
          }
          let sql = @app_core.preset_sql(preset)
          let (status, body) = query_handler(conn, sql, "Preset") catch {
            err =>
              (
                500,
                fragment_with_meta(
                  @app_core.render_error("Query failed: " + err.to_string()),
                  "Query failed",
                  "",
                ),
              )
          }
          respond_html(res, status, body)
          return
        }
        if path == "/api/search" {
          let term = match url.searchParams().get("term") {
            Some(v) => v
            None => ""
          }
          if term == "" {
            respond_html(res, 200, "")
            return
          }
          let sql = @app_core.search_sql(term)
          let (status, body) = query_handler(conn, sql, "Search") catch {
            err =>
              (
                500,
                fragment_with_meta(
                  @app_core.render_error("Query failed: " + err.to_string()),
                  "Query failed",
                  "",
                ),
              )
          }
          respond_html(res, status, body)
          return
        }
        if path == "/api/sql" {
          let query = match url.searchParams().get("query") {
            Some(v) => v
            None => ""
          }
          if query == "" {
            let body = fragment_with_meta(
              @app_core.render_error("SQL is empty"),
              "SQL is empty",
              "",
            )
            respond_html(res, 400, body)
            return
          }
          let (status, body) = query_handler(conn, query, "SQL") catch {
            err =>
              (
                500,
                fragment_with_meta(
                  @app_core.render_error("Query failed: " + err.to_string()),
                  "Query failed",
                  "",
                ),
              )
          }
          respond_html(res, status, body)
          return
        }
        respond_html(res, 200, @app_core.page_html(parquet_url))
      }
    }
  })
}

///|
/// Entry point for Node server.
fn main {
  let port = match js_env("PORT") {
    Some(p) => @strconv.parse_int(p, base=10) catch { _ => 8788 }
    None => 8788
  }
  let server = createServer(requestListener=handle_request)
  ignore(
    server.listen(port, callback=fn() {
      println("Server listening on http://localhost:" + port.to_string())
    }),
  )
}
