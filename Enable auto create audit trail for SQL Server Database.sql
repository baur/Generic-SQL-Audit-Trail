PRINT 'Starting: Create audit trigger on database for futures tables'

IF EXISTS(
  SELECT *
    FROM sys.triggers
   WHERE name = N'tr_database_audit'
     AND parent_class_desc = N'DATABASE'
)
	DROP TRIGGER tr_database_audit ON DATABASE
GO

CREATE TRIGGER tr_database_audit ON DATABASE 
	FOR CREATE_TABLE
AS
	DECLARE @TableName SYSNAME
	DECLARE @DMLStatement VARCHAR(50)
	SELECT @TableName = EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]','SYSNAME')
	INSERT INTO dbo.AuditTables(TableName) VALUES (@TableName);
	DECLARE @sqlCreateTriggerTemplate VARCHAR(8000)
	SET @sqlCreateTriggerTemplate = 'CREATE TRIGGER tr_audit_$$TableName$$
		ON [$$TableName$$] FOR INSERT, UPDATE, DELETE
		AS
		DECLARE @field INT,
			   @maxfield INT,
			   @char INT,
			   @mask INT,
			   @fieldname VARCHAR(128),
			   @TableName VARCHAR(128),
			   @PKCols VARCHAR(1000),
			   @sql VARCHAR(8000), 
			   @UpdateDate VARCHAR(21),
			   @UserName VARCHAR(128),
			   @Type CHAR(1),
			   @PKSelect VARCHAR(1000)
		SET NOCOUNT ON
		--You will need to change @TableName to match the table to be audited
		SELECT @TableName = ''$$TableName$$''
		-- date and user
		SELECT @UserName = SYSTEM_USER,
			   @UpdateDate = CONVERT(VARCHAR(8), GETDATE(), 112) 
					   + '' '' + CONVERT(VARCHAR(12), GETDATE(), 114)
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
				WHERE object_id = OBJECT_ID(@TableName)
				AND TABLE_NAME = @TableName
				AND ORDINAL_POSITION = @field
				GROUP BY column_id, name
			   
			   IF (SUBSTRING(COLUMNS_UPDATED(), @char, 1) & @mask) > 0
											   OR @Type IN (''I'',''D'')
			   BEGIN
				   SELECT @sql = ''
						INSERT Audit ( Type, 
									   TableName, 
									   PK, 
									   FieldName, 
									   OldValue, 
									   NewValue, 
									   UpdateDate)
						SELECT '''''' + @Type + '''''','''''' 
							   + @TableName + '''''','' + @PKSelect
							   + '','''''' + @fieldname + ''''''''
							   + '',convert(varchar(MAX),d.'' + @fieldname + '')''
							   + '',convert(varchar(MAX),i.'' + @fieldname + '')''
							   + '','''''' + @UpdateDate + ''''''''
							   + '' from #ins i full outer join #del d''
							   + @PKCols
							   + '' where i.'' + @fieldname + '' <> d.'' + @fieldname 
							   + '' or (i.'' + @fieldname + '' is null and  d.''
														+ @fieldname
														+ '' is not null)'' 
							   + '' or (i.'' + @fieldname + '' is not null and  d.'' 
														+ @fieldname
														+ '' is null)'' 
				   EXEC (@sql)
				END
			END
		END'
	DECLARE @sql VARCHAR(8000)
    SET @sql = REPLACE(@sqlCreateTriggerTemplate, '$$TableName$$', @TableName)
	EXEC(@sql)
GO

PRINT 'Finished: Create audit trigger on database for futures tables'
PRINT ''
PRINT 'Finished!'