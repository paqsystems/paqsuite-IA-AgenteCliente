Necesito crear un agente local en C# .NET 8 como Worker Service instalable como Windows Service.

El agente debe conectarse a un backend remoto mediante SignalR Client o WebSocket, autenticarse con AgentId y AgentToken, mantener heartbeat, recibir jobs, ejecutar operaciones permitidas contra SQL Server local mediante Microsoft.Data.SqlClient, devolver resultados en JSON, manejar timeouts, logs con Serilog y reintentos con Polly.

No debe ejecutar SQL libre recibido desde el servidor. Debe usar una lista blanca de operaciones configurables, por ejemplo clientes.listar, articulos.listar, saldos.consultar, cada una asociada a una stored procedure o query parametrizada.

Generar la estructura inicial del proyecto, clases de configuración, servicio principal, cliente SignalR, ejecutor SQL, modelo de Job, modelo de respuesta, manejo de errores y ejemplo de instalación como Windows Service.