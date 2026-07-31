/*
===============================================================================
Workshop SQL Server Expert 4ª edição
Construa Soluções com IA no SQL Server 2025

Hands On: Engenharia de Prompt

Objetivo:
Demonstrar o uso dos prompts de sistema e usuário em chamadas para uma
LLM local utilizando SQL Server, Ollama e Caddy.

Ambiente:
- SQL Server 2025
- Ollama
- Caddy

Autor: Landry Duailibe | SQL Server Expert
===============================================================================
*/
use Aula
go

/***********************************************
 Habilitando recursos de IA no banco corrente
************************************************/
-- Habilitar preview features (necessário no SQL Server 2025)
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON

-- Habilitar as Funcionalidades de AI
EXECUTE sp_configure 'external AI runtimes enabled', 1
RECONFIGURE WITH OVERRIDE

EXECUTE sp_configure 'external rest endpoint enabled', 1
RECONFIGURE WITH OVERRIDE

/*****************************************
 Cria SP para Chamada Chat com LLM Local
*****************************************/
EXEC dbo.spAI_Chat_Ollama
@pSystem = 'Você é um assistente especializado em bancos de dados Microsoft SQL Server que explica conceitos de forma clara e objetiva',
@pUser = 'Explique o que é o Banco de Dados de Sistema TempDB'
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


/*******************************************
 Prompt Sistema: Role Prompting
 Prompt Usuário: Zero-shot
********************************************/
-- Execute o Proxy Local Caddy antes:
-- c:\caddy\caddy_windows_amd64.exe run --config c:\caddy\Caddyfile

EXEC dbo.spAI_Chat_Ollama 
@pSystem = N'
Você é um assistente especializado em bancos de dados Microsoft SQL Server 
que explica conceitos de forma clara e objetiva.', 

@pUser = N'Explique o que é o Banco de Dados de Sistema TempDB.'


/*******************************************
 Prompt Sistema: 
 - Role Prompting: "Você é um professor especializado em Microsoft SQL Server."
 - Constraints: "Explique os conceitos em português..."
                "utilizando linguagem clara e objetiva"
                "Sempre que possível, utilize exemplos..."
 - Contextual Prompting: "...utilize exemplos relacionados ao trabalho de DBAs e desenvolvedores SQL."

 Prompt Usuário: 
 - Zero-shot: "Explique o que é o banco de dados de sistema TempDB..."
 - Contextual Prompting: "...para um desenvolvedor SQL iniciante."
 - Decomposição: "
   Inclua:
     - sua finalidade;
     - os principais objetos armazenados;
     - exemplos de uso;
     - cuidados básicos de configuração."

 - Output Formatting: "Organize a resposta em tópicos" e "Finalize com um resumo."
********************************************/
EXEC dbo.spAI_Chat_Ollama
@pSystem = '
Você é um professor especializado em Microsoft SQL Server.
Explique os conceitos em português, utilizando linguagem clara e objetiva.
Sempre que possível, utilize exemplos relacionados ao trabalho de DBAs e desenvolvedores SQL.',

@pUser = '
Explique o que é o banco de dados de sistema TempDB para um desenvolvedor SQL iniciante.

Inclua:
- sua finalidade;
- os principais objetos armazenados;
- exemplos de uso;
- cuidados básicos de configuração.

Organize a resposta em tópicos e finalize com um resumo.'
