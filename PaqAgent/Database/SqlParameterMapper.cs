using System.Text.Json;

namespace PaqAgent.Database;

public static class SqlParameterMapper
{
    public static Dictionary<string, object?> MapParameters(
        Dictionary<string, object?> input,
        IEnumerable<string> allowedParameters)
    {
        var allowed = new HashSet<string>(allowedParameters, StringComparer.OrdinalIgnoreCase);
        var result = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);

        foreach (var (key, value) in input)
        {
            if (!allowed.Contains(key))
                continue;

            result[key] = ConvertValue(value);
        }

        return result;
    }

    private static object? ConvertValue(object? value)
    {
        if (value is null)
            return null;

        if (value is JsonElement element)
        {
            return element.ValueKind switch
            {
                JsonValueKind.String => element.GetString(),
                JsonValueKind.Number when element.TryGetInt32(out var i) => i,
                JsonValueKind.Number when element.TryGetInt64(out var l) => l,
                JsonValueKind.Number => element.GetDecimal(),
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.Null => null,
                _ => element.ToString()
            };
        }

        return value;
    }
}
