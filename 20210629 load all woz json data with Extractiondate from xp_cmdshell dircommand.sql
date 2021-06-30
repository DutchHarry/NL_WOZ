USE [WOZ]
GO

-- Create the extracts table
DROP TABLE IF EXISTS [tbl_WOZ_data_extract_E];
GO
CREATE TABLE [tbl_WOZ_data_extract_E](
	[hID] [int] IDENTITY(1,1) NOT NULL,
	[StringLength]  AS (len([data])) PERSISTED,
	[StringHash]  AS (CONVERT([varchar](32),hashbytes('MD5',[data]),(2))) PERSISTED,
  [ExtractionFileDate] datetime NULL,
  [ExtractionFileName] varchar(255) NULL,
  [ExtractionDate] datetime NULL,
	[wobj_bag_obj_id] [varchar](20) NULL,
	[bag_id_type] [varchar](20) NULL,
	[totalFeatures]  AS (json_value([data],'$[0].totalFeatures')) PERSISTED,
	[data] [nvarchar](max) NULL
);
GO

-- create import view
CREATE OR ALTER   VIEW [Vw_WOZ_data_extract_E] AS 
SELECT
  [ExtractionFileDate]
, [ExtractionFileName]
, [ExtractionDate]
, [wobj_bag_obj_id]
, [data]
FROM [tbl_WOZ_data_extract_E];
GO


-- import json files
DECLARE @ExtractionFileName varchar(255) = ''--'S:\_ue\WOZ\VBO1_DATA_1.json';
DECLARE @ExtractionFileDate varchar(255) = ''
DECLARE @filedir varchar(1000) = 'D:\NLDATA\WOZjson\20210626newwoz\';  --<-- CHANGE!!!
DECLARE @ExtractionFileDirectory varchar(255) = @filedir 
DECLARE @tablename varchar(1000) = 'Vw_WOZ_data_extract_E';
DECLARE @featurecount int = 0; --for iterating features
DECLARE @featurestring varchar(5) = CONVERT(VARCHAR(5),@featurecount);
DECLARE @maxfeatures int = 0; 
DECLARE @minfeatures int = 0; 
DECLARE @sql nvarchar(max) ='';
DECLARE @debug varchar(5) = 'Y'; --Y,I,N
DECLARE @quote varchar(5)= '''';
DECLARE @crlf varchar(5) = CHAR(13)+CHAR(10);
DECLARE @msg varchar(8000) = ''
DECLARE @doscommand varchar(8000);
DECLARE @result int; 


SELECT @ExtractionFileDate = FORMAT(GETDATE(), 'dd-MMM-yyyy HH:mm:ss');
	IF @debug = 'Y' 
    SET @msg = @ExtractionFileDate
		BEGIN
		IF LEN(@msg) > 2047
			PRINT @msg;
		ELSE
			RAISERROR (@msg, 0, 1) WITH NOWAIT; 
		END;

-- BEGIN get dir into table
DROP TABLE IF EXISTS #CommandShell;
CREATE TABLE #CommandShell ( Line VARCHAR(512));
SET @doscommand = 'dir "'+@filedir+ '" /TC';
--PRINT @doscommand;
INSERT INTO #CommandShell
EXEC @result = MASTER..xp_cmdshell   @doscommand ;
IF (@result = 0)  
   PRINT 'Success'  
ELSE  
   PRINT 'Failure'  
;
DELETE
FROM   #CommandShell
WHERE  Line NOT LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9] %'
OR Line LIKE '%<DIR>%'
OR Line is null
;
-- END get dir into table

DECLARE woz_json_file CURSOR 
  FAST_FORWARD
  FOR 
  SELECT
    ExtractionFileDate = FORMAT(CONVERT(DATETIME2,LEFT(Line,17)+':00',103), 'dd-MMM-yyyy HH:mm:ss')
  , ExtractionFileName = REVERSE( LEFT(REVERSE(Line),CHARINDEX(' ',REVERSE(line))-1 ) )
  FROM #CommandShell
  ORDER BY 
    ExtractionFileName
OPEN woz_json_file  
FETCH NEXT FROM woz_json_file
INTO @ExtractionFileDate, @ExtractionFileName; 
WHILE @@FETCH_STATUS = 0  
BEGIN  
  SET @featurecount = 0;
  PRINT @ExtractionFileName;
	IF @debug = 'Y' 
    SET @msg = @ExtractionFileDate
		BEGIN
		IF LEN(@msg) > 2047
			PRINT @msg;
		ELSE
			RAISERROR (@msg, 0, 1) WITH NOWAIT; 
		END;

  --BEGIN DO SOMETHING WITHIN CURSOR

	--BEGIN JSON FILE PROCESSING
SET @sql = '
INSERT INTO ['+@tablename+']
SELECT 
      '+@quote+@ExtractionFileDate+@quote+'
    , '+@quote+@ExtractionFileName+@quote+'
	, woz.*
	FROM OPENROWSET (BULK '+@quote+@ExtractionFileDirectory+@ExtractionFileName+@quote+', SINGLE_CLOB) as j
	CROSS APPLY OPENJSON(BulkColumn )
	WITH( 
	  ExtractionDate varchar(8000) '+@quote+'$.ExtractionDate'+@quote+'
	, wobj_bag_obj_id1 varchar(8000) '+@quote+'$.wobj_bag_obj_id'+@quote+'
	, [data] nvarchar(max) AS JSON
) AS woz
WHERE 1=1
;
'
IF @debug = 'Y' 
		  BEGIN
      SET @msg = @sql
			IF LEN(@msg) > 2047
			  PRINT @msg;
			ELSE
			  RAISERROR (@msg, 0, 1) WITH NOWAIT; 
		  END;
		EXEC (@sql);

	--END JSON FILE PROCESSING

  --END   DO SOMETHING WITHIN CURSOR
  FETCH NEXT FROM woz_json_file   
    INTO @ExtractionFileDate, @ExtractionFileName;
END   
CLOSE woz_json_file;  
DEALLOCATE woz_json_file;  

-- drop directory table
DROP TABLE IF EXISTS #CommandShell;
PRINT 'ALL WOZ JSON LOADED';


--update BAG type
UPDATE t1
SET t1.[bag_id_type] = t2.[bag_id_type]
FROM [tbl_WOZ_data_extract_E] t1
INNER JOIN [BAG].[dbo].[VwBAG_id_Current] t2
ON t1.[wobj_bag_obj_id] = t2.[identificatie]
;

-- delete duplcate data, keep last ExtractionDate
;WITH cte0 AS (
SELECT 
RN = ROW_NUMBER() OVER (PARTITION BY [wobj_bag_obj_id], [StringHash] ORDER BY [wobj_bag_obj_id], [StringHash], [ExtractionDate] desc)
, t1.*
FROM [tbl_WOZ_data_extract_E] t1
)
DELETE
FROM cte0
WHERE 1=1
AND RN > 1
;

-- delete based on last ExtractionDate
;WITH cte0 AS (
SELECT 
RN = ROW_NUMBER() OVER (PARTITION BY [wobj_bag_obj_id] ORDER BY [wobj_bag_obj_id], [ExtractionDate] desc)
, t1.*
FROM [tbl_WOZ_data_extract_E] t1
)
DELETE
FROM cte0
WHERE 1=1
AND RN > 1
;

