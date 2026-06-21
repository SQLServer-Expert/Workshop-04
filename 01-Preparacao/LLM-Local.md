## Workshop SQL Server Expert - 4ª Edição
### Construa Soluções com IA Dentro do SQL Server 2025

### 1️⃣ Instalando e Configurando LLM

***➡️ Ollama LLM***
Fazer download e instalar Ollama utilizando o link abaixo:
https://ollama.com/download/windows

***➡️ Proxy Caddy***
Fazer download do Proxy Caddy utilizando o link abaixo, salve o arquivo "caddy_windows_amd64.exe" em uma pasta local, por exemplo "C:\Caddy"
https://caddyserver.com/download

Em seguida crie um arquivo sem extensão chamado "Caddyfile." na mesma pasta onde está o executável do Caddy e salve o script abaixo no arquivo.

```text
{
  admin localhost:2019
}

localhost, 127.0.0.1 {
  tls internal

  @ollama path /api/* /v1/*
  reverse_proxy 127.0.0.1:11434 {
    flush_interval -1
  }

  @preflight {
    method OPTIONS
    path /api/* /v1/*
  }
  respond @preflight 204

  header @ollama {
    Access-Control-Allow-Origin  *
    Access-Control-Allow-Methods "GET, POST, OPTIONS"
    Access-Control-Allow-Headers "Content-Type, Authorization"
    Access-Control-Expose-Headers "*"
  }

  respond / "Caddy is running with HTTPS on localhost" 200

  log {
    output file C:\caddy\logs\ollama-local.log
    format console
  }
}

Agora em uma janela de Prompt (Command Window) execute a partir da mesma pasta do arquivo criado acima. Aparecendo uma janela confirmando a instalação de um certificado local responda "Yes".

```text
.\caddy_windows_amd64.exe run --config Caddyfile

Para garantir a instalação de certificado local, execute em outra janela de prompt o comando abaixo:

.\caddy_windows_amd64.exe trust

Agora precisamos testar se o Ollama está funcionando corretamente. Abra uma janela de PowerShell e execute o comando abaixo. Vai gerar um resultado sem nenhum modelo, pois ainda não instalamos.

```powershell
ollama list

O mesmo deve acontecer com o comando PowerShell abaixo, lista vazia:

```powershell
curl.exe http://localhost:11434/api/tags

Agora vamos instalar os modelos que serão utilizado no Workshop, um para 
https://ollama.com/library

ollama pull llama3.1:8b

ollama pull nomic-embed-text

