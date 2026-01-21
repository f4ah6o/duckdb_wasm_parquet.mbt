///|
using @async {run_async_main}

///|
let parquet_url : String = match @sys.get_env_var("PARQUET_URL") {
  Some(v) => v
  None => "https://duckdb-wasm-mbt.f12o.com/P78BHZM3MD3MV47JDZG47PB8PW.parquet"
}

///|
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
fn error_message(err : @duckdb.DuckDBError) -> String {
  match err {
    @duckdb.DuckDBError::Message(msg) => msg
  }
}

///|
fn status_reason(code : Int) -> String {
  match code {
    200 => "OK"
    302 => "Found"
    400 => "Bad Request"
    404 => "Not Found"
    405 => "Method Not Allowed"
    500 => "Internal Server Error"
    _ => "OK"
  }
}

///|
fn connect_native() -> Result[@duckdb.Connection, String] {
  let result_ref : Ref[Result[@duckdb.Connection, @duckdb.DuckDBError]?] = Ref::new(
    None,
  )
  @duckdb.connect(on_ready=fn(result) {
    result_ref.update(fn(_) { Some(result) })
  })
  match result_ref.val {
    Some(Ok(conn)) => Ok(conn)
    Some(Err(err)) => Err(error_message(err))
    None => Err("duckdb connect did not return")
  }
}

///|
fn query_result(
  conn : @duckdb.Connection,
  sql : String,
) -> Result[@duckdb.QueryResult, String] {
  let result_ref : Ref[Result[@duckdb.QueryResult, @duckdb.DuckDBError]?] = Ref::new(
    None,
  )
  conn.query(sql, on_done=fn(result) {
    result_ref.update(fn(_) { Some(result) })
  })
  match result_ref.val {
    Some(Ok(res)) => Ok(res)
    Some(Err(err)) => Err(error_message(err))
    None => Err("duckdb query did not return")
  }
}

///|
fn exec_sql(conn : @duckdb.Connection, sql : String) -> Result[Unit, String] {
  match query_result(conn, sql) {
    Ok(_) => Ok(())
    Err(err) => Err(err)
  }
}

