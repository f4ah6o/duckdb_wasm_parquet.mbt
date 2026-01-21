///|
/// Shared SQL definitions for the Parquet viewer.

///|
/// The table name used for loaded parquet data.
pub let table_name : String = "stats"

///|
/// Build SQL for preset queries.
pub fn preset_sql(preset : String) -> String {
  match preset {
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
}

///|
/// Build SQL for search query.
pub fn search_sql(search_term : String) -> String {
  let escaped_term = escape_sql_string(search_term)
  "SELECT timestamp, connection_id, rtc_type FROM " +
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
}

///|
/// SQL for row count.
pub fn count_sql() -> String {
  "SELECT COUNT(*) as cnt FROM " + table_name
}

///|
/// Escape SQL string to prevent injection.
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
