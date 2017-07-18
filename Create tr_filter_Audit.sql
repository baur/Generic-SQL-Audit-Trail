SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER TRIGGER [dbo].[tr_filter_Audit]
ON [dbo].[Audit]
INSTEAD OF INSERT
AS 
BEGIN
INSERT INTO [dbo].[Audit]
           ([Type]
		   ,[TableSchema]
           ,[TableName]
           ,[PK]
           ,[FieldName]
           ,[OldValue]
           ,[NewValue]
           ,[UpdateDate]
		   ,[UserName]
		   )
     SELECT 
            I.[Type]
		   ,I.[TableSchema]
           ,I.[TableName]
           ,I.[PK]
           ,I.[FieldName]
           ,I.[OldValue]
           ,I.[NewValue]
           ,I.[UpdateDate]
		   ,I.[UserName]
    FROM INSERTED I
	JOIN [dbo].[AuditTables] a on a.[TableName]=I.[TableName] and a.[TableSchema] = I.[TableSchema]
	WHERE (a.[FieldName] = '*') or (CHARINDEX(i.[FieldName], a.[FieldName])<>0);
END
