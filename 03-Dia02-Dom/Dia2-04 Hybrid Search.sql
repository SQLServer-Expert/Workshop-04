/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: Hybrid Search

Objetivo:
Implementar Hybrid Search.

Ambiente:
- SQL Server 2025

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Landry_Blogs
go


/*****************************
 Hybrid Search
******************************/
DECLARE @Pergunta varchar(2000) = 'Como usar DBCC CHECKDB';

DECLARE @VetorPergunta vector(768) =
    AI_GENERATE_EMBEDDINGS
    (
        @Pergunta
        USE MODEL EmbeddingGemma
    );

DECLARE @Top int = 5;
DECLARE @K float = 60.0;


/*
    1. Busca Vetorial

    A menor distância representa o melhor resultado.
    ROW_NUMBER transforma a ordenação em ranking:
    1, 2, 3...
*/
;WITH BuscaVetorial AS
(
    SELECT
        bc.ChunkId,
        bc.PostId,
        vs.distance AS Distancia,

        ROW_NUMBER() OVER
        (
            ORDER BY vs.distance
        ) AS RankVetorial

    FROM VECTOR_SEARCH
    (
        TABLE = dbo.BlogChunks AS bc,
        COLUMN = Embedding,
        SIMILAR_TO = @VetorPergunta,
        METRIC = 'cosine',
        TOP_N = @Top
    ) AS vs
),


/*
    2. Busca Full-Text

    O maior RANK representa o melhor resultado.
*/
BuscaFullText AS
(
    SELECT TOP (@Top)
        bc.ChunkId,
        bc.PostId,
        ft.[RANK] AS FullTextScore,

        ROW_NUMBER() OVER
        (
            ORDER BY ft.[RANK] DESC
        ) AS RankFullText

    FROM FREETEXTTABLE
    (
        dbo.BlogChunks,
        Chunk_Texto,
        @Pergunta
    ) AS ft

    INNER JOIN dbo.BlogChunks AS bc
        ON bc.ChunkId = ft.[KEY]

    ORDER BY
        ft.[RANK] DESC
),


/*
    3. Combina os resultados das duas buscas

    FULL OUTER JOIN mantém:

    - chunks encontrados nas duas buscas;
    - chunks encontrados apenas na busca vetorial;
    - chunks encontrados apenas no Full-Text.
*/
ResultadosCombinados AS
(
    SELECT
        COALESCE(v.ChunkId, f.ChunkId) AS ChunkId,
        COALESCE(v.PostId, f.PostId) AS PostId,

        v.Distancia,
        v.RankVetorial,

        f.FullTextScore,
        f.RankFullText

    FROM BuscaVetorial AS v

    FULL OUTER JOIN BuscaFullText AS f
        ON f.ChunkId = v.ChunkId
),


/*
    4. Calcula o RRF

    Documento ausente em uma busca recebe contribuição zero
    naquela parte da fórmula.

    RRF =
        1 / (K + RankVetorial)
        +
        1 / (K + RankFullText)
*/
CalculoRRF AS
(
    SELECT
        ChunkId,
        PostId,
        Distancia,
        RankVetorial,
        FullTextScore,
        RankFullText,

        ISNULL
        (
            1.0 / (@K + RankVetorial),
            0
        ) AS ContribuicaoVetorial,

        ISNULL
        (
            1.0 / (@K + RankFullText),
            0
        ) AS ContribuicaoFullText,

        ISNULL
        (
            1.0 / (@K + RankVetorial),
            0
        )
        +
        ISNULL
        (
            1.0 / (@K + RankFullText),
            0
        ) AS RRFScore

    FROM ResultadosCombinados
)


/*
    5. Ranking final da busca híbrida
*/
SELECT
    ROW_NUMBER() OVER
    (
        ORDER BY r.RRFScore DESC
    ) AS RankingFinal,

    r.ChunkId,
    bp.Titulo,
    bc.Chunk_TituloSecao,

    r.RankVetorial,
    r.Distancia,
    r.ContribuicaoVetorial,

    r.RankFullText,
    r.FullTextScore,
    r.ContribuicaoFullText,

    r.RRFScore,

    bc.Chunk_Texto

FROM CalculoRRF AS r

INNER JOIN dbo.BlogChunks AS bc
    ON bc.ChunkId = r.ChunkId

INNER JOIN dbo.BlogPosts AS bp
    ON bp.PostId = r.PostId

ORDER BY
    r.RRFScore DESC;
GO
