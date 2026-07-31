/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: Chunking

Objetivo:
Demonstrar a geração de chunks com tamanhos variáveis, de acordo com
marcações de seção em documentos Markdown.

Ambiente:
- SQL Server 2025
- Ollama
- Caddy

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Landry_Blogs
go

/***********************************************
 Acrescenta nova coluna na tabela dbo.BlogPosts 
 para armazenar o blog sem URLs e  marcações de
 Markdown que não são necessárias para Chunk.
************************************************/
--ALTER TABLE dbo.BlogPosts DROP COLUMN Conteudo_Tratado
ALTER TABLE dbo.BlogPosts ADD Conteudo_Tratado varchar(max)
go

/***********************************************
 Cria tabela para armazenar os Chunks variáveis
************************************************/
DROP TABLE IF exists dbo.BlogChunks
go
CREATE TABLE dbo.BlogChunks (
ChunkId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_BlogChunks PRIMARY KEY (ChunkId),
PostId int NOT NULL,
Chunk_Indice int NOT NULL,
Chunk_TituloSecao varchar(500) NULL,
Chunk_Texto varchar(max) NOT NULL,
Chunk_Tamanho int NOT NULL,
Estrategia varchar(30) NOT NULL,
Embedding vector(768, float32) NULL)
go

ALTER TABLE dbo.BlogChunks ADD CONSTRAINT UQ_BlogChunks_Post_Indice
UNIQUE (PostId, Chunk_Indice)
go

ALTER TABLE dbo.BlogChunks ADD CONSTRAINT FK_BlogChunks_BlogPosts
FOREIGN KEY (PostId) REFERENCES dbo.BlogPosts(PostId)
go

/*******************************
 Prepara os Blogs
********************************/
EXEC dbo.spAI_TratarBlogPosts

SELECT * FROM dbo.BlogPosts

/*******************************
 Executa Chunking
********************************/
EXEC dbo.spAI_GerarBlogChunks

SELECT * FROM dbo.BlogChunks


-- Validar distribuição de chunks por post
SELECT bp.Titulo,
count(bc.ChunkId) as Total_Chunks,
min(len(bc.Chunk_Texto)) as Menor_Chunk,
max(len(bc.Chunk_Texto)) as Maior_Chunk,
avg(len(bc.Chunk_Texto)) as Media_Chunk
FROM dbo.BlogPosts bp
JOIN dbo.BlogChunks bc ON bc.PostId = bp.PostId
GROUP BY bp.Titulo
ORDER BY Total_Chunks DESC

/*****************************************
 Gerar embeddings para todos os chunks
******************************************/
-- Modelo embeddinggemma
-- Leva +- 6 minutos
UPDATE dbo.BlogChunks
SET Embedding = ai_generate_embeddings(Chunk_Texto USE MODEL EmbeddingGemma)
WHERE Embedding is null

-- Monitorar progresso em outra aba
SELECT count(*) as Total_Chunks,
count(Embedding) as Com_Embedding,
count(*) - count(Embedding) as Sem_Embedding,
cast(count(Embedding) * 100.0 / count(*) as decimal(5,1)) as Percentual
FROM dbo.BlogChunks with (nolock)

SELECT * FROM dbo.BlogChunks with (nolock)