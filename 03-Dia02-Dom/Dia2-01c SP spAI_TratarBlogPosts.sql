/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: Chunking

Objetivo:
Stored Procedure para tratamento de documentos Markdown limpando URLs, 
imagens e outras marcações que não são necessárias em um Chunk, mantendo 
apenas marcações de seção.

Ambiente:
- SQL Server 2025
- Ollama
- Caddy

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Landry_Blogs
go

CREATE OR ALTER PROCEDURE dbo.spAI_TratarBlogPosts
    @PostId int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*
        Procedure: dbo.spAI_TratarBlogPosts

        Objetivo:
        Limpar o conteúdo Markdown armazenado em dbo.BlogPosts.Conteudo
        e gravar o resultado em dbo.BlogPosts.Conteudo_Tratado.

        Regras:
        - Padroniza as quebras de linha.
        - Remove imagens Markdown.
        - Remove separadores Markdown.
        - Remove o rodapé padrão dos artigos.
        - Remove as cercas dos blocos de código: ```sql e ```.
        - Preserva o código SQL existente entre as cercas.
        - Remove escapes comuns do Markdown.
        - Acrescenta o título do post ao início do conteúdo.
        - Mantém no máximo duas linhas vazias consecutivas.
        - Sempre parte da coluna Conteudo, tornando a execução idempotente.
    */

    /*
        Valida o PostId antes de iniciar o processamento.
    */
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

    DECLARE
        @PostIdAtual      int,
        @Titulo           varchar(500),
        @ConteudoOriginal varchar(max),
        @ConteudoTratado  varchar(max),
        @PosicaoRodape    bigint,
        @PrimeiraLinha    bigint,
        @UltimaLinha      bigint;

    DECLARE cursor_posts CURSOR LOCAL FAST_FORWARD
    FOR
        SELECT
            PostId,
            Titulo,
            Conteudo
        FROM dbo.BlogPosts
        WHERE @PostId IS NULL
           OR PostId = @PostId
        ORDER BY PostId;

    OPEN cursor_posts;

    FETCH NEXT FROM cursor_posts
    INTO
        @PostIdAtual,
        @Titulo,
        @ConteudoOriginal;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            /*
                O tratamento sempre começa pelo conteúdo original.
            */
            SET @ConteudoTratado = @ConteudoOriginal;

            /*
                Padroniza as quebras de linha:

                CRLF -> LF
                CR   -> LF
            */
            SET @ConteudoTratado =
                REPLACE
                (
                    REPLACE
                    (
                        @ConteudoTratado,
                        CHAR(13) + CHAR(10),
                        CHAR(10)
                    ),
                    CHAR(13),
                    CHAR(10)
                );

            /*
                Remove o rodapé repetitivo.

                Tudo a partir desta frase é descartado.
            */
            SET @PosicaoRodape =
                CHARINDEX
                (
                    'Fui, mas volto com mais SQL Server em breve!',
                    @ConteudoTratado
                );

            IF @PosicaoRodape > 0
            BEGIN
                SET @ConteudoTratado =
                    LEFT
                    (
                        @ConteudoTratado,
                        @PosicaoRodape - 1
                    );
            END;

            DROP TABLE IF EXISTS #Linhas;

            CREATE TABLE #Linhas
            (
                NumeroLinha bigint NOT NULL,
                Linha       varchar(max) NOT NULL,
                EhCerca     bit NOT NULL,
                DentroCodigo bit NULL
            );

            /*
                Divide o documento em linhas, preservando a ordem.
            */
            INSERT INTO #Linhas
            (
                NumeroLinha,
                Linha,
                EhCerca
            )
            SELECT
                ordinal,
                RTRIM(value),
                CASE
                    WHEN LEFT(LTRIM(value), 3) = '```'
                        THEN 1
                    ELSE 0
                END
            FROM STRING_SPLIT
            (
                @ConteudoTratado,
                CHAR(10),
                1
            );

            /*
                Identifica quais linhas estão dentro de blocos de código.

                Essa identificação ocorre antes da remoção das cercas.
            */
            ;WITH EstadoCodigo AS
            (
                SELECT
                    NumeroLinha,
                    SUM(CONVERT(int, EhCerca))
                    OVER
                    (
                        ORDER BY NumeroLinha
                        ROWS BETWEEN UNBOUNDED PRECEDING
                                 AND 1 PRECEDING
                    ) AS CercasAnteriores
                FROM #Linhas
            )
            UPDATE l
                SET DentroCodigo =
                    CASE
                        WHEN ISNULL(e.CercasAnteriores, 0) % 2 = 1
                            THEN 1
                        ELSE 0
                    END
            FROM #Linhas AS l
            INNER JOIN EstadoCodigo AS e
                ON e.NumeroLinha = l.NumeroLinha;

            /*
                Remove imagens Markdown fora de blocos de código.

                Exemplos:

                ![](https://...)
                ![Descrição](https://...)
            */
            DELETE FROM #Linhas
            WHERE DentroCodigo = 0
              AND LEFT(LTRIM(Linha), 2) = '![';

            /*
                Remove os separadores horizontais Markdown.
            */
            DELETE FROM #Linhas
            WHERE DentroCodigo = 0
              AND LTRIM(RTRIM(Linha)) = '---';

            /*
                Remove as linhas que abrem ou fecham os blocos de código.

                Exemplos removidos:

                ```sql
                ```
            */
            DELETE FROM #Linhas
            WHERE EhCerca = 1;

            /*
                Remove escapes comuns inseridos pelo Markdown.

                Exemplos:

                ACTIVE\_TRANSACTION -> ACTIVE_TRANSACTION
                1\. Sintomas        -> 1. Sintomas
            */
            UPDATE #Linhas
                SET Linha =
                    REPLACE
                    (
                        REPLACE
                        (
                            REPLACE
                            (
                                REPLACE
                                (
                                    REPLACE
                                    (
                                        REPLACE
                                        (
                                            REPLACE
                                            (
                                                REPLACE
                                                (
                                                    Linha,
                                                    '\_',
                                                    '_'
                                                ),
                                                '\.',
                                                '.'
                                            ),
                                            '\*',
                                            '*'
                                        ),
                                        '\#',
                                        '#'
                                    ),
                                    '\[',
                                    '['
                                ),
                                '\]',
                                ']'
                            ),
                            '\(',
                            '('
                        ),
                        '\)',
                        ')'
                    );

            /*
                Localiza a primeira e a última linha com conteúdo.
            */
            SELECT
                @PrimeiraLinha =
                    MIN
                    (
                        CASE
                            WHEN LTRIM(RTRIM(Linha)) <> ''
                                THEN NumeroLinha
                        END
                    ),
                @UltimaLinha =
                    MAX
                    (
                        CASE
                            WHEN LTRIM(RTRIM(Linha)) <> ''
                                THEN NumeroLinha
                        END
                    )
            FROM #Linhas;

            /*
                Remove linhas vazias existentes no início e no final.
            */
            IF @PrimeiraLinha IS NOT NULL
            BEGIN
                DELETE FROM #Linhas
                WHERE NumeroLinha < @PrimeiraLinha
                   OR NumeroLinha > @UltimaLinha;
            END;

            /*
                Mantém no máximo duas linhas vazias consecutivas.
            */
            ;WITH LinhasClassificadas AS
            (
                SELECT
                    NumeroLinha,
                    CASE
                        WHEN LTRIM(RTRIM(Linha)) = ''
                            THEN 1
                        ELSE 0
                    END AS EhLinhaVazia
                FROM #Linhas
            ),
            Grupos AS
            (
                SELECT
                    NumeroLinha,
                    EhLinhaVazia,
                    SUM
                    (
                        CASE
                            WHEN EhLinhaVazia = 0
                                THEN 1
                            ELSE 0
                        END
                    )
                    OVER
                    (
                        ORDER BY NumeroLinha
                        ROWS UNBOUNDED PRECEDING
                    ) AS Grupo
                FROM LinhasClassificadas
            ),
            LinhasNumeradas AS
            (
                SELECT
                    NumeroLinha,
                    EhLinhaVazia,
                    CASE
                        WHEN EhLinhaVazia = 1
                        THEN
                            ROW_NUMBER()
                            OVER
                            (
                                PARTITION BY Grupo, EhLinhaVazia
                                ORDER BY NumeroLinha
                            )
                    END AS NumeroLinhaVazia
                FROM Grupos
            )
            DELETE l
            FROM #Linhas AS l
            INNER JOIN LinhasNumeradas AS n
                ON n.NumeroLinha = l.NumeroLinha
            WHERE n.EhLinhaVazia = 1
              AND n.NumeroLinhaVazia > 2;

            /*
                Reconstrói o conteúdo na ordem original.
            */
            SELECT
                @ConteudoTratado =
                    STRING_AGG
                    (
                        CAST(Linha AS varchar(max)),
                        CHAR(10)
                    )
                    WITHIN GROUP
                    (
                        ORDER BY NumeroLinha
                    )
            FROM #Linhas;

            SET @ConteudoTratado =
                ISNULL(@ConteudoTratado, '');

            /*
                Acrescenta o título do post ao início do conteúdo tratado.

                Resultado:

                # Título do artigo

                Conteúdo...
            */
            SET @ConteudoTratado =
                '# ' + LTRIM(RTRIM(@Titulo))
                + CHAR(10) + CHAR(10)
                + @ConteudoTratado;

            /*
                Grava o resultado.
            */
            UPDATE dbo.BlogPosts
                SET Conteudo_Tratado = @ConteudoTratado
            WHERE PostId = @PostIdAtual;
        END TRY
        BEGIN CATCH
            CLOSE cursor_posts;
            DEALLOCATE cursor_posts;

            THROW;
        END CATCH;

        FETCH NEXT FROM cursor_posts
        INTO
            @PostIdAtual,
            @Titulo,
            @ConteudoOriginal;
    END;

    CLOSE cursor_posts;
    DEALLOCATE cursor_posts;
END;
GO