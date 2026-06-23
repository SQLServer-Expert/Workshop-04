## Workshop SQL Server Expert - 4ª Edição
### Construa Soluções com IA Dentro do SQL Server 2025

### 1️⃣ Instalando e Configurando LLM

**➡️ Ollama LLM**
Fazer download e instalar Ollama utilizando o link abaixo:
https://ollama.com/download/windows

**➡️ Proxy Caddy**
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
```

Agora em uma janela de Prompt (Command Window) execute a partir da mesma pasta do arquivo criado acima. Aparecendo uma janela confirmando a instalação de um certificado local responda "Yes".
```text
.\caddy_windows_amd64.exe run --config Caddyfile
```

Para garantir a instalação de certificado local, execute em outra janela de prompt o comando abaixo:
```text
.\caddy_windows_amd64.exe trust
```

Agora precisamos importar o Certificado gerado para o Trusted Root do Windows, utilize o comando PowerShell abaixo para confirmar a localização do certificado:
```text
Get-ChildItem -Path "$env:APPDATA\Caddy\pki\authorities\local\" -ErrorAction SilentlyContinue
```

No comando abaixo importamos o certificado para o Trusted Root do Windows, utilizar janela PowerShell como administrador!
```text
Import-Certificate `
    -FilePath "$env:APPDATA\Caddy\pki\authorities\local\root.crt" `
    -CertStoreLocation Cert:\LocalMachine\Root
```

Para verificar a importação do certificado utilizar o comando PowerShell abaixo:
```text
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*Caddy*" }
```

Agora precisamos testar se o Ollama está funcionando corretamente. Abra uma janela de PowerShell e execute o comando abaixo. Vai gerar um resultado sem nenhum modelo, pois ainda não instalamos.

```powershell
ollama list
```

O mesmo deve acontecer com o comando PowerShell abaixo, lista vazia:

```powershell
curl.exe http://localhost:11434/api/tags
```

Agora vamos instalar os modelos que serão utilizado no Workshop, um para chat e outro para embeddings, você encontra a lista de modelos disponíveis no Ollama no link abaixo:
https://ollama.com/library

**PowerShell:** Instalando Modelo de Chat **mais leve**, recebe pergunta e gera resposta em linguagem natural.
```powershell
ollama pull llama3.1:8b
```

**PowerShell:** Instalando Modelo de Chat **mais pesado**, recebe pergunta e gera resposta em linguagem natural.
```powershell
ollama pull llama3.2:1b
```

**PowerShell:** Modelo de Embeddings da Google treinado com mais de 100 idiomas que transforma texto em vetor numérico.
```powershell
ollama pull embeddinggemma
```

**PowerShell:** Modelo de Embeddings **mais leve** que transforma texto em vetor numérico.
```powershell
ollama pull nomic-embed-text
```

**PowerShell:** Modelo de Embeddings **mais pesado** que transforma texto em vetor numérico.
```powershell
ollama pull mxbai-embed-large
```

**Command Prompt:** Teste utilizando Modelo de Chat com pergunta sobre índices.
```powershell
curl -H "Content-Type: application/json" -d "{\"model\":\"llama3.2:1b\",\"messages\":[{\"role\":\"system\",\"content\":\"You are a helpful assistant that explains database concepts clearly.\"},{\"role\":\"user\",\"content\":\"Explain the difference between clustered and nonclustered indexes in SQL Server.\"}],\"stream\":false}" http://localhost:11434/api/chat
```

**Command Prompt:** Teste utilizando Modelo de Chat via Proxy Caddy com pergunta sobre índices.
```powershell
curl --ssl-no-revoke -H "Content-Type: application/json" -d "{\"model\":\"llama3.2:1b\",\"messages\":[{\"role\":\"system\",\"content\":\"You are a helpful assistant that explains database concepts clearly.\"},{\"role\":\"user\",\"content\":\"Explain the difference between clustered and nonclustered indexes in SQL Server.\"}],\"stream\":false}" https://localhost/api/chat
```

**Command Prompt:** Teste utilizando Modelo de Chat via Proxy Caddy com pergunta sobre índices.
```powershell
curl --ssl-no-revoke -X POST https://localhost/api/embeddings -H "Content-Type: application/json" -d "{\"model\":\"mxbai-embed-large\",\"prompt\":\"The Dallas Cowboys are the best team in the NLF\"}"
```

