///|
/// OPFS (Origin Private File System) FFI for DuckDB persistence
///
/// This module provides JavaScript FFI functions for OPFS operations
/// that enable persistent storage of DuckDB databases in the browser.

///|
/// Check if OPFS is supported in the current browser
extern "js" fn js_check_opfs_support(
  on_ok : (Bool) -> Unit,
  on_err : (String) -> Unit,
) -> Unit =
  #|(on_ok, on_err) => {
  #|  const run = async () => {
  #|    try {
  #|      if (!navigator.storage || !navigator.storage.getDirectory) {
  #|        on_ok(false);
  #|        return;
  #|      }
  #|      // Try to actually get the directory to verify it works
  #|      await navigator.storage.getDirectory();
  #|      on_ok(true);
  #|    } catch (e) {
  #|      on_ok(false);
  #|    }
  #|  };
  #|  run().catch((err) => on_err(err.message || String(err)));
  #|}

///|
/// Public function to check OPFS support
pub fn check_opfs_support(on_done~ : (Result[Bool, String]) -> Unit) -> Unit {
  js_check_opfs_support(fn(supported) { on_done(Ok(supported)) }, fn(err) {
    on_done(Err(err))
  })
}

///|
/// Open a DuckDB connection with OPFS backend
/// This uses duckdb-wasm's OPFS Virtual File System for persistence
extern "js" fn js_open_opfs_db(
  path : String,
  on_ok : (@duckdb.Connection) -> Unit,
  on_err : (String) -> Unit,
) -> Unit =
  #|(path, on_ok, on_err) => {
  #|  const toError = (err) => err && err.message ? err.message : String(err);
  #|  const run = async () => {
  #|    if (typeof Worker === "undefined") {
  #|      throw new Error("duckdb-wasm requires Worker support");
  #|    }
  #|    const duckdb = await import("@duckdb/duckdb-wasm");
  #|    const version = duckdb.PACKAGE_VERSION || "1.32.0";
  #|    const base = `https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@${version}/dist/`;
  #|    const duckdb_mvp = `${base}duckdb-mvp.wasm`;
  #|    const duckdb_mvp_worker = `${base}duckdb-browser-mvp.worker.js`;
  #|    const wrapWorker = (innerUrl) => {
  #|      const source = `var _setThrew = function() {};\nimportScripts(${JSON.stringify(innerUrl)});`;
  #|      return URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
  #|    };
  #|    const workerUrl = wrapWorker(duckdb_mvp_worker);
  #|    const MANUAL_BUNDLES = {
  #|      mvp: {
  #|        mainModule: duckdb_mvp,
  #|        mainWorker: workerUrl,
  #|      },
  #|    };
  #|    const bundle = await duckdb.selectBundle(MANUAL_BUNDLES);
  #|    const logger = new duckdb.ConsoleLogger(duckdb.LogLevel.WARNING);
  #|    if (!bundle.mainWorker) {
  #|      throw new Error("duckdb-wasm bundle missing mainWorker");
  #|    }
  #|    const worker = new Worker(bundle.mainWorker);
  #|    URL.revokeObjectURL(workerUrl);
  #|    const db = new duckdb.AsyncDuckDB(logger, worker);
  #|    await db.instantiate(bundle.mainModule, bundle.pthreadWorker);
  #|    const setStorageMode = (mode) => {
  #|      window.__duckdb_storage = mode;
  #|    };
  #|    const setStorageName = (name) => {
  #|      window.__duckdb_storage_name = name;
  #|    };
  #|    const openInMemory = async () => {
  #|      await db.open({ query: { castBigIntToDouble: true } });
  #|      setStorageMode("memory");
  #|      setStorageName(":memory:");
  #|    };
  #|    const openOpfs = async (dbPath) => {
  #|      const opfsPath = dbPath.startsWith("opfs://")
  #|        ? dbPath
  #|        : `opfs://${dbPath}`;
  #|      await db.open({
  #|        path: opfsPath,
  #|        accessMode: 3, // READ_WRITE
  #|        opfs: { fileHandling: "auto" },
  #|        query: { castBigIntToDouble: true },
  #|      });
  #|      setStorageMode("opfs");
  #|      setStorageName(dbPath);
  #|    };
  #|    const shouldRetryOpfs = (msg) =>
  #|      msg.includes("not a valid DuckDB database file") ||
  #|      msg.includes("Access Handles cannot be created") ||
  #|      msg.includes("createSyncAccessHandle");
  #|    const makeAltPath = (basePath) => {
  #|      const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  #|      return basePath.endsWith(".db")
  #|        ? `${basePath.slice(0, -3)}-${suffix}.db`
  #|        : `${basePath}-${suffix}`;
  #|    };
  #|    // Register OPFS file
  #|    if (path && path !== ":memory:") {
  #|      try {
  #|        // Check if OPFS is available
  #|        await navigator.storage.getDirectory();
  #|        await openOpfs(path);
  #|      } catch (opfsErr) {
  #|        const msg = toError(opfsErr);
  #|        if (shouldRetryOpfs(msg)) {
  #|          try {
  #|            // Prefer a new filename to avoid locks on existing handles.
  #|            await openOpfs(makeAltPath(path));
  #|          } catch (retryErr) {
  #|            console.warn("OPFS retry failed, using in-memory database:", retryErr);
  #|            await openInMemory();
  #|          }
  #|        } else {
  #|          console.warn("OPFS not available, using in-memory database:", opfsErr);
  #|          await openInMemory();
  #|        }
  #|      }
  #|    } else {
  #|      await openInMemory();
  #|    }
  #|    const conn = await db.connect();
  #|    on_ok({ kind: "wasm", db, conn, worker });
  #|  };
  #|  run().catch((err) => on_err(toError(err)));
  #|}

