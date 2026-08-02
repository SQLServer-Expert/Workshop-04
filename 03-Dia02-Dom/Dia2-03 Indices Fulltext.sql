/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: Fulltext Search

Objetivo:
Demonstrar o que é Fulltext Search e como configurar.

Ambiente:
- SQL Server 2025

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Landry_Blogs
go

/********************************************************************************
 Fulltext Index
 https://learn.microsoft.com/en-us/sql/relational-databases/search/full-text-search?view=sql-server-ver16
 https://learn.microsoft.com/en-us/sql/relational-databases/search/create-and-manage-full-text-indexes?view=sql-server-ver16

 - Requisitos para criar Indice Fulltext
   - Criar Catalogo Fulltext no Banco.
   - Tabela precisa de índice UNIQUE NOT NULL com chave contendo uma coluna.

*********************************************************************************/

SELECT * FROM sys.fulltext_languages WHERE [name] = 'Brazilian'
-- Português Brasil 1046

/***********************************
 1o Passo: Criar um Catalogo
************************************/
CREATE FULLTEXT CATALOG Landry_Blogs  --WITH ACCENT_SENSITIVITY = OFF -- Padrão é ON
AS DEFAULT
-- DROP FULLTEXT CATALOG Landry_Blogs 

/**************************************************
 2o Passo: Criar um Índice Fulltext por tabela
***************************************************/
-- DROP FULLTEXT INDEX ON dbo.BlogChunks_PorTamanho
CREATE FULLTEXT INDEX ON dbo.BlogChunks_PorTamanho (Chunk_Texto LANGUAGE 1046)
KEY INDEX pk_BlogChunks_PorTamanho
WITH STOPLIST = SYSTEM

-- DROP FULLTEXT INDEX ON dbo.BlogChunks
CREATE FULLTEXT INDEX ON dbo.BlogChunks (Chunk_Texto LANGUAGE 1046)
KEY INDEX pk_BlogChunks
WITH STOPLIST = SYSTEM

-- Informações sobre FULLTEXT INDEX
DECLARE @NomeCatalogo varchar(100) = 'Landry_Blogs'

SELECT FTC.name AS NomeCatalogo, SCHEMA_NAME(T.schema_id) AS NomeSchema, T.name AS NomeTabela,
CASE FTI.change_tracking_state_desc
    WHEN 'AUTO' THEN 'Automática'
    WHEN 'MANUAL' THEN 'Manual'
    WHEN 'OFF' THEN 'Desabilitada'
    ELSE FTI.change_tracking_state_desc
END AS AtualizacaoIndice,
FULLTEXTCATALOGPROPERTY(@NomeCatalogo, 'ItemCount') AS ItemCount,
FULLTEXTCATALOGPROPERTY(@NomeCatalogo, 'IndexSize') AS IndexSize_MB,
DATEADD(SECOND,FULLTEXTCATALOGPROPERTY(@NomeCatalogo, 'PopulateCompletionAge'),
        CONVERT(datetime, '19900101', 112)) AS LastPopulated,
CASE FULLTEXTCATALOGPROPERTY(@NomeCatalogo, 'PopulateStatus')
    WHEN 0 THEN 'Idle'
    WHEN 1 THEN 'Full Population In Progress'
    WHEN 2 THEN 'Paused'
    WHEN 3 THEN 'Throttled'
    WHEN 4 THEN 'Recovering'
    WHEN 5 THEN 'Shutdown'
    WHEN 6 THEN 'Incremental Population In Progress'
    WHEN 7 THEN 'Building Index'
    WHEN 8 THEN 'Disk Full - Paused'
    WHEN 9 THEN 'Change Tracking'
END AS PopulateStatus
FROM sys.fulltext_catalogs AS FTC
INNER JOIN sys.fulltext_indexes AS FTI ON FTC.fulltext_catalog_id = FTI.fulltext_catalog_id
INNER JOIN sys.tables AS T ON FTI.object_id = T.object_id
WHERE FTC.name = @NomeCatalogo


/************************************************
 Comparando LIKE x CONTAINS

 Live 129: https://youtube.com/live/Ne1BhnmXCI0
 Disponível até dia 07/08/2026 (6a)
*************************************************/
SELECT * FROM dbo.BlogChunks
WHERE Chunk_Texto like '%TempDB%'

/*************************
 Função CONTAINS
 https://learn.microsoft.com/en-us/sql/t-sql/queries/contains-transact-sql?view=sql-server-ver17
**************************/
SELECT * FROM dbo.BlogChunks
WHERE contains(Chunk_Texto,'TempDB')

/****************************************************************
 Função CONTAINSTABLE
 https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/containstable-transact-sql?view=sql-server-ver17

 - Mesmo que  a função CONTAINS, contudo retorna uma tabela.
*****************************************************************/
SELECT C.ChunkId, C.Chunk_Texto, FT.[RANK]
FROM CONTAINSTABLE(dbo.BlogChunks, Chunk_Texto, 'TempDB') as FT
JOIN dbo.BlogChunks C ON C.ChunkId = FT.[KEY]
ORDER BY FT.[RANK] DESC


/*************************
 Função FREETEXT
 https://learn.microsoft.com/pt-br/sql/relational-databases/system-functions/freetexttable-transact-sql?view=sql-server-ver17
**************************/
SELECT * FROM dbo.BlogChunks
WHERE freetext(Chunk_Texto,'TempDB')

/****************************************************************
 Função FREETEXTTABLE
 https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/freetexttable-transact-sql?view=sql-server-ver17

 - Mesmo que  a função FREETEXT, contudo retorna uma tabela.
*****************************************************************/
SELECT C.ChunkId, C.Chunk_Texto, FT.[RANK]
FROM FREETEXTTABLE(dbo.BlogChunks, Chunk_Texto, 'TempDB') as FT
JOIN dbo.BlogChunks C ON C.ChunkId = FT.[KEY]
ORDER BY FT.[RANK] DESC


/*****************************************************
 Comparando Fulltext Search com Busca Vetorial
******************************************************/
-- Busca Vetorial
go
--DECLARE @Pergunta varchar(2000) = 'Como diagnosticar crescimento do log da TempDB?'
DECLARE @Pergunta varchar(2000) = 'Como usar DBCC CHECKDB'
DECLARE @VetorPergunta vector(768) = ai_generate_embeddings(@Pergunta USE MODEL EmbeddingGemma)
DECLARE @Top int = 5

SELECT bp.Titulo, bc.Chunk_Texto as ChunkVariavel, vs.distance as Distancia
FROM vector_search(
TABLE = dbo.BlogChunks AS bc,
COLUMN = Embedding,
SIMILAR_TO = @VetorPergunta,
METRIC = 'cosine',
TOP_N  = @Top
) as vs

JOIN dbo.BlogPosts bp ON bp.PostId = bc.PostId
ORDER BY vs.distance
go

-- Busca Fulltext
--DECLARE @Pergunta varchar(2000) = 'Como diagnosticar crescimento do log da TempDB?'
DECLARE @Pergunta varchar(2000) = 'Como usar DBCC CHECKDB'
DECLARE @Top int = 5

SELECT top(@Top) bp.Titulo, C.Chunk_Texto as ChunkFullText, FT.[RANK]
FROM FREETEXTTABLE(dbo.BlogChunks, Chunk_Texto, @Pergunta) as FT
JOIN dbo.BlogChunks C ON C.ChunkId = FT.[KEY]
JOIN dbo.BlogPosts bp ON bp.PostId = c.PostId
ORDER BY FT.[RANK] DESC
