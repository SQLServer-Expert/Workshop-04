/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: Busca Vetorial em Embeddings

Objetivo:
Demonstrar busca vetorial em embeddings gerados por uma LLM.

Ambiente:
- SQL Server 2025
- Ollama
- Caddy

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Landry_Blogs
go

/**************************************
 Criar o índice vetorial
***************************************/
DROP INDEX IF EXISTS IX_BlogChunksGemma_Embedding ON dbo.BlogChunksGemma
go
CREATE VECTOR INDEX IX_BlogChunksGemma_Embedding
ON dbo.BlogChunksGemma (Embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann')
go

DROP INDEX IF EXISTS IX_BlogChunks ON dbo.BlogChunks
go
CREATE VECTOR INDEX IX_BlogChunks
ON dbo.BlogChunks (Embedding)
WITH (METRIC = 'cosine', TYPE = 'diskann')
go
/*
Warning: The join order has been enforced because a local join hint is used.

O algoritmo DiskANN (que é o tipo de índice vetorial que o SQL Server 2025 usa internamente) 
durante sua construção executa queries internas com hints de join explícitos para garantir a 
ordem correta de processamento dos vetores. O SQL Server é "honesto" e avisa quando o otimizador 
foi forçado a seguir uma ordem específica em vez de escolher livremente — mas nesse caso é 
comportamento intencional e esperado, não um problema.
*/

-- Verificar a criação do índice vetorial
SELECT i.[name] as Nome_Indice,
i.[type_desc] as Tipo,
vi.distance_metric as Metrica,
vi.vector_index_type as Algoritmo,
vi.build_parameters as Parametros
FROM sys.indexes i
JOIN sys.vector_indexes vi ON vi.object_id = i.object_id AND vi.index_id  = i.index_id
WHERE i.object_id = object_id('dbo.BlogChunksGemma')

/**************************************
 Busca semântica - VECTOR_SEARCH
***************************************/
go
DECLARE @Pergunta varchar(2000) = 'Como diagnosticar crescimento do log da TempDB?'
DECLARE @VetorPergunta vector(768) = ai_generate_embeddings(@Pergunta USE MODEL EmbeddingGemma)
DECLARE @Top int = 5

-- Chunk Tamanho Fixo
SELECT bp.Titulo, bc.Chunk_Texto as ChunkFixo, vs.distance as Distancia
FROM vector_search(
TABLE = dbo.BlogChunksGemma AS bc,
COLUMN = Embedding,
SIMILAR_TO = @VetorPergunta,
METRIC = 'cosine',
TOP_N  = @Top
) as vs

JOIN dbo.BlogPosts bp ON bp.PostId = bc.PostId
ORDER BY vs.distance

-- Chunk Tamanho Variável
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

/*******************************************************
 Busca semântica por similaridade vetorial
*********************************************************/
go
DECLARE @Pergunta varchar(2000) = 'Como diagnosticar crescimento do log da TempDB?'
DECLARE @VetorPergunta vector(768) = ai_generate_embeddings(@Pergunta USE MODEL EmbeddingGemma)

-- Chunk Tamanho Fixo
SELECT TOP (5) bp.Titulo, bc.Chunk_Texto as ChunkFixo,
vector_distance('cosine', bc.Embedding, @VetorPergunta) as Distancia
FROM dbo.BlogChunksGemma bc
INNER JOIN dbo.BlogPosts bp ON bp.PostId = bc.PostId
ORDER BY Distancia ASC

-- Chunk Tamanho Variável
SELECT TOP (5) bp.Titulo, bc.Chunk_Texto as ChunkVariavel,
vector_distance('cosine', bc.Embedding, @VetorPergunta) as Distancia
FROM dbo.BlogChunks bc
INNER JOIN dbo.BlogPosts bp ON bp.PostId = bc.PostId
ORDER BY Distancia ASC
go