///|
/// Open a DuckDB connection with OPFS persistence
pub fn open_opfs_database(
  path : String,
  on_done~ : (Result[@duckdb.Connection, String]) -> Unit,
) -> Unit {
  js_open_opfs_db(path, fn(conn) { on_done(Ok(conn)) }, fn(err) {
    on_done(Err(err))
  })
}

///|
/// Register a URL as a remote file in DuckDB
extern "js" fn js_register_remote_file(
  conn : @duckdb.Connection,
  name : String,
  url : String,
  on_ok : () -> Unit,
  on_err : (String) -> Unit,
) -> Unit =
  #|(conn, name, url, on_ok, on_err) => {
  #|  const run = async () => {
  #|    if (!conn || conn.kind !== "wasm" || !conn.db) {
  #|      throw new Error("Connection must be a WASM connection");
  #|    }
  #|    const duckdb = await import("@duckdb/duckdb-wasm");
  #|    await conn.db.registerFileURL(name, url, duckdb.DuckDBDataProtocol.HTTP, false);
  #|    on_ok();
  #|  };
  #|  run().catch((err) => on_err(err.message || String(err)));
  #|}

///|
/// Register a remote file URL for use in DuckDB queries
pub fn register_remote_file(
  conn : @duckdb.Connection,
  name : String,
  url : String,
  on_done~ : (Result[Unit, String]) -> Unit,
) -> Unit {
  js_register_remote_file(conn, name, url, fn() { on_done(Ok(())) }, fn(err) {
    on_done(Err(err))
  })
}

///|
/// Delete a file from OPFS
extern "js" fn js_delete_opfs_file(
  path : String,
  on_ok : () -> Unit,
  on_err : (String) -> Unit,
) -> Unit =
  #|(path, on_ok, on_err) => {
  #|  const run = async () => {
  #|    const opfsRoot = await navigator.storage.getDirectory();
  #|    try {
  #|      await opfsRoot.removeEntry(path);
  #|    } catch (e) {
  #|      // File might not exist, that's okay
  #|      if (e.name !== 'NotFoundError') {
  #|        throw e;
  #|      }
  #|    }
  #|    on_ok();
  #|  };
  #|  run().catch((err) => on_err(err.message || String(err)));
  #|}

///|
/// Delete a file from OPFS storage
pub fn delete_opfs_file(
  path : String,
  on_done~ : (Result[Unit, String]) -> Unit,
) -> Unit {
  js_delete_opfs_file(path, fn() { on_done(Ok(())) }, fn(err) {
    on_done(Err(err))
  })
}

///|
/// List all files in OPFS root directory
extern "js" fn js_list_opfs_files(
  on_ok : (Array[String]) -> Unit,
  on_err : (String) -> Unit,
) -> Unit =
  #|(on_ok, on_err) => {
  #|  const run = async () => {
  #|    const opfsRoot = await navigator.storage.getDirectory();
  #|    const files = [];
  #|    for await (const [name, handle] of opfsRoot.entries()) {
  #|      if (handle.kind === 'file') {
  #|        files.push(name);
  #|      }
  #|    }
  #|    on_ok(files);
  #|  };
  #|  run().catch((err) => on_err(err.message || String(err)));
  #|}

///|
/// List all files in OPFS storage
pub fn list_opfs_files(
  on_done~ : (Result[Array[String], String]) -> Unit,
) -> Unit {
  js_list_opfs_files(fn(files) { on_done(Ok(files)) }, fn(err) {
    on_done(Err(err))
  })
}
