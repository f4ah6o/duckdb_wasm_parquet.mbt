# DuckDB-Wasm (OPFS) + Parquet with MoonBit

## 概要

- [@voluntas](https://github.com/voluntas)さんによる[DuckDB-Wasm (OPFS) + Parquet + S3-compatible object storage](https://github.com/voluntas/duckdb-wasm-parquet)のMoonBit移植版です。
  - アップストリームのソースコードはApache-2.0ライセンスであり、著作権は @voluntasさんに帰属します。

MoonBit移植版のライセンスもApache-2.0ライセンスです。

### アプリについて

- > DuckDB-Wasm をブラウザで使用して、 OPFS に DuckDB データベースファイルを作成し、 S3 互換オブジェクトストレージにある Parquet ファイルを読み込んで DuckDB-Wasm に登録し、 DuckDB-Wasm で SQL でクエリを実行するお試し用のアプリです。
- see [original README](https://github.com/voluntas/duckdb-wasm-parquet/tree/main?tab=readme-ov-file#%E6%A6%82%E8%A6%81)

### このリポジトリのアプリについて

アプリの実行形式は以下の通りです。オリジナルの趣旨とは外れますが[MoonBit DuckDB Client API](https://github.com/f4ah6o/duckdb.mbt)の動作確認を兼ねています。
1. オリジナルの通りDuckDB-Wasmを使用したブラウザ側動作
2. DuckDB node-apiを使用したサーバー側動作
3. DuckDB C APIを使用したネイティブサーバー動作

## Parquetファイルのライセンス

- 利用したParquetファイル: `P78BHZM3MD3MV47JDZG47PB8PW.parquet`
  - 作成者: [@voluntas](https://github.com/voluntas)
  - 出典: <https://duckdb-wasm.shiguredo.jp/P78BHZM3MD3MV47JDZG47PB8PW.parquet>
  - ライセンス: [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)
  - 改変: なし
  - ライセンスに基づきCloudflare R2に保存しています。
- see [Parquetファイルについて](https://github.com/voluntas/duckdb-wasm-parquet/tree/main#parquet-%E3%83%95%E3%82%A1%E3%82%A4%E3%83%AB%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6).

## 環境変数

- `VITE_PARQUET_URL`: 読み込む Parquet ファイルの URL（未設定時は公開URL）
- `PARQUET_URL`: Node サーバー / Native サーバーが `read_parquet()` で読む URL（未設定時は公開URL）
- `PORT`: Node サーバー / Native サーバーのポート（未設定時は `8788`）
  - 公開URL: <https://duckdb-wasm-mbt.f12o.com/P78BHZM3MD3MV47JDZG47PB8PW.parquet>

## ターゲット構成

1. **SPA (DuckDB-WASM)**: `index.html` + `cmd/main`
2. **Node サーバー (DuckDB Node API)**: `cmd/server` + duckdb node API
3. **Native サーバー (DuckDB C API)**: `cmd/native_server` + duckdb native bindings

## ローカル実行

### SPA

```
pnpm dev
```

### Node サーバー

```
pnpm add @duckdb/node-api
moon build --target js
node target/js/release/build/cmd/server/main.js
```

### Native サーバー (DuckDB C API)

```
moon run cmd/native_server --target native
```

DuckDB C API（libduckdb）のインストールが必要です。  
Linux で動的ライブラリが見つからない場合は `LD_LIBRARY_PATH=/usr/local/lib` を付けて実行してください。  
ARM Mac (Homebrew) は `/opt/homebrew/lib` が想定パスです。

```
pnpm start:native
```
