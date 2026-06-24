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



    public async Task<AgentJobResult> DispatchAsync(AgentJob job, CancellationToken cancellationToken = default)

    {

        var stopwatch = Stopwatch.StartNew();

        var timeoutSeconds = Math.Min(

            job.TimeoutSeconds > 0 ? job.TimeoutSeconds : _settings.DefaultTimeoutSeconds,

            _settings.MaxTimeoutSeconds);



        _logger.LogInformation("Ejecutando job {JobId}, operacion {Operation}, timeout {Timeout}s",

            job.JobId, job.Operation, timeoutSeconds);



        try

        {

            if (!_authenticator.ValidateJob(job))

            {

                return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                    ErrorCodes.InvalidParameters, "El job no corresponde a este agente.");

            }



            object? data;



            if (string.Equals(job.Operation, AuthLoginOperation.OperationName, StringComparison.OrdinalIgnoreCase))

            {

                if (!_operationRegistry.IsAllowed(job.Operation))

                {

                    return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                        ErrorCodes.OperationNotAllowed,

                        $"La operacion '{job.Operation}' no esta en la lista blanca.");

                }



                using var loginCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

                loginCts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));



                var loginResult = await _authLoginOperation.ExecuteAsync(

                    job.Parameters, timeoutSeconds, loginCts.Token);



                stopwatch.Stop();



                if (!loginResult.IsSuccess)

                {

                    _logger.LogWarning(

                        "Job {JobId} auth.login fallo con codigo {ErrorCode}",

                        job.JobId,

                        loginResult.ErrorCode);



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



                return JobResultFactory.Success(

                    job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds, loginResult.Data);

            }



            if (string.Equals(job.Operation, DiagnosticsOperation, StringComparison.OrdinalIgnoreCase))

            {

                data = await _diagnosticsService.RunDiagnosticsAsync(cancellationToken);

            }

            else

            {

                if (!_operationRegistry.IsAllowed(job.Operation))

                {

                    return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                        ErrorCodes.OperationNotAllowed,

                        $"La operacion '{job.Operation}' no esta en la lista blanca.");

                }



                using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);

                cts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));



                data = await _operationRegistry.ExecuteAsync(

                    job.Operation, job.Parameters, timeoutSeconds, cts.Token);

            }



            stopwatch.Stop();

            _logger.LogInformation("Job {JobId} completado en {DurationMs}ms", job.JobId, stopwatch.ElapsedMilliseconds);



            return JobResultFactory.Success(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds, data);

        }

        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)

        {

            stopwatch.Stop();

            _logger.LogWarning("Job {JobId} excedio el timeout de {Timeout}s", job.JobId, timeoutSeconds);

            return JobResultFactory.Timeout(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds);

        }

        catch (OperationNotAllowedException ex)

        {

            stopwatch.Stop();

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.OperationNotAllowed, ex.Message);

        }

        catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == -2)

        {

            stopwatch.Stop();

            _logger.LogError(ex, "Timeout SQL en job {JobId}", job.JobId);

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.SqlTimeout, "La consulta supero el tiempo maximo permitido.");

        }

        catch (Microsoft.Data.SqlClient.SqlException ex)

        {

            stopwatch.Stop();

            _logger.LogError(ex, "Error SQL en job {JobId}", job.JobId);

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.SqlError, ex.Message);

        }

        catch (Exception ex)

        {

            stopwatch.Stop();

            _logger.LogError(ex, "Error interno en job {JobId}", job.JobId);

            return JobResultFactory.Failed(job.JobId, _settings.AgentId, stopwatch.ElapsedMilliseconds,

                ErrorCodes.InternalError, ex.Message);

        }

    }

}

