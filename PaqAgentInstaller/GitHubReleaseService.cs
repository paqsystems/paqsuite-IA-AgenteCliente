using System.Net.Http.Headers;
using System.Text.Json;

namespace PaqAgentInstaller;

internal sealed class GitHubReleaseInfo
{
    public string TagName { get; init; } = "";
    public string Version { get; init; } = "";
    public string DownloadUrl { get; init; } = "";
}

internal sealed class GitHubReleaseService
{
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PaqAgent-Installer");
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        if (!string.IsNullOrWhiteSpace(Constants.GITHUB_TOKEN)
            && Constants.GITHUB_TOKEN != "CONFIGURAR-TOKEN-AQUI")
        {
            client.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", Constants.GITHUB_TOKEN);
        }

        return client;
    }

    public async Task<GitHubReleaseInfo> GetLatestReleaseAsync(CancellationToken cancellationToken = default)
    {
        var url = $"https://api.github.com/repos/{Constants.GITHUB_OWNER}/{Constants.GITHUB_REPO}/releases/latest";
        using var response = await Http.GetAsync(url, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = doc.RootElement;

        var tagName = root.GetProperty("tag_name").GetString() ?? "";
        var version = tagName.TrimStart('v', 'V');

        string? downloadUrl = null;
        if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
        {
            foreach (var asset in assets.EnumerateArray())
            {
                var name = asset.TryGetProperty("name", out var nameProp) ? nameProp.GetString() : null;
                if (name is null || !name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                    continue;

                downloadUrl = asset.TryGetProperty("browser_download_url", out var urlProp)
                    ? urlProp.GetString()
                    : null;
                if (!string.IsNullOrWhiteSpace(downloadUrl))
                    break;
            }
        }

        if (string.IsNullOrWhiteSpace(downloadUrl))
            throw new InvalidOperationException("El release más reciente no tiene un asset .zip.");

        return new GitHubReleaseInfo
        {
            TagName = tagName,
            Version = version,
            DownloadUrl = downloadUrl,
        };
    }

    public async Task DownloadReleaseAsync(
        string url,
        string destPath,
        IProgress<int>? progress = null,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        using var response = await Http.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        response.EnsureSuccessStatusCode();

        var total = response.Content.Headers.ContentLength ?? -1L;
        await using var remote = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var local = new FileStream(
            destPath,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None,
            81920,
            useAsync: true);

        var buffer = new byte[81920];
        long readTotal = 0;
        int read;
        var lastPercent = -1;

        while ((read = await remote.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) > 0)
        {
            await local.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            readTotal += read;

            if (total > 0 && progress is not null)
            {
                var percent = (int)Math.Min(100, readTotal * 100 / total);
                if (percent != lastPercent)
                {
                    lastPercent = percent;
                    progress.Report(percent);
                }
            }
        }

        progress?.Report(100);
    }
}