///|
fn install_extensions(conn : @duckdb.Connection) -> Result[Unit, String] {
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
fn ensure_connection() -> Result[@duckdb.Connection, String] {
  match db_state.val {
    Ready(conn) => Ok(conn)
    Failed(msg) => Err(msg)
    Loading => Err("Database is initializing")
    Empty => {
      db_state.update(fn(_) { Loading })
      let conn_result = connect_native()
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
fn ensure_parquet_loaded(conn : @duckdb.Connection) -> Result[Unit, String] {
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
fn load_handler(conn : @duckdb.Connection) -> (Int, String) {
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
fn purge_handler(conn : @duckdb.Connection) -> (Int, String) {
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
fn query_handler(
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
fn hex_value(b : Byte) -> Int? {
  if b >= b'0' && b <= b'9' {
    Some(b.to_int() - b'0'.to_int())
  } else if b >= b'a' && b <= b'f' {
    Some(b.to_int() - b'a'.to_int() + 10)
  } else if b >= b'A' && b <= b'F' {
    Some(b.to_int() - b'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn url_decode(s : String) -> String {
  let input = @encoding/utf8.encode(s)
  let out : Array[Byte] = []
  let len = input.length()
  for i = 0; i < len; {
    let b = input[i]
    if b == b'%' && i + 2 < len {
      let hi = hex_value(input[i + 1])
      let lo = hex_value(input[i + 2])
      match (hi, lo) {
        (Some(h), Some(l)) => {
          out.push((h * 16 + l).to_byte())
          continue i + 3
        }
        _ => {
          out.push(b)
          continue i + 1
        }
      }
    } else if b == b'+' {
      out.push(b' ')
      continue i + 1
    } else {
      out.push(b)
      continue i + 1
    }
  } else {
    ()
  }
  @encoding/utf8.decode_lossy(Bytes::from_array(out))
}

///|
fn split_path_query(path : String) -> (String, String) {
  match path.find("?") {
    Some(idx) =>
      ((try! path[:idx]).to_string(), (try! path[idx + 1:]).to_string())
    None => (path, "")
  }
}

///|
fn parse_query(query : String) -> Map[String, String] {
  let params : Map[String, String] = {}
  if query != "" {
    for part in query.split("&") {
      let part_str = part.to_string()
      if part_str == "" {
        continue
      }
      match part_str.find("=") {
        Some(idx) => {
          let key = url_decode((try! part_str[:idx]).to_string())
          let value = url_decode((try! part_str[idx + 1:]).to_string())
          params[key] = value
        }
        None => {
          let key = url_decode(part_str)
          params[key] = ""
        }
      }
    } else {
      ()
    }
  }
  params
}

///|
fn get_param(params : Map[String, String], key : String) -> String {
  match params.get(key) {
    Some(v) => v
    None => ""
  }
}

///|
async fn respond_html(
  conn : @http.ServerConnection,
  status : Int,
  body : String,
) -> Unit {
  conn.send_response(status, status_reason(status), extra_headers={
    "Content-Type": "text/html; charset=utf-8",
  })
  conn.write(body)
  conn.end_response()
}

///|
async fn respond_redirect(
  conn : @http.ServerConnection,
  location : String,
) -> Unit {
  conn.send_response(302, status_reason(302), extra_headers={
    "Location": location,
  })
  conn.end_response()
}

///|
async fn handle_request(
  req : @http.Request,
  _reader : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  if req.meth != @http.RequestMethod::Get {
    respond_html(conn, 405, @app_core.render_error("Method not allowed"))
    return
  }
  let (path, raw_query) = split_path_query(req.path)
  if path == "/parquet" {
    respond_redirect(conn, parquet_url)
    return
  }
  let conn_result = ensure_connection()
  match conn_result {
    Err(err) => {
      let body = fragment_with_meta(
        @app_core.render_error("DB init failed: " + err),
        "DB init failed",
        "",
      )
      respond_html(conn, 500, body)
    }
    Ok(db) => {
      if path == "/" {
        respond_html(conn, 200, @app_core.page_html(parquet_url))
        return
      }
      if path == "/api/load" {
        let (status, body) = load_handler(db)
        respond_html(conn, status, body)
        return
      }
      if path == "/api/purge" {
        let (status, body) = purge_handler(db)
        respond_html(conn, status, body)
        return
      }
      let params = parse_query(raw_query)
      if path == "/api/preset" {
        let preset = get_param(params, "p")
        let sql = @app_core.preset_sql(preset)
        let (status, body) = query_handler(db, sql, "Preset")
        respond_html(conn, status, body)
        return
      }
      if path == "/api/search" {
        let term = get_param(params, "term")
        if term == "" {
          respond_html(conn, 200, "")
          return
        }
        let sql = @app_core.search_sql(term)
        let (status, body) = query_handler(db, sql, "Search")
        respond_html(conn, status, body)
        return
      }
      if path == "/api/sql" {
        let query = get_param(params, "query")
        if query == "" {
          let body = fragment_with_meta(
            @app_core.render_error("SQL is empty"),
            "SQL is empty",
            "",
          )
          respond_html(conn, 400, body)
          return
        }
        let (status, body) = query_handler(db, query, "SQL")
        respond_html(conn, status, body)
        return
      }
      respond_html(conn, 200, @app_core.page_html(parquet_url))
    }
  }
}

///|
fn port_from_env() -> Int {
  match @sys.get_env_var("PORT") {
    Some(p) => @strconv.parse_int(p, base=10) catch { _ => 8788 }
    None => 8788
  }
}

///|
fn main {
  run_async_main(async fn() {
    let port = port_from_env()
    let addr = @socket.Addr::new(0, port)
    let server = @http.Server::new(addr, reuse_addr=true) catch {
      err => {
        println("Failed to start server: " + err.to_string())
        return
      }
    }
    println("Native server listening on http://localhost:" + port.to_string())
    server.run_forever(handle_request, allow_failure=true)
  })
}
