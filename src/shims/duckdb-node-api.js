export class DuckDBInstance {
  static async create() {
    throw new Error(
      'DuckDB Node API is not available in the browser. Use the WASM backend.'
    );
  }
}
