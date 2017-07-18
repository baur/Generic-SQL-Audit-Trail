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
           ,[TableName]
           ,[PK]
           ,[FieldName]
           ,[OldValue]
           ,[NewValue]
           ,[UpdateDate])
     SELECT 
            I.[Type]
           ,I.[TableName]
           ,I.[PK]
           ,I.[FieldName]
           ,I.[OldValue]
           ,I.[NewValue]
           ,I.[UpdateDate]
    FROM INSERTED I
	JOIN [dbo].[AuditTables] a on a.[TableName]=I.[TableName]
	WHERE (a.[FieldName] = '*') or (CHARINDEX(i.[FieldName], a.[FieldName])<>0);
END