/* Loads the CSV files from /data.
   Change @path to the folder where you saved the CSVs. The SQL Server
   service account needs read access to that folder.
   Empty fields load as NULL. */

USE OTC_Portfolio;
GO
DECLARE @path NVARCHAR(400) = N'C:\otc-dashboard\data\';
DECLARE @sql  NVARCHAR(MAX) = N'';

-- Parents first so the foreign keys are satisfied
SELECT @sql += N'BULK INSERT otc.' + t + N' FROM ''' + @path + t + N'.csv'' '
            + N'WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'');' + CHAR(10)
FROM (VALUES (1,'KNA1'),(2,'CUSTOMER_CREDIT'),(3,'MARA'),(4,'VBAK'),(5,'VBAP'),
             (6,'VBEP'),(7,'LIKP'),(8,'LIPS'),(9,'VBRK'),(10,'VBRP')) v(seq, t)
ORDER BY seq;

EXEC sp_executesql @sql;
GO

-- Make sure blank flags are NULL, since the views test for IS NULL
UPDATE otc.VBAK SET LIFSK = NULLIF(LIFSK, ''), FAKSK = NULLIF(FAKSK, ''), CMGST = NULLIF(CMGST, '');
UPDATE otc.VBAP SET ABGRU = NULLIF(ABGRU, '');
UPDATE otc.VBRK SET FKSTO = NULLIF(FKSTO, ''), SFAKN = NULLIF(SFAKN, '');
GO

-- Row count check. Expected counts are in docs/test_cases.md (TC-01).
SELECT 'KNA1' AS tbl, COUNT(*) AS row_count FROM otc.KNA1 UNION ALL
SELECT 'CUSTOMER_CREDIT', COUNT(*) FROM otc.CUSTOMER_CREDIT UNION ALL
SELECT 'MARA', COUNT(*) FROM otc.MARA UNION ALL
SELECT 'VBAK', COUNT(*) FROM otc.VBAK UNION ALL
SELECT 'VBAP', COUNT(*) FROM otc.VBAP UNION ALL
SELECT 'VBEP', COUNT(*) FROM otc.VBEP UNION ALL
SELECT 'LIKP', COUNT(*) FROM otc.LIKP UNION ALL
SELECT 'LIPS', COUNT(*) FROM otc.LIPS UNION ALL
SELECT 'VBRK', COUNT(*) FROM otc.VBRK UNION ALL
SELECT 'VBRP', COUNT(*) FROM otc.VBRP;
GO
