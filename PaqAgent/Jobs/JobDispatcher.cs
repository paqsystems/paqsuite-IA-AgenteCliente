using System.Diagnostics;

using Microsoft.Extensions.Logging;

using Microsoft.Extensions.Options;

using PaqAgent.Configuration;

using PaqAgent.Models;

using PaqAgent.Operations;

using PaqAgent.Security;

using PaqAgent.Services;



namespace PaqAgent.Jobs;



public class JobDispatcher

{

    private const string DiagnosticsOperation = "diagnostics.run";



    private readonly OperationRegistry _operationRegistry;

    private readonly AuthLoginOperation _authLoginOperation;

    private readonly DiagnosticsService _diagnosticsService;

    private readonly AgentAuthenticator _authenticator;

    private readonly AgentSettings _settings;

    private readonly ILogger<JobDispatcher> _logger;



    public JobDispatcher(

        OperationRegistry operationRegistry,

        AuthLoginOperation authLoginOperation,

        DiagnosticsService diagnosticsService,

        AgentAuthenticator authenticator,

        IOptions<AgentSettings> settings,

        ILogger<JobDispatcher> logger)

    {

        _operationRegistry = operationRegistry;

        _authLoginOperation = authLoginOperation;

        _diagnosticsService = diagnosticsService;

        _authenticator = authenticator;

        _settings = settings.Value;

        _logger = logger;

    }



    private void LogBeforeGatewaySend(string jobId)

    {

        _logger.LogInformation(

            "[PERF {TimestampUtc}] Antes de enviar resultado al Gateway JobId={JobId}",

            DateTime.UtcNow.ToString("HH:mm:ss.fff"), jobId);

    }



    public async Task<AgentJobResult> DispatchAsync(AgentJob job, CancellationToken cancellationToken = default)

    {

        var stopwatch = Stopwatch.StartNew();

        var timeoutSeconds = Math.Min(

            job.TimeoutSeconds > 0 ? job.TimeoutSeconds : _settings.DefaultTimeoutSeconds,

            _settings.MaxTimeoutSeconds);



        _logger.LogInformation("Ejecutando job {JobId}, operacion {Operation}, timeout {Timeout}s",

            job.JobId, job.Operation, timeoutSeconds);



        _logger.LogInformation(

            "[PERF {TimestampUtc}] Job recibido JobId={JobId} Operation={Operation}",

            DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



        try

        {

            if (!_authenticator.ValidateJob(job))

            {

                LogBeforeGatewaySend(job.JobId);

                return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                    ErrorCodes.InvalidParameters, "El job no corresponde a este agente.");

            }



            object? data;



            if (string.Equals(job.Operation, AuthLoginOperation.OperationName, StringComparison.OrdinalIgnoreCase))

            {

                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Antes de buscar handler JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                if (!_operationRegistry.IsAllowed(job.Operation))

                {

                    LogBeforeGatewaySend(job.JobId);

                    return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                        ErrorCodes.OperationNotAllowed,

                        $"La operacion '{job.Operation}' no esta en la lista blanca.");

                }



                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Handler encontrado JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                using var loginCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

                loginCts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));



                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Antes de ExecuteAsync JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                var loginResult = await _authLoginOperation.ExecuteAsync(

                    job.Parameters, timeoutSeconds, loginCts.Token);



                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Después de ExecuteAsync JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                stopwatch.Stop();



                if (!loginResult.IsSuccess)

                {

                    _logger.LogWarning(

                        "Job {JobId} auth.login fallo con codigo {ErrorCode}",

                        job.JobId,

                        loginResult.ErrorCode);



                    LogBeforeGatewaySend(job.JobId);

                    return JobResultFactory.Failed(

                        job.JobId,

                        _settings.AgentId,

                        stopwatch.ElapsedMilliseconds,

                        loginResult.ErrorCode ?? ErrorCodes.InternalError,

                        loginResult.ErrorMessage ?? "Error en autenticacion.");

                }



                _logger.LogInformation(

                    "Job {JobId} auth.login completado en {DurationMs}ms (password_hash omitido de logs)",

                    job.JobId,

                    stopwatch.ElapsedMilliseconds);



                LogBeforeGatewaySend(job.JobId);

                return JobResultFactory.Success(

                    job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds, loginResult.Data);

            }



            if (string.Equals(job.Operation, DiagnosticsOperation, StringComparison.OrdinalIgnoreCase))

            {

                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Antes de ExecuteAsync JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                data = await _diagnosticsService.RunDiagnosticsAsync(cancellationToken);



                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Después de ExecuteAsync JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);

            }

            else

            {

                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Antes de buscar handler JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                if (!_operationRegistry.IsAllowed(job.Operation))

                {

                    LogBeforeGatewaySend(job.JobId);

                    return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                        ErrorCodes.OperationNotAllowed,

                        $"La operacion '{job.Operation}' no esta en la lista blanca.");

                }



                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Handler encontrado JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

                cts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));



                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Antes de ExecuteAsync JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);



                data = await _operationRegistry.ExecuteAsync(

                    job.Operation, job.Parameters, timeoutSeconds, cts.Token);



                _logger.LogInformation(

                    "[PERF {TimestampUtc}] Después de ExecuteAsync JobId={JobId} Operation={Operation}",

                    DateTime.UtcNow.ToString("HH:mm:ss.fff"), job.JobId, job.Operation);

            }



            stopwatch.Stop();

            _logger.LogInformation("Job {JobId} completado en {DurationMs}ms", job.JobId, stopwatch.ElapsedMilliseconds);



            LogBeforeGatewaySend(job.JobId);

            return JobResultFactory.Success(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds, data);

        }

        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)

        {

            stopwatch.Stop();

            _logger.LogWarning("Job {JobId} excedio el timeout de {Timeout}s", job.JobId, timeoutSeconds);

            LogBeforeGatewaySend(job.JobId);

            return JobResultFactory.Timeout(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds);

        }

        catch (OperationNotAllowedException ex)

        {

            stopwatch.Stop();

            LogBeforeGatewaySend(job.JobId);

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.OperationNotAllowed, ex.Message);

        }

        catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == -2)

        {

            stopwatch.Stop();

            _logger.LogError(ex, "Timeout SQL en job {JobId}", job.JobId);

            LogBeforeGatewaySend(job.JobId);

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.SqlTimeout, "La consulta supero el tiempo maximo permitido.");

        }

        catch (Microsoft.Data.SqlClient.SqlException ex)

        {

            stopwatch.Stop();

            _logger.LogError(ex, "Error SQL en job {JobId}", job.JobId);

            LogBeforeGatewaySend(job.JobId);

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.SqlError, ex.Message);

        }

        catch (Exception ex)

        {

            stopwatch.Stop();

            _logger.LogError(ex, "Error interno en job {JobId}", job.JobId);

            LogBeforeGatewaySend(job.JobId);

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.InternalError, ex.Message);

        }

    }

}

