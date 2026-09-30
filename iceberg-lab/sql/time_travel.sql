USE demo;

-- Kondisi sekarang (S20001 tidak ditemukan)
SELECT * FROM undiknas.student_activity WHERE student_id = 'S20001';

-- Kondisi lama, sebelum DELETE (S20001 masih ada)
SELECT * FROM undiknas.student_activity VERSION AS OF 2243523771466558878 WHERE student_id = 'S20001';