/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: Stored Procedure para RAG

Objetivo:
Cria Stored Procedure para encapsular RAG.

Ambiente:
- SQL Server 2025
- Ollama
- Caddy

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Landry_Blogs
go



go
CREATE or ALTER PROC dbo.spAI_RAG_Ollama
/*==============================================================================
  Parâmetros:
  @Pergunta nvarchar(2000) - prompt do usuário final
  @TopCandidatos int - Quantidade de candidatos recuperados por cada 
                       mecanismo de busca
  @TopDocumentos int - Quantidade de documentos após o Ranking, 
                       apresentados a LLM
  @ConstanteRRF decimal(10,2) - Constante utilizada no cálculo do 
                                Reciprocal Rank Fusion (RRF)

  Chamada:
  EXEC dbo.spAI_RAG_Ollama 
  @Pergunta = N'Como usar DBCC CHECKDB?',
  @TopDocumentos = 5,
  @vModelo = N'llama3.2:1b',
  @vTemp = N'0.2'
==============================================================================*/
@Pergunta nvarchar(2000) = N'Como usar DBCC CHECKDB?',
@TopCandidatos int = 20,
@TopDocumentos int = 5,
@ConstanteRRF decimal(10,2) = 60.0,
@vModelo nvarchar(200) = N'llama3.2:1b',
@vTemp nvarchar(4) = N'0.2'
as

set nocount on

/*==============================================================================
  2. GERAÇÃO DO EMBEDDING DA PERGUNTA
==============================================================================*/
DECLARE @VetorPergunta vector(768)
SET @VetorPergunta = AI_GENERATE_EMBEDDINGS (@Pergunta USE MODEL EmbeddingGemma)

/*==============================================================================
  3. BUSCA HÍBRIDA COM RECIPROCAL RANK FUSION
==============================================================================*/
DROP TABLE IF EXISTS #ResultadoHibrido

;WITH BuscaVetorial AS
(
    SELECT
        bc.ChunkId,
        vs.distance AS Distancia,
        ROW_NUMBER() OVER
        (
            ORDER BY vs.distance, bc.ChunkId
        ) AS RankingVetorial

    FROM VECTOR_SEARCH
    (
        TABLE       = dbo.BlogChunks AS bc,
        COLUMN      = Embedding,
        SIMILAR_TO  = @VetorPergunta,
        METRIC      = 'cosine',
        TOP_N       = @TopCandidatos
    ) AS vs
),
BuscaTextual AS
(
    SELECT
        bc.ChunkId,
        ft.[RANK] AS RelevanciaTextual,
        ROW_NUMBER() OVER
        (
            ORDER BY ft.[RANK] DESC, bc.ChunkId
        ) AS RankingTextual

    FROM FREETEXTTABLE
    (
        dbo.BlogChunks,
        Chunk_Texto,
        @Pergunta,
        LANGUAGE 1046,
        @TopCandidatos
    ) AS ft

    JOIN dbo.BlogChunks AS bc
        ON bc.ChunkId = ft.[KEY]
),
FusaoRankings AS
(
    SELECT
        COALESCE(v.ChunkId, t.ChunkId) AS ChunkId,
        v.Distancia,
        t.RelevanciaTextual,
        v.RankingVetorial,
        t.RankingTextual,

        COALESCE
        (
            1.0 / (@ConstanteRRF + v.RankingVetorial),
            0
        )
        +
        COALESCE
        (
            1.0 / (@ConstanteRRF + t.RankingTextual),
            0
        ) AS PontuacaoRRF

    FROM BuscaVetorial AS v

    FULL OUTER JOIN BuscaTextual AS t
        ON t.ChunkId = v.ChunkId
)
SELECT TOP (@TopDocumentos)
    f.ChunkId,
    bc.PostId,
    bp.Titulo,
    bc.Chunk_Indice,
    bc.Chunk_Texto,
    f.Distancia,
    f.RelevanciaTextual,
    f.RankingVetorial,
    f.RankingTextual,
    CAST(f.PontuacaoRRF AS decimal(19,8)) AS PontuacaoRRF

