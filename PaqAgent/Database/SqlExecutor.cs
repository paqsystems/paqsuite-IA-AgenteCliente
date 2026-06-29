using System.Data;

using Microsoft.Data.SqlClient;

using Microsoft.Extensions.Logging;

using Microsoft.Extensions.Options;

using PaqAgent.Configuration;



namespace PaqAgent.Database;



public class SqlExecutor : ISqlExecutor

{

    private readonly SqlConnectionSettings _settings;

    private readonly ILogger<SqlExecutor> _logger;



    public SqlExecutor(IOptions<SqlConnectionSettings> settings, ILogger<SqlExecutor> logger)

    {

        _settings = settings.Value;

        _logger = logger;

    }



    public async Task<List<Dictionary<string, object?>>> ExecuteStoredProcedureAsync(

        string storedProcedure,

        Dictionary<string, object?> parameters,

        int timeoutSeconds,

        CancellationToken cancellationToken = default)

    {

        var resultSets = await ExecuteStoredProcedureMultiResultAsync(

            storedProcedure, parameters, timeoutSeconds, cancellationToken);



        return resultSets.Count > 0

            ? resultSets[0].ToList()

            : new List<Dictionary<string, object?>>();

    }



    public async Task<IReadOnlyList<IReadOnlyList<Dictionary<string, object?>>>> ExecuteStoredProcedureMultiResultAsync(

        string storedProcedure,

        Dictionary<string, object?> parameters,

        int timeoutSeconds,

        CancellationToken cancellationToken = default)

    {

        await using var connection = new SqlConnection(_settings.BuildConnectionString());

        await connection.OpenAsync(cancellationToken);



        await using var command = BuildCommand(storedProcedure, parameters, timeoutSeconds, connection);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);



        var allResultSets = new List<IReadOnlyList<Dictionary<string, object?>>>();



        do

        {

            allResultSets.Add(await ReadResultSetAsync(reader, cancellationToken));

        }

        while (await reader.NextResultAsync(cancellationToken));



        _logger.LogDebug(

            "SP {StoredProcedure} ejecutado, {ResultSetCount} result sets",

            storedProcedure,

            allResultSets.Count);



        return allResultSets;

    }



    public async Task<bool> TestConnectionAsync(CancellationToken cancellationToken = default)

    {

        try

        {

            await using var connection = new SqlConnection(_settings.BuildConnectionString());

            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand("SELECT 1", connection);

            await command.ExecuteScalarAsync(cancellationToken);

            return true;

        }

        catch (Exception ex)

        {

            _logger.LogError(ex, "Error al probar conexion SQL");

            return false;

        }

    }



    public async Task ExecuteNonQueryAsync(

        string sql,

        int timeoutSeconds,

        CancellationToken cancellationToken = default)

    {

        await ExecuteNonQueryAsync(sql, new Dictionary<string, object?>(), timeoutSeconds, cancellationToken);

    }



    public async Task ExecuteNonQueryAsync(

        string sql,

        Dictionary<string, object?> parameters,

        int timeoutSeconds,

        CancellationToken cancellationToken = default)

    {

        await using var connection = new SqlConnection(_settings.BuildConnectionString());

        await connection.OpenAsync(cancellationToken);



        await using var command = new SqlCommand(sql, connection)

        {

            CommandType = CommandType.Text,

            CommandTimeout = timeoutSeconds

        };



        foreach (var (name, value) in parameters)

        {

            var paramName = name.StartsWith('@') ? name : $"@{name}";

            command.Parameters.AddWithValue(paramName, value ?? DBNull.Value);

        }



        await command.ExecuteNonQueryAsync(cancellationToken);

    }



    public async Task<IReadOnlyList<string>> QueryStringColumnAsync(

        string sql,

        string columnName,

        int timeoutSeconds,

        CancellationToken cancellationToken = default)

    {

        await using var connection = new SqlConnection(_settings.BuildConnectionString());

        await connection.OpenAsync(cancellationToken);



        await using var command = new SqlCommand(sql, connection)

        {

            CommandType = CommandType.Text,

            CommandTimeout = timeoutSeconds

        };



        var values = new List<string>();

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);



        var columnOrdinal = reader.GetOrdinal(columnName);



        while (await reader.ReadAsync(cancellationToken))

        {

            values.Add(reader.IsDBNull(columnOrdinal)

                ? string.Empty

                : reader.GetString(columnOrdinal));

        }



        return values;

    }



    private static SqlCommand BuildCommand(

        string storedProcedure,

        Dictionary<string, object?> parameters,

        int timeoutSeconds,

        SqlConnection connection)

    {

        var command = new SqlCommand(storedProcedure, connection)

        {

            CommandType = CommandType.StoredProcedure,

            CommandTimeout = timeoutSeconds

        };



        foreach (var (name, value) in parameters)

        {

            var paramName = name.StartsWith('@') ? name : $"@{name}";

            command.Parameters.AddWithValue(paramName, value ?? DBNull.Value);

        }



        return command;

    }



    private static async Task<List<Dictionary<string, object?>>> ReadResultSetAsync(

        SqlDataReader reader,

        CancellationToken cancellationToken)

    {

        var results = new List<Dictionary<string, object?>>();



        while (await reader.ReadAsync(cancellationToken))

        {

            var row = new Dictionary<string, object?>();

            for (var i = 0; i < reader.FieldCount; i++)

            {

                var columnName = reader.GetName(i);

                var value = reader.IsDBNull(i) ? null : reader.GetValue(i);

                row[columnName] = value;

            }

            results.Add(row);

        }



        return results;

    }

}

