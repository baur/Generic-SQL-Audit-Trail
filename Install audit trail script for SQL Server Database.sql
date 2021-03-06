-- The MIT License (MIT)
-- 
-- Copyright (c) 2015 Philip Doxakis
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
/*
Script Name:
    Install audit trail script for SQL Server Database
Author:
    Philip Doxakis
Customize:
	You can exclude tables in the script.
	Follow comments in the script: "Specify table to exclude here:"
Description:
	Install a complete audit trail on selected database.
	Optional: Add "USE [DatabaseName];" at the top of the script.
Step:
	- Remove all triggers starting with "tr_audit_"
	- Add "Audit" table if not found on the database
	- Add triggers for almost all tables (this can be customized).
	- Add or replace the database trigger tr_database_audit (for adding audit trigger on new tables)
Limitations:
	- Audit table is "Audit"
	- Audit trigger start with "tr_audit_"
	- The database trigger is "tr_database_audit"
	- Do not support datatype: image
	- Extra step required when changing table name.
		- Run the uninstall script
		- Change the table name
		- Run the install script
	(Based on https://msdn.microsoft.com/en-us/library/ms187928.aspx)
*/
USE BILLING
GO

DECLARE @DatabaseName VARCHAR(255);

SELECT @DatabaseName = TABLE_CATALOG
FROM information_schema.columns

PRINT 'Starting script...'
PRINT ''
PRINT 'Environnement:'
PRINT ' Server:'
PRINT '  ' + CAST(SERVERPROPERTY('ServerName') AS VARCHAR(255))
PRINT ' Edition:'
PRINT '  ' + CAST(SERVERPROPERTY('Edition') AS VARCHAR(255))
PRINT ' Database name:'
PRINT '  ' + @DatabaseName
PRINT ''
PRINT 'Starting: Removing all triggers starting with tr_audit_'

DECLARE @TriggerName VARCHAR(255);

DECLARE MY_CURSOR_FOR_TRIGGER CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY
FOR
-- Get list of trigger in current database
SELECT sysobjects.NAME AS trigger_name
FROM sysobjects
WHERE sysobjects.type = 'TR'
	AND sysobjects.NAME LIKE 'tr_audit_%'

OPEN MY_CURSOR_FOR_TRIGGER

FETCH NEXT
FROM MY_CURSOR_FOR_TRIGGER
INTO @TriggerName

WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @sql VARCHAR(250)

	-- Remove current trigger
	SET @sql = 'DROP TRIGGER ' + @TriggerName

	PRINT 'Removing trigger: ' + @TriggerName

	EXEC (@sql)

	FETCH NEXT
	FROM MY_CURSOR_FOR_TRIGGER
	INTO @TriggerName
END

CLOSE MY_CURSOR_FOR_TRIGGER

DEALLOCATE MY_CURSOR_FOR_TRIGGER

PRINT 'Finished: Removing all triggers starting with tr_audit_'
PRINT ''
PRINT 'Starting: Make sure Audit table exists'

IF NOT EXISTS (
		SELECT *
		FROM sysobjects
		WHERE id = OBJECT_ID(N'[dbo].[Audit]')
		)
BEGIN
	PRINT 'Adding Audit table in the database'

	CREATE TABLE Audit (
	    ID int IDENTITY(1,1) NOT NULL
		,[Type] CHAR(1)
		,TableSchema VARCHAR(128)
		,TableName VARCHAR(128)
		,PK VARCHAR(1000)
		,FieldName VARCHAR(128)
		,OldValue VARCHAR(MAX)
		,NewValue VARCHAR(MAX)
		,UpdateDate DATETIME
		,UserName VARCHAR(128)
		,ApplicationName varchar(500) 
		)		
END
GO

PRINT 'Finished: Make sure Audit table exists'
PRINT ''
PRINT 'Starting: Make sure AuditTables table exists'

IF NOT EXISTS (
		SELECT *
		FROM sysobjects
		WHERE id = OBJECT_ID(N'[dbo].[AuditTables]')
		)
BEGIN
	PRINT 'Adding AuditTables table in the database'

	CREATE TABLE [dbo].[AuditTables] (
		[TableSchema] [varchar](128) NOT NULL CONSTRAINT [DF_AuditTables_TableSchema] DEFAULT('dbo')
		,[TableName] [varchar](128) NOT NULL
		,[DMLStatement] [varchar](50) NOT NULL CONSTRAINT [DF_AuditTables_DMLStatement] DEFAULT('*')
		,[FieldName] [varchar](1000) NOT NULL CONSTRAINT [DF_AuditTables_FieldName] DEFAULT('*')
		,CONSTRAINT [PK_AuditTables] PRIMARY KEY CLUSTERED (
			[TableSchema] ASC
		   ,[TableName] ASC) 
		) ON [PRIMARY]
