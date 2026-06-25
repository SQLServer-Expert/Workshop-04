## Workshop SQL Server Expert - 4ª Edição
### Construa Soluções com IA Dentro do SQL Server 2025

### ▶️ Restaurando Banco de Dados

Faça Download do arquivo de Backup "Landry_Blogs.bak" e posicione em uma pasta.

**Verificando a Media de Backup**
Utilize o comando baixo para verificar o conteúdo da media de backup.

```sql
RESTORE FILELISTONLY FROM DISK = 'C:\Backup\Landry_Blogs.bak'
```

No retorno você consegue verificar os nomes lógicos dos arquivos de dados e log, assim como a localização original de cada arquivo.

**Restaurando o Backup**
Utilize o comando baixo para restaurar o banco de dados "Landry_Blogs" utilizando a media de backup que você salvou, atenção para alterar a localização do arquivo de backup no comando RESTORE, além da localização dos arquivos de dados e log no seu computador!.

```sql
RESTORE DATABASE Landry_Blogs FROM DISK = 'C:\Backup\Landry_Blogs.bak' WITH recovery,
move 'Landry_Blogs' to 'C:\MSSQL_Data\Landry_Blogs.mdf',
move 'Landry_Blogs_log' to 'C:\MSSQL_Data\Landry_Blogs_log.ldf'
```
