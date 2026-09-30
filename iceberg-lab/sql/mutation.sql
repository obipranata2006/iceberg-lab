USE demo;

-- Langkah 8: INSERT
INSERT INTO undiknas.student_activity VALUES ('S20001','Student Mutation','Teknologi Informasi',5,'Praktikum',DATE '2026-09-21',88.0);
SELECT COUNT(*) FROM undiknas.student_activity;
SELECT snapshot_id, parent_id, committed_at, operation FROM undiknas.student_activity.snapshots ORDER BY committed_at;

-- Langkah 9: UPDATE
UPDATE undiknas.student_activity SET score = 99.0 WHERE student_id = 'S20001';
SELECT student_id, score FROM undiknas.student_activity WHERE student_id = 'S20001';
SELECT snapshot_id, parent_id, committed_at, operation FROM undiknas.student_activity.snapshots ORDER BY committed_at;

-- Langkah 10: DELETE
DELETE FROM undiknas.student_activity WHERE student_id = 'S20001';
SELECT * FROM undiknas.student_activity WHERE student_id = 'S20001';
SELECT snapshot_id, parent_id, committed_at, operation FROM undiknas.student_activity.snapshots ORDER BY committed_at;