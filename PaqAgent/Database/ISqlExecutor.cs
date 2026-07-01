namespace PaqAgent.Database;



public interface ISqlExecutor

{

    Task<List<Dictionary<string, object?>>> ExecuteStoredProcedureAsync(

        string storedProcedure,

        Dictionary<string, object?> parameters,

        int timeoutSeconds,

        string? databaseOverride = null,

        CancellationToken cancellationToken = default);



    Task<IReadOnlyList<IReadOnlyList<Dictionary<string, object?>>>> ExecuteStoredProcedureMultiResultAsync(

        string storedProcedure,

        Dictionary<string, object?> parameters,

        int timeoutSeconds,

        CancellationToken cancellationToken = default);



    Task<bool> TestConnectionAsync(CancellationToken cancellationToken = default);



    Task ExecuteNonQueryAsync(

        string sql,

        int timeoutSeconds,

        CancellationToken cancellationToken = default);



    Task ExecuteNonQueryAsync(

        string sql,

        Dictionary<string, object?> parameters,

        int timeoutSeconds,

        CancellationToken cancellationToken = default);



    Task<IReadOnlyList<string>> QueryStringColumnAsync(

        string sql,

        string columnName,

        int timeoutSeconds,

        CancellationToken cancellationToken = default);

}

