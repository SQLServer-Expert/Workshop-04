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

CREATE OR ALTER PROCEDURE dbo.spAI_GerarBlogChunks
    @PostId        int = NULL,
    @TamanhoAlvo   int = 2000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*
        Procedure: dbo.spAI_GerarBlogChunks

        Objetivo:
        Dividir o conteúdo tratado dos posts em chunks semânticos,
        utilizando os cabeçalhos Markdown como limites naturais.

        Estratégia:

        1. Divide o conteúdo em linhas.
        2. Identifica cabeçalhos Markdown iniciados por ##.
        3. Cria uma seção "Introdução" para o conteúdo anterior
           ao primeiro cabeçalho.
        4. Mantém seções menores que @TamanhoAlvo intactas.
        5. Subdivide seções maiores utilizando parágrafos.
        6. Inclui o título do artigo em todos os chunks.
        7. Recria os chunks existentes do post processado.

        Valores gravados em Estrategia:

        INTRODUCTION
        MARKDOWN_SECTION
        MARKDOWN_PARAGRAPH
        OVERSIZE_UNIT
    */

    ----------------------------------------------------------------
    -- Validações
    ----------------------------------------------------------------

    IF @TamanhoAlvo < 500
    BEGIN
        RAISERROR
        (
            'O tamanho-alvo deve ser igual ou superior a 500 caracteres.',
            16,
            1
        );

        RETURN;
    END;

    IF @PostId IS NOT NULL
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.BlogPosts
           WHERE PostId = @PostId
       )
    BEGIN
        RAISERROR
        (
            'O PostId informado não existe em dbo.BlogPosts.',
            16,
            1
        );

        RETURN;
    END;

    IF @PostId IS NOT NULL
       AND EXISTS
       (
           SELECT 1
           FROM dbo.BlogPosts
           WHERE PostId = @PostId
             AND NULLIF(LTRIM(RTRIM(Conteudo_Tratado)), '') IS NULL
       )
    BEGIN
        RAISERROR
        (
            'O post informado ainda não possui conteúdo tratado.',
            16,
            1
        );

        RETURN;
    END;

    ----------------------------------------------------------------
    -- Variáveis utilizadas no processamento
    ----------------------------------------------------------------

    DECLARE
        @PostIdAtual         int,
        @TituloPost          varchar(500),
        @ConteudoTratado     varchar(max),
        @PrimeiraLinha       bigint,
        @SecaoNumero         int,
        @LinhaCabecalho      bigint,
        @TituloSecao         varchar(500),
        @TituloSecaoOriginal varchar(max),
        @ConteudoSecao       varchar(max),
        @PrefixoChunk        varchar(max),
        @TextoCompleto       varchar(max),
        @TextoChunk          varchar(max),
        @TextoUnidade        varchar(max),
        @TextoCandidato      varchar(max),
        @Estrategia          varchar(30),
        @ChunkIndice         int,
        @TemConteudo         bit;

    ----------------------------------------------------------------
    -- Percorre os posts
    ----------------------------------------------------------------

    DECLARE cursor_posts CURSOR LOCAL FAST_FORWARD
    FOR
        SELECT
            PostId,
            Titulo,
            Conteudo_Tratado
        FROM dbo.BlogPosts
        WHERE (@PostId IS NULL OR PostId = @PostId)
          AND NULLIF(LTRIM(RTRIM(Conteudo_Tratado)), '') IS NOT NULL
        ORDER BY PostId;

    OPEN cursor_posts;

    FETCH NEXT FROM cursor_posts
    INTO
        @PostIdAtual,
        @TituloPost,
        @ConteudoTratado;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            --------------------------------------------------------
            -- Remove chunks gerados anteriormente para o post
            --------------------------------------------------------

            DELETE FROM dbo.BlogChunks
            WHERE PostId = @PostIdAtual;

            SET @ChunkIndice = 1;

            --------------------------------------------------------
            -- Divide o conteúdo tratado em linhas
            --------------------------------------------------------

            DROP TABLE IF EXISTS #Linhas;

            CREATE TABLE #Linhas
            (
                NumeroLinha bigint NOT NULL,
                Linha       varchar(max) NOT NULL,
                EhCabecalho bit NOT NULL,
                SecaoNumero int NULL
            );

            INSERT INTO #Linhas
            (
                NumeroLinha,
                Linha,
                EhCabecalho
            )
            SELECT
                ordinal,
                RTRIM(value),
                CASE
                    WHEN LEFT(LTRIM(value), 2) = '##'
                        THEN 1
                    ELSE 0
                END
            FROM STRING_SPLIT
            (
                @ConteudoTratado,
                CHAR(10),
                1
            );

            --------------------------------------------------------
            -- Remove o título inserido pela procedure de tratamento
            --
            -- Ele será acrescentado novamente em cada chunk.
            --------------------------------------------------------

            SELECT
                @PrimeiraLinha =
                    MIN
                    (
                        CASE
                            WHEN LTRIM(RTRIM(Linha)) <> ''
                                THEN NumeroLinha
                        END
                    )
            FROM #Linhas;

            DELETE FROM #Linhas
            WHERE NumeroLinha = @PrimeiraLinha
              AND LEFT(LTRIM(Linha), 2) = '# '
              AND LEFT(LTRIM(Linha), 3) <> '## ';

            --------------------------------------------------------
            -- Numera as seções
            --
            -- Seção 0:
            -- conteúdo anterior ao primeiro cabeçalho.
            --------------------------------------------------------

            ;WITH Secoes AS
            (
                SELECT
                    NumeroLinha,
                    SUM(CONVERT(int, EhCabecalho))
                    OVER
                    (
                        ORDER BY NumeroLinha
                        ROWS UNBOUNDED PRECEDING
                    ) AS NumeroSecao
                FROM #Linhas
            )
            UPDATE l
                SET SecaoNumero = s.NumeroSecao
            FROM #Linhas AS l
            INNER JOIN Secoes AS s
                ON s.NumeroLinha = l.NumeroLinha;

            --------------------------------------------------------
            -- Percorre as seções do documento
            --------------------------------------------------------

            DECLARE cursor_secoes CURSOR LOCAL FAST_FORWARD
            FOR
                SELECT DISTINCT
                    SecaoNumero
                FROM #Linhas
                GROUP BY SecaoNumero
                HAVING MAX
                       (
                           CASE
                               WHEN LTRIM(RTRIM(Linha)) <> ''
                                   THEN 1
                               ELSE 0
                           END
                       ) = 1
                ORDER BY SecaoNumero;

            OPEN cursor_secoes;

            FETCH NEXT FROM cursor_secoes
            INTO @SecaoNumero;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @LinhaCabecalho = NULL;
                SET @TituloSecaoOriginal = NULL;
                SET @ConteudoSecao = NULL;

                ----------------------------------------------------
                -- Recupera o cabeçalho da seção
                ----------------------------------------------------

                SELECT TOP (1)
                    @LinhaCabecalho = NumeroLinha,
                    @TituloSecaoOriginal = Linha
                FROM #Linhas
                WHERE SecaoNumero = @SecaoNumero
                  AND EhCabecalho = 1
                ORDER BY NumeroLinha;

                ----------------------------------------------------
                -- Define e limpa o título da seção
                ----------------------------------------------------

                IF @SecaoNumero = 0
                BEGIN
                    SET @TituloSecao = 'Introdução';
                END;
                ELSE
                BEGIN
                    SET @TituloSecao =
                        LTRIM(RTRIM(@TituloSecaoOriginal));

                    /*
                        Remove os caracteres # existentes no início.
                    */
                    WHILE LEFT(@TituloSecao, 1) = '#'
                    BEGIN
                        SET @TituloSecao =
                            LTRIM(SUBSTRING
                            (
                                @TituloSecao,
                                2,
                                LEN(@TituloSecao)
                            ));
                    END;

                    /*
                        Remove a marcação de negrito do título.
                    */
                    SET @TituloSecao = REPLACE(REPLACE(@TituloSecao, '**', ''),'?','');
                END;

                ----------------------------------------------------
                -- Monta o conteúdo da seção, sem o cabeçalho
                ----------------------------------------------------

                SELECT
                    @ConteudoSecao =
                        STRING_AGG
                        (
                            CAST(Linha AS varchar(max)),
                            CHAR(10)
                        )
                        WITHIN GROUP
                        (
                            ORDER BY NumeroLinha
                        )
                FROM #Linhas
                WHERE SecaoNumero = @SecaoNumero
                  AND EhCabecalho = 0;

                SET @ConteudoSecao =
                    ISNULL(@ConteudoSecao, '');

                /*
                    Remove quebras vazias do início.
                */
                WHILE LEFT(@ConteudoSecao, 1) = CHAR(10)
                BEGIN
                    SET @ConteudoSecao =
                        SUBSTRING
                        (
                            @ConteudoSecao,
                            2,
                            LEN(@ConteudoSecao)
                        );
                END;

                /*
                    Remove quebras vazias do final.
                */
                WHILE RIGHT(@ConteudoSecao, 1) = CHAR(10)
                BEGIN
                    SET @ConteudoSecao =
                        LEFT
                        (
                            @ConteudoSecao,
                            LEN(@ConteudoSecao) - 1
                        );
                END;

                ----------------------------------------------------
                -- Ignora seções sem conteúdo
                ----------------------------------------------------

                IF NULLIF(LTRIM(RTRIM(@ConteudoSecao)), '') IS NOT NULL
                BEGIN
                    ------------------------------------------------
                    -- Prefixo incluído em todos os chunks
                    ------------------------------------------------

                    SET @PrefixoChunk =
                          '# ' + LTRIM(RTRIM(@TituloPost))
                        + CHAR(10) + CHAR(10)
                        + '## ' + LTRIM(RTRIM(@TituloSecao))
                        + CHAR(10) + CHAR(10);

                    SET @TextoCompleto =
                        @PrefixoChunk + @ConteudoSecao;

                    ------------------------------------------------
                    -- Seção dentro do tamanho-alvo
                    ------------------------------------------------

                    IF LEN(@TextoCompleto) <= @TamanhoAlvo
                    BEGIN
                        SET @Estrategia =
                            CASE
                                WHEN @SecaoNumero = 0
                                    THEN 'INTRODUCTION'
                                ELSE 'MARKDOWN_SECTION'
                            END;

                        INSERT INTO dbo.BlogChunks
                        (
                            PostId,
                            Chunk_Indice,
                            Chunk_TituloSecao,
                            Chunk_Texto,
                            Chunk_Tamanho,
                            Estrategia
                        )
                        VALUES
                        (
                            @PostIdAtual,
                            @ChunkIndice,
                            @TituloSecao,
                            @TextoCompleto,
                            LEN(@TextoCompleto),
                            @Estrategia
                        );

                        SET @ChunkIndice += 1;
                    END;
                    ELSE
                    BEGIN
                        ------------------------------------------------
                        -- Seção extensa:
                        -- divide o conteúdo em parágrafos.
                        ------------------------------------------------

                        DROP TABLE IF EXISTS #Unidades;

                        CREATE TABLE #Unidades
                        (
                            OrdemUnidade bigint NOT NULL,
                            Texto        varchar(max) NOT NULL
                        );

                        /*
                            Cada sequência de linhas não vazias forma
                            uma unidade lógica.

                            Consultas SQL com várias linhas permanecem
                            juntas enquanto não houver linha vazia.
                        */
                        ;WITH LinhasSecao AS
                        (
                            SELECT
                                NumeroLinha,
                                Linha,
                                CASE
                                    WHEN LTRIM(RTRIM(Linha)) = ''
                                        THEN 1
                                    ELSE 0
                                END AS EhLinhaVazia
                            FROM #Linhas
                            WHERE SecaoNumero = @SecaoNumero
                              AND EhCabecalho = 0
                        ),
                        Grupos AS
                        (
                            SELECT
                                NumeroLinha,
                                Linha,
                                EhLinhaVazia,
                                SUM(EhLinhaVazia)
                                OVER
                                (
                                    ORDER BY NumeroLinha
                                    ROWS UNBOUNDED PRECEDING
                                ) AS GrupoParagrafo
                            FROM LinhasSecao
                        )
                        INSERT INTO #Unidades
                        (
                            OrdemUnidade,
                            Texto
                        )
                        SELECT
                            MIN(NumeroLinha),
                            STRING_AGG
                            (
                                CAST(Linha AS varchar(max)),
                                CHAR(10)
                            )
                            WITHIN GROUP
                            (
                                ORDER BY NumeroLinha
                            )
                        FROM Grupos
                        WHERE EhLinhaVazia = 0
                        GROUP BY GrupoParagrafo
                        ORDER BY MIN(NumeroLinha);

                        ------------------------------------------------
                        -- Acumula parágrafos até atingir o tamanho
                        ------------------------------------------------

                        SET @TextoChunk = @PrefixoChunk;
                        SET @TemConteudo = 0;

                        DECLARE cursor_unidades CURSOR LOCAL FAST_FORWARD
                        FOR
                            SELECT Texto
                            FROM #Unidades
                            ORDER BY OrdemUnidade;

                        OPEN cursor_unidades;

                        FETCH NEXT FROM cursor_unidades
                        INTO @TextoUnidade;

                        WHILE @@FETCH_STATUS = 0
                        BEGIN
                            SET @TextoCandidato =
                                @TextoChunk
                                + CASE
                                    WHEN @TemConteudo = 1
                                        THEN CHAR(10) + CHAR(10)
                                    ELSE ''
                                  END
                                + @TextoUnidade;

                            /*
                                Se a nova unidade ultrapassar o tamanho,
                                grava o chunk atual antes de adicioná-la.
                            */
                            IF LEN(@TextoCandidato) > @TamanhoAlvo
                               AND @TemConteudo = 1
                            BEGIN
                                INSERT INTO dbo.BlogChunks
                                (
                                    PostId,
                                    Chunk_Indice,
                                    Chunk_TituloSecao,
                                    Chunk_Texto,
                                    Chunk_Tamanho,
                                    Estrategia
                                )
                                VALUES
                                (
                                    @PostIdAtual,
                                    @ChunkIndice,
                                    replace(replace(@TituloSecao,'???',''),'??',''),
                                    @TextoChunk,
                                    LEN(@TextoChunk),
                                    'MARKDOWN_PARAGRAPH'
                                );

                                SET @ChunkIndice += 1;
                                SET @TextoChunk =
                                    @PrefixoChunk + @TextoUnidade;
                                SET @TemConteudo = 1;
                            END;
                            ELSE
                            BEGIN
                                SET @TextoChunk = @TextoCandidato;
                                SET @TemConteudo = 1;
                            END;

                            /*
                                Caso uma única unidade seja maior que
                                o tamanho-alvo, ela é preservada inteira.
                            */
                            IF LEN(@TextoChunk) > @TamanhoAlvo
                               AND @TemConteudo = 1
                            BEGIN
                                INSERT INTO dbo.BlogChunks
                                (
                                    PostId,
                                    Chunk_Indice,
                                    Chunk_TituloSecao,
                                    Chunk_Texto,
                                    Chunk_Tamanho,
                                    Estrategia
                                )
                                VALUES
                                (
                                    @PostIdAtual,
                                    @ChunkIndice,
                                    replace(replace(@TituloSecao,'???',''),'??',''),
                                    @TextoChunk,
                                    LEN(@TextoChunk),
                                    'OVERSIZE_UNIT'
                                );

                                SET @ChunkIndice += 1;
                                SET @TextoChunk = @PrefixoChunk;
                                SET @TemConteudo = 0;
                            END;

                            FETCH NEXT FROM cursor_unidades
                            INTO @TextoUnidade;
                        END;

                        CLOSE cursor_unidades;
                        DEALLOCATE cursor_unidades;

                        ------------------------------------------------
                        -- Grava o último chunk pendente
                        ------------------------------------------------

                        IF @TemConteudo = 1
                        BEGIN
                            INSERT INTO dbo.BlogChunks
                            (
                                PostId,
                                Chunk_Indice,
                                Chunk_TituloSecao,
                                Chunk_Texto,
                                Chunk_Tamanho,
                                Estrategia
                            )
                            VALUES
                            (
                                @PostIdAtual,
                                @ChunkIndice,
                                replace(replace(@TituloSecao,'???',''),'??',''),
                                @TextoChunk,
                                LEN(@TextoChunk),
                                'MARKDOWN_PARAGRAPH'
                            );

                            SET @ChunkIndice += 1;
                        END;
                    END;
                END;

                FETCH NEXT FROM cursor_secoes
                INTO @SecaoNumero;
            END;

            CLOSE cursor_secoes;
            DEALLOCATE cursor_secoes;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            IF CURSOR_STATUS('local', 'cursor_unidades') >= 0
                CLOSE cursor_unidades;

            IF CURSOR_STATUS('local', 'cursor_unidades') > -3
                DEALLOCATE cursor_unidades;

            IF CURSOR_STATUS('local', 'cursor_secoes') >= 0
                CLOSE cursor_secoes;

            IF CURSOR_STATUS('local', 'cursor_secoes') > -3
                DEALLOCATE cursor_secoes;

            IF CURSOR_STATUS('local', 'cursor_posts') >= 0
                CLOSE cursor_posts;

            IF CURSOR_STATUS('local', 'cursor_posts') > -3
                DEALLOCATE cursor_posts;

            THROW;
        END CATCH;

        FETCH NEXT FROM cursor_posts
        INTO
            @PostIdAtual,
            @TituloPost,
            @ConteudoTratado;
    END;

    CLOSE cursor_posts;
    DEALLOCATE cursor_posts;
END;
GO