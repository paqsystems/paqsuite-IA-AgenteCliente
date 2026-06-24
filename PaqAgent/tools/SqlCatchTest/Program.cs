using System.Data;
using Microsoft.Data.SqlClient;

static string GetArg(string[] args, string name, string defaultValue)
{
    for (var i = 0; i < args.Length - 1; i++)
    {
        if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
            return args[i + 1];
    }
    return defaultValue;
}

var server = GetArg(args, "--server", "192.168.41.2");
var database = GetArg(args, "--database", "Diccionario_000205_012");
var user = GetArg(args, "--user", "Axoft");
var password = GetArg(args, "--password", "Axoft");

var builder = new SqlConnectionStringBuilder
{
    DataSource = server,
    InitialCatalog = database,
    UserID = user,
    Password = password,
    Encrypt = false,
    TrustServerCertificate = true,
    ConnectTimeout = 30
};

var deploySp = args.Contains("--deploy");
var spName = "dbo.PAQ_Auth_Login_CatchTest";

Console.WriteLine("=== SqlCatchTest — replica SqlExecutor.ExecuteStoredProcedureAsync ===");
Console.WriteLine($"Server: {server}, Database: {database}");
Console.WriteLine();

await using var connection = new SqlConnection(builder.ConnectionString);
try
{
    await connection.OpenAsync();
    Console.WriteLine("[OK] Conexion abierta");
}
catch (Exception ex)
{
    Console.WriteLine("[FAIL] No se pudo conectar:");
    Console.WriteLine(ex.GetType().FullName);
    Console.WriteLine(ex.Message);
    return 1;
}

if (deploySp)
{
    var sqlPath = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "sql", "tests", "PAQ_Auth_Login_CatchTest.sql");
    sqlPath = Path.GetFullPath(sqlPath);
    if (!File.Exists(sqlPath))
    {
        sqlPath = @"D:\PaqSystems\paqsuite-IA-AgenteCliente\PaqAgent\sql\tests\PAQ_Auth_Login_CatchTest.sql";
    }

    var ddl = await File.ReadAllTextAsync(sqlPath);
    Console.WriteLine($"[DEPLOY] Ejecutando DDL desde: {sqlPath}");
    await using var deployCmd = new SqlCommand(ddl, connection) { CommandTimeout = 60 };
    await deployCmd.ExecuteNonQueryAsync();
    Console.WriteLine("[DEPLOY] SP creado/actualizado");
    Console.WriteLine();
}

var infoMessages = new List<string>();
connection.InfoMessage += (_, e) =>
{
    var text = e.Message ?? string.Empty;
    infoMessages.Add(text);
    Console.WriteLine($"[InfoMessage] Errors={e.Errors.Count}, Source={e.Source}, Text={text}");
    foreach (SqlError err in e.Errors)
    {
        Console.WriteLine($"  SqlError: Class={err.Class}, State={err.State}, Number={err.Number}, Line={err.LineNumber}, Message={err.Message}");
    }
};

Console.WriteLine($"[EXEC] {spName}");
Console.WriteLine();

Exception? caughtException = null;
List<Dictionary<string, object?>> results = new();

try
{
    results = await ExecuteStoredProcedureAsync(connection, spName, new Dictionary<string, object?>(), 30);
    Console.WriteLine("[RESULT] ExecuteStoredProcedureAsync termino SIN excepcion");
}
catch (Exception ex)
{
    caughtException = ex;
    Console.WriteLine("[RESULT] ExecuteStoredProcedureAsync lanzo excepcion:");
    PrintExceptionChain(ex);
}

Console.WriteLine();
Console.WriteLine($"InfoMessages capturados: {infoMessages.Count}");
Console.WriteLine($"Filas result set 1: {results.Count}");

if (results.Count > 0)
{
    Console.WriteLine("[RESULT SET 1 — fila 0]");
    foreach (var (key, value) in results[0])
        Console.WriteLine($"  {key} = {value ?? "NULL"}");
}

Console.WriteLine();
Console.WriteLine("=== RESUMEN ===");
Console.WriteLine($"Excepcion .NET: {(caughtException is null ? "NO" : caughtException.GetType().Name)}");
Console.WriteLine($"SqlException: {(caughtException is SqlException ? "SI" : "NO")}");
Console.WriteLine($"InfoMessage (RAISERROR sev 0): {(infoMessages.Count > 0 ? "SI" : "NO")}");
if (results.Count > 0 && results[0].TryGetValue("status", out var status))
    Console.WriteLine($"status en result set: {status}");

return caughtException is null ? 0 : 2;

static async Task<List<Dictionary<string, object?>>> ExecuteStoredProcedureAsync(
    SqlConnection connection,
    string storedProcedure,
    Dictionary<string, object?> parameters,
    int timeoutSeconds,
    CancellationToken cancellationToken = default)
{
    var results = new List<Dictionary<string, object?>>();

    await using var command = new SqlCommand(storedProcedure, connection)
    {
        CommandType = CommandType.StoredProcedure,
        CommandTimeout = timeoutSeconds
    };

    foreach (var (name, value) in parameters)
    {
        var paramName = name.StartsWith('@') ? name : $"@{name}";
        command.Parameters.AddWithValue(paramName, value ?? DBNull.Value);
    }

    await using var reader = await command.ExecuteReaderAsync(cancellationToken);

    while (await reader.ReadAsync(cancellationToken))
    {
        var row = new Dictionary<string, object?>();
        for (var i = 0; i < reader.FieldCount; i++)
        {
            var columnName = reader.GetName(i);
            var cellValue = reader.IsDBNull(i) ? null : reader.GetValue(i);
            row[columnName] = cellValue;
        }
        results.Add(row);
    }

    return results;
}

static void PrintExceptionChain(Exception ex)
{
    var depth = 0;
    while (ex is not null)
    {
        Console.WriteLine($"  [{depth}] {ex.GetType().FullName}: {ex.Message}");
        if (ex is SqlException sqlEx)
        {
            foreach (SqlError err in sqlEx.Errors)
            {
                Console.WriteLine($"      SqlError Class={err.Class} Number={err.Number} State={err.State}: {err.Message}");
            }
        }
        ex = ex.InnerException!;
        depth++;
        if (depth > 5) break;
    }
}
