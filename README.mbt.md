# DuckDB-Wasm (OPFS) + Parquet + S3-compatible object storage with MoonBit

## 概要

- [@voluntas](https://github.com/voluntas)さんによる[DuckDB-Wasm (OPFS) + Parquet + S3-compatible object storage](https://github.com/voluntas/duckdb-wasm-parquet)のMoonBit移植版です。
  - アップストリームのソースコードはApache-2.0ライセンスであり、著作権は @voluntasさんに帰属します。

MoonBit移植版のライセンスもApache-2.0ライセンスです。

### アプリについて

- > DuckDB-Wasm をブラウザで使用して、 OPFS に DuckDB データベースファイルを作成し、 S3 互換オブジェクトストレージにある Parquet ファイルを読み込んで DuckDB-Wasm に登録し、 DuckDB-Wasm で SQL でクエリを実行するお試し用のアプリです。
- see [original README](https://github.com/voluntas/duckdb-wasm-parquet/tree/main?tab=readme-ov-file#%E6%A6%82%E8%A6%81)

## Parquetファイルのライセンス

- 利用したParquetファイル: `P78BHZM3MD3MV47JDZG47PB8PW.parquet`
  - 作成者: [@voluntas](https://github.com/voluntas)
  - 出典: <https://duckdb-wasm.shiguredo.jp/P78BHZM3MD3MV47JDZG47PB8PW.parquet>
  - ライセンス: [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)
  - 改変: なし
  - ライセンスに基づきCloudflare R2に保存しています。
- see [Parquetファイルについて](https://github.com/voluntas/duckdb-wasm-parquet/tree/main#parquet-%E3%83%95%E3%82%A1%E3%82%A4%E3%83%AB%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6).

## 環境変数

- `VITE_PARQUET_URL`: 読み込む Parquet ファイルの URL
