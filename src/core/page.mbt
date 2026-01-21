///|
/// HTML page template for HTMX server rendering.

///|
fn parquet_filename(source : String) -> String {
  let mut last = ""
  for part in source.split("/") {
    last = part.to_string()
  }
  if last == "" {
    source
  } else {
    last
  }
}

///|
/// Render the base HTML page.
pub fn page_html(parquet_source : String) -> String {
  let source = escape_html(parquet_source)
  let filename = escape_html(parquet_filename(parquet_source))
  let title = "DuckDB-Wasm (OPFS) + Parquet + S3-compatible object storage with MoonBit"
  let default_sql : String =
    #|SELECT
    #|  time_bucket,
    #|  channel_id,
    #|  session_id,
    #|  connection_id,
    #|  bytes_sent_diff,
    #|  bytes_received_diff,
    #|  packets_sent_diff,
    #|  packets_received_diff
    #|FROM (
    #|  SELECT
    #|    time_bucket,
    #|    channel_id,
    #|    session_id,
    #|    connection_id,
    #|    bytes_sent - LAG(bytes_sent) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS bytes_sent_diff,
    #|    bytes_received - LAG(bytes_received) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS bytes_received_diff,
    #|    packets_sent - LAG(packets_sent) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS packets_sent_diff,
    #|    packets_received - LAG(packets_received) OVER (PARTITION BY channel_id, session_id, connection_id ORDER BY time_bucket) AS packets_received_diff
    #|  FROM (
    #|    SELECT
    #|      strftime(time_bucket('15 seconds', strptime(timestamp, '%Y-%m-%dT%H:%M:%S.%fZ')), '%Y-%m-%d %H:%M:%S') AS time_bucket,
    #|      channel_id,
    #|      session_id,
    #|      connection_id,
    #|      MAX(CAST(rtc_data->'$.bytesSent' AS BIGINT)) AS bytes_sent,
    #|      MAX(CAST(rtc_data->'$.bytesReceived' AS BIGINT)) AS bytes_received,
    #|      MAX(CAST(rtc_data->'$.packetsSent' AS BIGINT)) AS packets_sent,
    #|      MAX(CAST(rtc_data->'$.packetsReceived' AS BIGINT)) AS packets_received
    #|    FROM stats
    #|    WHERE rtc_type = 'transport'
    #|    GROUP BY time_bucket, channel_id, session_id, connection_id
    #|  )
    #|)
    #|WHERE
    #|  bytes_sent_diff IS NOT NULL AND
    #|  bytes_received_diff IS NOT NULL AND
    #|  packets_sent_diff IS NOT NULL AND
    #|  packets_received_diff IS NOT NULL
    #|ORDER BY time_bucket ASC;
  let html =
    $|<!DOCTYPE html>
    $|<html lang="ja">
    $|<head>
    $|  <meta charset="UTF-8" />
    $|  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    $|  <title>\{title}</title>
    $|  <style>
    $|    * { box-sizing: border-box; }
    $|    body { font-family: Arial, sans-serif; margin: 20px; padding: 20px; color: #333; }
    $|    .container { max-width: 1400px; }
    $|    h1 { margin: 0 0 10px; }
    $|    .section { padding: 0; margin-bottom: 15px; border: none; }
    $|    .section h2 { margin: 0 0 10px; font-size: 1.1em; }
    $|    .button-row { display: block; margin-bottom: 10px; }
    $|    button { padding: 8px 12px; font-size: 14px; border: 1px solid #ddd; border-radius: 4px; cursor: pointer; background: #f2f2f2; color: #333; margin-right: 6px; margin-bottom: 6px; }
    $|    button:disabled { opacity: 0.5; cursor: not-allowed; }
    $|    #sql-input { width: 100%; height: 120px; font-family: Consolas, 'Courier New', monospace; font-size: 14px; padding: 10px; border: 1px solid #ddd; border-radius: 4px; resize: vertical; }
    $|    #sql-input:focus { outline: none; border-color: #666; }
    $|    #status { margin-bottom: 5px; font-weight: bold; }
    $|    #row-count { display: inline-block; margin-bottom: 15px; }
    $|    #result { overflow-x: auto; margin-top: 20px; }
    $|    .result-table { border-collapse: collapse; border: 2px solid #ddd; table-layout: auto; width: auto; font-size: 14px; }
    $|    .result-table th, .result-table td { padding: 8px 12px; text-align: left; white-space: nowrap; border: 1px solid #ddd; }
    $|    .result-table th { background-color: #f2f2f2; font-weight: bold; border-bottom: 2px solid #ddd; }
    $|    .result-table tr:hover { background-color: #f5f5f5; }
    $|    .result-table tr:nth-child(even) { background-color: #f9f9f9; }
    $|    .result-table .null { color: #999; font-style: italic; }
    $|    .error { color: #cc3333; padding: 15px; background: #fff0f0; border-radius: 4px; }
    $|    .notice { color: #666; font-style: italic; margin-top: 10px; }
    $|    .loading { opacity: 0.5; }
    $|    .license-notice { font-size: 12px; color: #666; margin-top: 20px; }
    $|    @media (max-width: 768px) { body { padding: 10px; } button { width: 100%; } }
    $|  </style>
    $|</head>
    $|<body>
    $|  <div class="container">
    $|    <h1>\{title}</h1>
    $|    <h2>GitHub: <a href="https://github.com/f4ah6o/duckdb_wasm_parquet.mbt">https://github.com/f4ah6o/duckdb_wasm_parquet.mbt</a></h2>
    $|    <div class="section">
    $|      <h2>Status</h2>
    $|      <div id="status">Ready. Click Fetch Parquet.</div>
    $|      <div id="row-count"></div>
    $|    </div>
    $|    <div class="section">
    $|      <h2>Data Management</h2>
    $|      <div class="button-row">
    $|        <button class="btn-primary" hx-get="/api/load" hx-target="#result" hx-swap="innerHTML">Fetch Parquet</button>
    $|        <button class="btn-danger" hx-get="/api/purge" hx-target="#result" hx-swap="innerHTML">Purge Cache</button>
    $|      </div>
    $|      <p style="font-size: 12px; color: #666;">
    $|        Data source: <code id="parquet-source">\{filename}</code>
    $|      </p>
    $|    </div>
    $|    <div class="section">
    $|      <h2>SQL Query</h2>
    $|      <form hx-get="/api/sql" hx-target="#result" hx-swap="innerHTML">
    $|        <textarea id="sql-input" name="query">\{default_sql}</textarea>
    $|        <div class="button-row" style="margin-top: 15px;">
    $|          <button class="btn-primary" type="submit">Execute Query</button>
    $|        </div>
    $|      </form>
    $|    </div>
    $|    <div class="section">
    $|      <h2>Preset Queries</h2>
    $|      <div class="button-row">
    $|        <button class="btn-preset" hx-get="/api/preset?p=samples" hx-target="#result" hx-swap="innerHTML">Samples (1%)</button>
    $|        <button class="btn-preset" hx-get="/api/preset?p=aggregation" hx-target="#result" hx-swap="innerHTML">Aggregation</button>
    $|        <button class="btn-preset" hx-get="/api/preset?p=describe" hx-target="#result" hx-swap="innerHTML">Describe Table</button>
    $|      </div>
    $|    </div>
    $|    <div class="section">
    $|      <h2>Instant Search</h2>
    $|      <form hx-get="/api/search" hx-target="#result" hx-swap="innerHTML" hx-trigger="keyup changed delay:400ms from:#search-input">
    $|        <input type="text" id="search-input" name="term" placeholder="Search connection_id, channel_id, timestamp, rtc_type..." style="width: 100%; padding: 10px; font-size: 14px; border: 1px solid #ddd; border-radius: 4px;" />
    $|      </form>
    $|    </div>
    $|    <div class="section">
    $|      <h2>Results</h2>
    $|      <div id="result">
    $|        <p style="color: #666;">Query results will appear here.</p>
    $|      </div>
    $|    </div>
    $|    <div class="license-notice">
    $|      <strong>License:</strong><br />
    $|      Code: Apache-2.0<br />
    $|      Parquet Data:
    $|      <a id="parquet-data-link" href="\{source}">\{filename}</a>
    $|      by <a href="https://github.com/voluntas">@voluntas</a><br />
    $|      License:
    $|      <a href="https://creativecommons.org/licenses/by-nc-nd/4.0/">CC BY-NC-ND 4.0</a>
    $|      (no changes)
    $|    </div>
    $|  </div>
    $|  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
    $|</body>
    $|</html>
  html
}
