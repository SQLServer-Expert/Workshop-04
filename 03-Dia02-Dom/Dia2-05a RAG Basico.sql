/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: RAG Básico

Objetivo:
Demonstrar a solução completa de RAG com prompt básico.

Ambiente:
- SQL Server 2025
- Ollama
- Caddy

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Landry_Blogs
go

/*****************************************
 Cria SP para ser utilizada no RAG
 - Chama LLM de Chat
*****************************************/
go
CREATE or ALTER PROC dbo.spAI_Chat_Ollama
@pSystem nvarchar(max),
@pUser nvarchar(max),
@Modelo nvarchar(200) = N'llama3.2:1b',
@Temp nvarchar(4) = N'0.3',
@Timeout int = 230
as
set nocount on

DECLARE @payload nvarchar(MAX) = N'{
    "model": "' + STRING_ESCAPE(@Modelo, 'json') + N'",
    "options": {"temperature":' + @Temp + N'},
    "messages": [
        {"role": "system", "content": "' + STRING_ESCAPE(@pSystem, 'json') + N'"},
        {"role": "user",   "content": "' + STRING_ESCAPE(@pUser, 'json') + N'"}
    ],
    "stream": false
}'

DECLARE @response nvarchar(MAX)

EXEC sp_invoke_external_rest_endpoint
@url      = 'https://localhost/api/chat',
@method   = 'POST',
@headers  = '{"Content-Type":"application/json"}',
@payload  = @payload,
@timeout  = @Timeout,
@response = @response OUTPUT

SELECT JSON_VALUE(@response, '$.result.message.content') AS Resposta
go
/********************** FIM SP *********************/


/*==============================================================================
  RAG - CENÁRIO 1: PROMPT SIMPLES

  Fluxo:
      Pergunta
          ↓
      Busca vetorial + busca textual
          ↓
      Reciprocal Rank Fusion (RRF)
          ↓
      TOP documentos
          ↓
      Montagem do contexto
          ↓
      Envio para o LLM
==============================================================================*/

set nocount on


/*==============================================================================
  1. CONFIGURAÇÕES
==============================================================================*/

DECLARE @Pergunta nvarchar(2000) = N'Como usar DBCC CHECKDB?'
-- Quantidade de candidatos recuperados por cada mecanismo de busca
DECLARE @TopCandidatos  int = 20

-- Quantidade de documentos após o Ranking, apresentados a LLM
DECLARE @TopDocumentos int = 5

-- Constante utilizada no cálculo do Reciprocal Rank Fusion (RRF)
DECLARE @ConstanteRRF   decimal(10,2) = 60.0

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


/* Prompts */

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
    N'Pergunta:'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)
    + @Pergunta

    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'Contexto:'
    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)
    + COALESCE
      (
          @Contexto,
          N'Nenhum documento relevante foi localizado.'
      )

    + CHAR(13) + CHAR(10)
    + CHAR(13) + CHAR(10)

    + N'Responda à pergunta utilizando o contexto acima.';


/* Conferência antes do envio */

SELECT
    @System AS Prompt_Sistema,
    @User   AS Prompt_Usuario;


/* Chamada ao Ollama */

EXEC dbo.spAI_Chat_Ollama
     @pSystem = @System,
     @pUser   = @User,
     @Modelo  = N'llama3.2:1b',
     @Temp    = N'0.2';
GO
/******************** FIM RAG **************************/

