# Mini Data Lakehouse: MinIO + Iceberg + REST Catalog + Spark

**Nama:** I Made Obi Pranata

**NIM:** 42430003

**Program Studi:** Teknologi Informasi

---

Praktikum membangun versi kecil arsitektur Data Lakehouse: file Parquet di MinIO dikelola sebagai tabel Apache Iceberg (dengan metadata, snapshot, dan time travel) dan di-query lewat Spark.

```
Spark SQL -> Iceberg + REST Catalog -> metadata + snapshot + manifest -> MinIO -> file Parquet
```

## Cara Menjalankan
1. `docker compose up -d`
2. Cek service: `docker compose ps`
3. Masuk Spark SQL: `docker exec -it spark-iceberg spark-sql`
4. Jalankan query di folder `sql/` sesuai urutan (`create_table.sql`, `mutation.sql`, `time_travel.sql`).

Evidence: `evidence/docker-compose-ps.png`

## Catatan Penyesuaian
- Image `iceberg-rest` dipin ke `apache/iceberg-rest-fixture:1.9.2`. Versi terbaru menolak query metadata table (`.snapshots`) dengan error "Suspicious Path Character".
- Alias network `rest` ditambahkan pada service `iceberg-rest` agar Spark dapat menemukan catalog.
- MinIO Console tidak dapat dibuka, sehingga file fisik diperiksa lewat `mc ls`.
- Data awal 10.000 record dibuat dengan `INSERT ... SELECT ... FROM range(10000)` di Spark SQL. Hasilnya sama dengan `writeTo().append()` (satu snapshot `append`). Kode PySpark dari modul disimpan di `notebooks/bulk_write.ipynb`.
- Catalog ini menyimpan isinya di memori, sehingga tabel perlu dibuat ulang setelah container `iceberg-rest` dibuat ulang.

## Snapshot Lineage
| State | Operasi | Snapshot ID | Parent ID | Operation | Row Count |
|---|---|---|---|---|---|
| S1 | Bulk write | 7479782201853189333 | NULL | append | 10000 |
| S2 | INSERT | 3509643241966980260 | 7479782201853189333 | append | 10001 |
| S3 | UPDATE | 2243523771466558878 | 3509643241966980260 | overwrite | 10001 |
| S4 | DELETE | 8338453376377512835 | 2243523771466558878 | delete | 10000 |
| - | 20 append kecil | 20 snapshot append | 8338453376377512835 (rantai) | append | 11000 |
| S5 | Compaction | 2402329208524984463 | 2200583229409775962 | replace | 11000 |

```
S1 --> S2 --> S3 --> S4 --> (20 append kecil) --> S5
bulk   insert  update  delete                      rewrite
```

## Pengamatan INSERT / UPDATE / DELETE
- **INSERT** (`S20001`, score 88.0): row count naik 10000 menjadi 10001 dan terbentuk snapshot baru dengan parent S1.
- **UPDATE** (score menjadi 99.0): row count tetap 10001, tetapi isi berubah. Terbentuk snapshot baru dengan operation `overwrite`.
- **DELETE**: `S20001` tidak ditemukan di current state dan row count kembali 10000. Terbentuk snapshot baru dengan operation `delete`.

Evidence: `evidence/snapshot-history.png`

## Bukti Time Travel
Evidence: `evidence/time-travel.png`

- Current state: `SELECT * ... WHERE student_id = 'S20001'` menghasilkan kosong.
- Snapshot sebelum DELETE: `SELECT * ... VERSION AS OF 2243523771466558878 WHERE student_id = 'S20001'` menampilkan `S20001` dengan score 99.0.

## Struktur File di MinIO
Evidence: `evidence/minio-data-metadata.png`

Kondisi saat Langkah 12 (setelah INSERT, UPDATE, DELETE dan sebelum small files):

| Komponen | Jumlah |
|---|---|
| File Parquet (`data/`) | 23 |
| Metadata JSON | 5 |
| Manifest list (`snap-*.avro`) | 4 |
| Manifest file (`*-m0/m1.avro`) | 5 |

Pengamatan:
- Data dipartisi per hari (`activity_date_day=...`), satu file Parquet per partisi.
- INSERT dan UPDATE masing-masing menulis file Parquet baru.
- DELETE tidak menulis file Parquet baru, hanya metadata baru. File lama tetap ada di storage sehingga time travel bisa membacanya.

## Before vs After Compaction
Setelah 20 append kecil, tabel berisi banyak file kecil, lalu dijalankan `CALL demo.system.rewrite_data_files(...)`.

| Yang dibandingkan | Before | After |
|---|---|---|
| Jumlah data file | 395 (file yang ditulis ulang oleh `CALL`) | 21 |
| Jumlah record | 11000 | 11000 |
| Total size | tidak tercatat | 0.15 MB |
| Hasil query logis (GROUP BY program) | Akuntansi 2029, Hukum 1980, Manajemen 2967, Sistem Informasi 2047, Teknologi Informasi 1977 | sama persis |
| Waktu query uji | 1.484 detik | 0.102 detik |

Catatan: angka 395 diambil dari output `CALL` (jumlah file yang di-rewrite), dan total size sebelum compaction tidak sempat dicatat. Waktu query setelah compaction lebih cepat, tetapi belum tentu karena compaction saja (cache Spark ikut berpengaruh).

## Jawaban Pertanyaan Konsep

**1. Mengapa S3 tetap berbeda dari S2 walaupun jumlah row sama?**
Dari hasil praktikum, S2 dan S3 sama-sama punya 10001 row. Tetapi di S2 score S20001 masih 88.0, sedangkan di S3 sudah 99.0. Jadi `COUNT(*)` hanya memberi tahu berapa banyak data, bukan apa isinya. Saat UPDATE, Iceberg tidak mengubah file lama. Ia menulis file Parquet baru dan membuat snapshot baru (operation `overwrite`) yang parent-nya S2. Itu sebabnya S3 adalah state yang berbeda.

**2. Mengapa S20001 masih terlihat saat membaca snapshot sebelum DELETE?**
Karena DELETE tidak menghapus file dari MinIO. DELETE hanya membuat snapshot baru (S4) yang sudah tidak menyertakan S20001. Snapshot S3 masih menyimpan referensi ke file data dan metadata lama, dan file itu masih ada di storage. Jadi saat saya menjalankan `VERSION AS OF 2243523771466558878`, Iceberg membaca state S3 dan S20001 muncul lagi dengan score 99.0. Snapshot di sini bukan backup terpisah, tetapi bagian dari metadata yang menunjuk ke kumpulan file pada waktu tertentu.

**3. Mengapa compaction dapat mengubah file di storage tanpa mengubah jumlah record?**
Compaction hanya merapikan susunan fisik file. Setelah 20 append kecil, tabel punya banyak file kecil. Compaction menggabungkannya (395 file ditulis ulang menjadi 21 file), tetapi isi datanya tetap sama: jumlah record 11000 dan hasil GROUP BY tidak berubah. Jadi yang berubah physical layout, sedangkan logical state tetap. Iceberg mencatatnya sebagai snapshot `replace`.

## Kesimpulan
Data aktual disimpan sebagai file di Object Storage (MinIO). Apache Iceberg menambahkan lapisan metadata yang mengelola file-file itu sebagai tabel. Setiap perubahan menghasilkan snapshot baru sehingga history dapat dilacak dan dibaca kembali (time travel). Compaction merapikan susunan file tanpa mengubah hasil logis tabel.