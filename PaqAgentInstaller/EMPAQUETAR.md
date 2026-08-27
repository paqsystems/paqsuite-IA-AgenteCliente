# Instrucciones de empaquetado — PaqAgentInstaller

## Comando de publish

```bash
dotnet publish PaqAgentInstaller/PaqAgentInstaller.csproj \
  -r win-x64 \
  --self-contained false \
  -p:PublishSingleFile=true \
  -c Release
```

## Archivos a incluir en PaqAgentInstaller.zip

Carpeta de salida: `PaqAgentInstaller/bin/Release/net8.0-windows/win-x64/publish/`

Incluir en el zip:

- `PaqAgentInstaller.exe`
- `Microsoft.Data.SqlClient.SNI.dll`

NO incluir:

- `PaqAgentInstaller.pdb`
- Cualquier otro archivo .pdb o de símbolos

## Nota

`Microsoft.Data.SqlClient.SNI.dll` es una librería nativa requerida por el test de conexión SQL del installer. No puede ser empaquetada dentro del single-file por ser un binario nativo win-x64. Debe acompañar al .exe siempre.

## Prerequisito en el servidor destino

.NET 8 Desktop Runtime (x64) debe estar instalado.
Descarga: https://dotnet.microsoft.com/download/dotnet/8.0