INTO #ResultadoHibrido

FROM FusaoRankings AS f

JOIN dbo.BlogChunks AS bc
    ON bc.ChunkId = f.ChunkId

JOIN dbo.BlogPosts AS bp
    ON bp.PostId = bc.PostId

ORDER BY
    f.PontuacaoRRF DESC,
    f.Distancia,
    f.ChunkId;


/* Documentos selecionados para o contexto */
/*
SELECT
    ChunkId,
    Titulo,
    LEFT(Chunk_Texto, 300) AS Trecho,
    RankingVetorial,
    RankingTextual,
    PontuacaoRRF
FROM #ResultadoHibrido
ORDER BY
    PontuacaoRRF DESC,
    Distancia;
*/

/* Montagem do contexto */

DECLARE @Contexto nvarchar(MAX);

;WITH DocumentosOrdenados AS
(
    SELECT
        ROW_NUMBER() OVER
        (
            ORDER BY PontuacaoRRF DESC, Distancia, ChunkId
        ) AS NumeroDocumento,
        Titulo,
        Chunk_Texto
    FROM #ResultadoHibrido
)
SELECT
    @Contexto =
        STRING_AGG
        (
            CONVERT
            (
                nvarchar(MAX),

                N'Documento '
                + CONVERT(nvarchar(10), NumeroDocumento)
                + CHAR(13) + CHAR(10)
                + CHAR(13) + CHAR(10)

                + N'Título: '
                + COALESCE(Titulo, N'Sem título')
                + CHAR(13) + CHAR(10)
                + CHAR(13) + CHAR(10)

                + Chunk_Texto
            ),

            CHAR(13) + CHAR(10)
            + CHAR(13) + CHAR(10)
            + N'----------------------------------------'
            + CHAR(13) + CHAR(10)
            + CHAR(13) + CHAR(10)
        )
        WITHIN GROUP
        (
            ORDER BY NumeroDocumento
        )
FROM DocumentosOrdenados;


/*==============================================================================
  5. PROMPTS - CENÁRIO 2: ESTRUTURA IDEAL PARA RAG
==============================================================================*/

DECLARE @System nvarchar(MAX) = N'
Você é um assistente especializado em Microsoft SQL Server.

Responda dúvidas técnicas sobre SQL Server de forma clara, correta e objetiva.

Regras obrigatórias:
- Utilize o contexto fornecido como principal fonte da resposta.
- Não invente comandos, funcionalidades ou informações.
- Se o contexto não for suficiente, informe isso claramente.
- Responda em português do Brasil.
- Utilize Markdown.
';

DECLARE @User nvarchar(MAX) =
      N'PERGUNTA DO USUÁRIO'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + @Pergunta

    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'========================================'
    + CHAR(13) + CHAR(10)
    + N'BASE DE CONHECIMENTO RECUPERADA'
    + CHAR(13) + CHAR(10)
    + N'========================================'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + COALESCE
      (
          @Contexto,
          N'Nenhum documento relevante foi localizado.'
      )

    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'========================================'
    + CHAR(13) + CHAR(10)
    + N'REGRAS PARA A RESPOSTA'
    + CHAR(13) + CHAR(10)
    + N'========================================'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'1. Responda exclusivamente com informações presentes no contexto.'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'2. Não utilize conhecimento próprio.'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'3. Não crie comandos, parâmetros, opções ou exemplos que não estejam no contexto.'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'4. Se o contexto não responder à pergunta, responda exatamente: Não encontrei informações suficientes na base de conhecimento.'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'Responda em Markdown.';


/* Conferência antes do envio */

--SELECT @System AS Prompt_Sistema, @User   AS Prompt_Usuario


/* Chamada ao Ollama */

EXEC dbo.spAI_Chat_Ollama
     @pSystem = @System,
     @pUser   = @User,
     @Modelo  = @vModelo,
     @Temp    = @vTemp;
GO
/******************** FIM RAG **************************/




