SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER TRIGGER dbo.tr_filter_Audit ON dbo.Audit
INSTEAD OF INSERT
AS
BEGIN
	INSERT INTO dbo.Audit (
		 Type
		,TableSchema
		,TableName
		,PK
		,FieldName
		,OldValue
		,NewValue
		,UpdateDate
		,UserName
		,ApplicationName
		)
	SELECT I.Type
		  ,I.TableSchema
		  ,I.TableName
		  ,I.PK
		  ,I.FieldName
		  ,I.OldValue
		  ,I.NewValue
		  ,I.UpdateDate
		  ,I.UserName
		  ,I.ApplicationName
	FROM INSERTED I
	JOIN dbo.AuditTables a ON a.TableName = I.TableName
		AND a.TableSchema = I.TableSchema
	WHERE (a.FieldName = '*')
		OR (CHARINDEX(i.FieldName, a.FieldName) <> 0);
END