END
GO

PRINT 'Finished: Make sure AuditTables table exists'
PRINT ''

DECLARE @sqlCreateTriggerTemplate VARCHAR(8000)

SET @sqlCreateTriggerTemplate = 
	'CREATE TRIGGER tr_audit_$$TableName$$
	ON [$$TableSchema$$].[$$TableName$$] FOR $$DMLStatement$$
	AS
	DECLARE @field INT,
		   @maxfield INT,
		   @char INT,
		   @mask INT,
		   @fieldname VARCHAR(128),
		   @FieldNameList VARCHAR(1000),
		   @TableName VARCHAR(128),
		   @TableSchema VARCHAR(128),
		   @PKCols VARCHAR(1000),
		   @sql VARCHAR(8000), 
		   @UpdateDate VARCHAR(21),
		   @UserName VARCHAR(128),
		   @Type CHAR(1),
		   @PKSelect VARCHAR(1000);
	SET NOCOUNT ON
	--You will need to change @TableName to match the table to be audited
	SELECT @TableName = ''$$TableName$$''
	-- date and user
	SELECT @UserName = SYSTEM_USER,
		   @UpdateDate = CONVERT(VARCHAR(8), GETDATE(), 112) 
				   + '' '' + CONVERT(VARCHAR(12), GETDATE(), 114),
		   @TableSchema = ''$$TableSchema$$'', @FieldNameList=''$$FieldNameList$$''
	-- Action
	IF EXISTS (SELECT * FROM inserted)
		   IF EXISTS (SELECT * FROM deleted)
				   SELECT @Type = ''U''
		   ELSE
				   SELECT @Type = ''I''
	ELSE
		   SELECT @Type = ''D''
	-- get list of columns
	SELECT * INTO #ins FROM inserted
	SELECT * INTO #del FROM deleted
	-- Get primary key columns for full outer join
	SELECT @PKCols = COALESCE(@PKCols + '' and'', '' on'') 
				   + '' i.'' + c.COLUMN_NAME + '' = d.'' + c.COLUMN_NAME
		   FROM    INFORMATION_SCHEMA.TABLE_CONSTRAINTS pk ,
				  INFORMATION_SCHEMA.KEY_COLUMN_USAGE c
		   WHERE   pk.TABLE_NAME = @TableName
		   AND     CONSTRAINT_TYPE = ''PRIMARY KEY''
		   AND     c.TABLE_NAME = pk.TABLE_NAME
		   AND     c.CONSTRAINT_NAME = pk.CONSTRAINT_NAME
	-- Get primary key select for insert
	SELECT @PKSelect = COALESCE(@PKSelect+''+'','''') 
		   + ''''''<'' + COLUMN_NAME 
		   + ''=''''+convert(varchar(100),
	coalesce(i.'' + COLUMN_NAME +'',d.'' + COLUMN_NAME + ''))+''''>'''''' 
		   FROM    INFORMATION_SCHEMA.TABLE_CONSTRAINTS pk ,
				   INFORMATION_SCHEMA.KEY_COLUMN_USAGE c
		   WHERE   pk.TABLE_NAME = @TableName
		   AND     CONSTRAINT_TYPE = ''PRIMARY KEY''
		   AND     c.TABLE_NAME = pk.TABLE_NAME
		   AND     c.CONSTRAINT_NAME = pk.CONSTRAINT_NAME
	IF @PKCols IS NULL
	BEGIN
		   RAISERROR(''no PK on table %s'', 16, -1, @TableName)
		   RETURN
	END
	SELECT @field = 0, 
		   @maxfield = MAX(ORDINAL_POSITION) 
		FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @TableName
	WHILE @field < @maxfield
	BEGIN
		SELECT @field = MIN(ORDINAL_POSITION) 
			   FROM INFORMATION_SCHEMA.COLUMNS 
			   WHERE TABLE_NAME = @TableName 
			   AND ORDINAL_POSITION > @field
        IF @field IS NOT NULL
        BEGIN
		    SELECT
				@field = MIN(ORDINAL_POSITION),
				@char = (column_id - 1) / 8 + 1,
				@mask = POWER(2, (column_id - 1) % 8),
				@fieldname = name
			FROM SYS.COLUMNS SC
			INNER JOIN INFORMATION_SCHEMA.COLUMNS ISC
			ON SC.name = ISC.COLUMN_NAME
			WHERE object_id = OBJECT_ID(@TableSchema+''.''+@TableName)
			AND TABLE_NAME = @TableName
			AND ORDINAL_POSITION = @field
			GROUP BY column_id, name
		   
		   IF (SUBSTRING(COLUMNS_UPDATED(), @char, 1) & @mask) > 0
										   OR @Type IN (''I'',''D'')
		   BEGIN
			   SELECT @sql = ''
					INSERT Audit ( Type, 
								   TableSchema,
								   TableName, 
								   PK, 
								   FieldName, 
								   OldValue, 
								   NewValue, 
								   UpdateDate, 
								   UserName,
								   ApplicationName)
					SELECT '''''' + @Type + '''''','''''' 
					       + @TableSchema + '''''','''''' 
						   + @TableName + '''''','' + @PKSelect
						   + '','''''' + @fieldname + ''''''''
						   + '',convert(varchar(MAX),d.'' + @fieldname + '')''
						   + '',convert(varchar(MAX),i.'' + @fieldname + '')''
						   + '','''''' + @UpdateDate + ''''''''
						   + '','''''' + @UserName + ''''''''
						   + '','''''' + REPLACE(APP_NAME(), '''''''','''''''''''') + ''''''''
						   + '' from #ins i full outer join #del d''
						   + @PKCols
						   + '' where i.'' + @fieldname + '' <> d.'' + @fieldname 
						   + '' or (i.'' + @fieldname + '' is null and  d.''
													+ @fieldname
													+ '' is not null)'' 
						   + '' or (i.'' + @fieldname + '' is not null and  d.'' 
													+ @fieldname
													+ '' is null)'' 
			   IF @FieldName <> ''ID'' AND ((@FieldNameList = ''*'') or (CHARINDEX(@fieldname, @FieldNameList)<>0))
			   EXEC (@sql)
			END
		END
	END'

PRINT 'Starting: Create audit trigger for all tables'

DECLARE @TableSchema VARCHAR(255);
DECLARE @TableName VARCHAR(255);
DECLARE @DMLStatement VARCHAR(50);
DECLARE @FieldNameList VARCHAR(1000);
DECLARE MY_CURSOR_FOR_TABLE CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY
FOR
SELECT DISTINCT TABLE_SCHEMA
	,TABLE_NAME
FROM information_schema.columns
WHERE OBJECTPROPERTY(OBJECT_ID(TABLE_CATALOG + '.' + TABLE_SCHEMA + '.' + TABLE_NAME), 'IsView') = 0

OPEN MY_CURSOR_FOR_TABLE

FETCH NEXT
FROM MY_CURSOR_FOR_TABLE
INTO @TableSchema
	,@TableName

WHILE @@FETCH_STATUS = 0
BEGIN
	IF @TableName != 'Audit' -- Table used by audit trigger
		AND LEFT(@TableName, 7) <> 'aspnet_'
		AND LEFT(@TableName, 9) <> 'webpages_'
		-- Specify table to exclude here:
		-- Copy paste line bellow to specify table to exclude more table:
		AND EXISTS (
			SELECT TableName
			FROM dbo.AuditTables
			WHERE TableName = @TableName
				AND TableSchema = @TableSchema
			)
	BEGIN
		PRINT 'Adding trigger for table: ' + @TableSchema + '.' + @TableName

		DECLARE @sql VARCHAR(8000)


				SELECT @DMLStatement = CASE 
						WHEN DMLStatement = '*'
							THEN 'INSERT, UPDATE, DELETE'
						ELSE DMLStatement
						END,
						@FieldNameList = FieldName
				FROM dbo.AuditTables
				WHERE TableName = @TableName and TableSchema = @TableSchema;

		SET @sql = REPLACE(@sqlCreateTriggerTemplate, '$$TableName$$', @TableName)
		SET @sql = REPLACE(@sql, '$$TableSchema$$', @TableSchema)
		SET @sql = REPLACE(@sql, '$$DMLStatement$$', @DMLStatement)
		SET @sql = REPLACE(@sql, '$$FieldNameList$$', @FieldNameList)

		EXEC (@sql)
	END
	ELSE
	BEGIN
		PRINT 'Trigger not added for table: ' + @TableSchema + '.' + @TableName
	END

	FETCH NEXT
	FROM MY_CURSOR_FOR_TABLE
	INTO @TableSchema
		,@TableName
END

CLOSE MY_CURSOR_FOR_TABLE

DEALLOCATE MY_CURSOR_FOR_TABLE

PRINT 'Finished: Create audit trigger for all tables'
PRINT ''
PRINT 'Finished!'