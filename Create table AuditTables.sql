SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[AuditTables](
	[id] [smallint] IDENTITY(1,1) NOT NULL,
	[TableSchema] [varchar](128) NOT NULL,
	[TableName] [varchar](128) NOT NULL,
	[DMLStatement] [varchar](50) NOT NULL,
	[FieldName] [varchar](128) NOT NULL,
 CONSTRAINT [PK_AuditTables] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[AuditTables] ADD  CONSTRAINT [DF_AuditTables_TableSchema]  DEFAULT ('dbo') FOR [TableSchema]
GO

ALTER TABLE [dbo].[AuditTables] ADD  CONSTRAINT [DF_AuditTables_DMLStatement]  DEFAULT ('*') FOR [DMLStatement]
GO

ALTER TABLE [dbo].[AuditTables] ADD  CONSTRAINT [DF_AuditTables_FieldName]  DEFAULT ('*') FOR [FieldName]
GO