/***************************************
- Prompt Sistema:
  Você é um assistente especializado em Microsoft SQL Server.    Responda dúvidas técnicas sobre SQL Server de forma clara, correta e objetiva.    Regras obrigatórias:  - Utilize o contexto fornecido como principal fonte da resposta.  - Não invente comandos, funcionalidades ou informações.  - Se o contexto não for suficiente, informe isso claramente.  - Responda em português do Brasil.  - Utilize Markdown.  

- Prompt usuário:
Pergunta:    Como usar DBCC CHECKDB?    

Contexto:    
Documento 1    Título: Meu Banco Corrompeu no SQL Server… e Agora?    
# Meu Banco Corrompeu no SQL Server… e Agora?  
## O Erro Clássico de Corrupção  Ao consultar uma linha afetada, temos:  SELECT * FROM VendasDB.dbo.Cliente WHERE Nome = 'Jose' -- OK SELECT * FROM VendasDB.dbo.Cliente WHERE Nome = 'Carla'-- Erro, cai a conexão  ?? Resultado:  <mark>Msg 824, Level 24, State 2 SQL Server detected a logical consistency-based I/O error...</mark>  ?? Verificando Integridade com DBCC CHECKDB  DBCC CHECKDB (VendasDB) WITH NO_INFOMSGS, TABLERESULTS  Essa é a principal ferramenta para diagnosticar páginas suspeitas ou inconsistentes.  Você pode consultar o histórico pelo `msdb..suspect_pages`:  SELECT * FROM msdb..suspect_pages    
----------------------------------------    

Documento 2    Título: Meu Banco Corrompeu no SQL Server… e Agora?    
# Meu Banco Corrompeu no SQL Server… e Agora?  
## Reparando Corrupção com Perda de Dados  Se não houver backup, a única opção pode ser:  ALTER DATABASE VendasDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE DBCC CHECKDB (VendasDB, REPAIR_ALLOW_DATA_LOSS) ALTER DATABASE VendasDB SET MULTI_USER    
----------------------------------------    

Documento 3    Título: Meu Banco Corrompeu no SQL Server… e Agora?    
# Meu Banco Corrompeu no SQL Server… e Agora?  
## Exemplo de criação e corrupção:  DBCC TRACEON(3604) -- Habilita o uso do DBCC PAGE DBCC PAGE(VendasDB, 1, 256, 3) DBCC PAGE(VendasDB, 1, 258, 3) --WITH NO_INFOMSGS, TABLERESULTS  /*****************************************************************************************************************  dbcc WRITEPAGE ({'dbname' | dbid}, fileid, pageid, {offset | 'fieldname'}, length, data [, directORbufferpool]) ******************************************************************************************************************/ ALTER DATABASE VendasDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE DBCC WRITEPAGE ('VendasDB',1,258,4000,1, 0x45, 1) ALTER DATABASE VendasDB SET  MULTI_USER WITH NO_WAIT    
----------------------------------------    

Documento 4    Título: Meu Banco Corrompeu no SQL Server… e Agora?    
# Meu Banco Corrompeu no SQL Server… e Agora?  
## Simulando Corrupção de Tabela  Para estudo, podemos utilizar `DBCC WRITEPAGE` (com EXTREMA cautela) para escrever bytes diretamente em uma página específica do arquivo `.mdf`.    
----------------------------------------    

Documento 5    Título: Entendendo o Crescimento do Transaction Log no SQL Server    
# Entendendo o Crescimento do Transaction Log no SQL Server  
## Como Monitorar o Espaço Usado no Log  Use a função `DBCC SQLPERF` para visualizar o espaço de log utilizado:  DBCC SQLPERF(LOGSPACE)  Ela retorna:  * Nome do banco  * Tamanho total do log (MB)  * Percentual de espaço usado  * Status do log    Responda à pergunta utilizando o contexto acima.
****************************************/

/***************************************
 Comprando sem RAG
***************************************/
EXEC dbo.spAI_Chat_Ollama
@pSystem = '
Você é um assistente especializado em Microsoft SQL Server.

Responda dúvidas técnicas sobre SQL Server de forma clara, correta e objetiva.

Regras obrigatórias:
- Utilize o contexto fornecido como principal fonte da resposta.
- Não invente comandos, funcionalidades ou informações.
- Se o contexto não for suficiente, informe isso claramente.
- Responda em português do Brasil.
- Utilize Markdown.',

@pUser = 'Como usar DBCC CHECKDB?'


