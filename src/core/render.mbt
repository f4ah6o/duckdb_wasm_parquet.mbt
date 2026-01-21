///|
/// HTML rendering helpers shared across targets.

///|
/// Render query result as HTML table.
pub fn render_result_table(
  result : @duckdb.QueryResult,
  max_rows? : Int = 1000,
) -> String {
  let buf = StringBuilder::new()
  let row_count = result.row_count()
  let display_rows = if row_count > max_rows { max_rows } else { row_count }
  buf.write_string("<table class=\"result-table\"><thead><tr>")
  for i = 0; i < result.columns.length(); i = i + 1 {
    buf.write_string("<th>")
    buf.write_string(escape_html(result.columns[i]))
    buf.write_string("</th>")
  }
  buf.write_string("</tr></thead><tbody>")
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
  if row_count > max_rows {
    buf.write_string(
      "<p class=\"notice\">Showing " +
      max_rows.to_string() +
      " of " +
      row_count.to_string() +
      " rows</p>",
    )
  }
  buf.to_string()
}

///|
/// Render an error panel.
pub fn render_error(message : String) -> String {
  "<div class=\"error\">" + escape_html(message) + "</div>"
}

///|
/// Escape HTML special characters.
pub fn escape_html(s : String) -> String {
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
