USE demo;
CREATE NAMESPACE IF NOT EXISTS undiknas;
CREATE TABLE undiknas.student_activity (student_id STRING, student_name STRING, program STRING, semester INT, activity_type STRING, activity_date DATE, score DOUBLE) USING iceberg PARTITIONED BY (days(activity_date));
SHOW TABLES IN undiknas;
DESCRIBE TABLE undiknas.student_activity;