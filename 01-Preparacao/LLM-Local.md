## Workshop SQL Server Expert - 4ª Edição
### Construa Soluções com IA Dentro do SQL Server 2025

### ▶️ Instalando e Configurando LLM

**Ollama LLM**
Fazer download e instalar Ollama utilizando o link abaixo:
https://ollama.com/download/windows


Agora precisamos testar se o Ollama está funcionando corretamente. Abra uma janela de PowerShell e execute o comando abaixo. Vai gerar um resultado sem nenhum modelo, pois ainda não instalamos.

```powershell
ollama list
```

O mesmo deve acontecer com o comando PowerShell abaixo, lista vazia:

```powershell
curl.exe http://localhost:11434/api/tags
```

Agora vamos instalar os modelos que serão utilizado no Workshop, alguns para chat e outros para embeddings, você encontra a lista de modelos disponíveis no Ollama no link abaixo:
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

