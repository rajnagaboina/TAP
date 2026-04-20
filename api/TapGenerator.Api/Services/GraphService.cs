using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Microsoft.Graph;
using Microsoft.Graph.Models;
using Microsoft.Graph.Models.ODataErrors;
using TapGenerator.Api.Models;

namespace TapGenerator.Api.Services;

public class GraphService : IGraphService
{
    private readonly GraphServiceClient _graph;
    private readonly TokenCredential _credential;
    private readonly ILogger<GraphService> _log;
    private readonly IHttpClientFactory _httpFactory;

    private static readonly HashSet<string> PrivilegedRoleTemplateIds = new(StringComparer.OrdinalIgnoreCase)
    {
        "62e90394-69f5-4237-9190-012177145e10", // Global Administrator
        "e8611ab8-c189-46e8-94e1-60213ab1f814", // Privileged Role Administrator
        "194ae4cb-b126-40b2-bd5b-6091b380977d", // Security Administrator
        "7be44c8a-adaf-4e2a-84d6-ab2649e08a13", // Privileged Authentication Administrator
        "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", // Authentication Administrator
        "c4e39bd9-1100-46d3-8c65-fb160da0071f", // Authentication Policy Administrator
        "966707d0-3269-4727-9be2-8c3a10f19b9d", // Password Administrator
    };

    public GraphService(GraphServiceClient graph, ILogger<GraphService> log, IHttpClientFactory httpFactory)
    {
        _graph      = graph;
        _log        = log;
        _httpFactory = httpFactory;
        _credential = new DefaultAzureCredential();
    }

    public async Task<User?> GetUserAsync(string upnOrId, CancellationToken ct = default)
    {
        try
        {
            return await _graph.Users[upnOrId]
                .GetAsync(req =>
                {
                    req.QueryParameters.Select = ["id", "userPrincipalName", "displayName", "accountEnabled"];
                }, ct);
        }
        catch (ODataError ex) when (ex.ResponseStatusCode == 404)
        {
            return null;
        }
    }

    public async Task<bool> IsPrivilegedUserAsync(string userId, CancellationToken ct = default)
    {
        try
        {
            var roles = await _graph.Users[userId].TransitiveMemberOf
                .GraphDirectoryRole
                .GetAsync(req =>
                {
                    req.QueryParameters.Select = ["roleTemplateId", "displayName"];
                }, ct);

            if (roles?.Value is null) return false;

            return roles.Value.Any(r =>
                r.RoleTemplateId is not null &&
                PrivilegedRoleTemplateIds.Contains(r.RoleTemplateId));
        }
        catch (ODataError ex)
        {
            _log.LogWarning("Could not retrieve roles for user {UserId}: {Error}", userId, ex.Message);
            return true;
        }
    }

    public async Task<List<UserSearchResult>> SearchUsersAsync(string query, CancellationToken ct = default)
    {
        var result = await _graph.Users.GetAsync(req =>
        {
            req.QueryParameters.Search  = $"\"displayName:{query}\" OR \"userPrincipalName:{query}\"";
            req.QueryParameters.Select  = ["displayName", "givenName", "surname", "userPrincipalName", "accountEnabled"];
            req.QueryParameters.Top     = 10;
            req.QueryParameters.Orderby = ["displayName"];
            req.Headers.Add("ConsistencyLevel", "eventual");
        }, ct);

        return result?.Value?
            .Where(u => u.AccountEnabled != false && u.UserPrincipalName != null)
            .Select(u => new UserSearchResult(
                u.DisplayName ?? "",
                u.GivenName ?? "",
                u.Surname ?? "",
                u.UserPrincipalName!))
            .ToList() ?? [];
    }

    public async Task<TapCreationResult> CreateTapAsync(
        string userId, int lifetimeInMinutes, CancellationToken ct = default)
    {
        var token = await _credential.GetTokenAsync(
            new TokenRequestContext(["https://graph.microsoft.com/.default"]), ct);

        var url     = $"https://graph.microsoft.com/v1.0/users/{userId}/authentication/temporaryAccessPassMethods";
        var payload = JsonSerializer.Serialize(new { lifetimeInMinutes, isUsableOnce = true });

        using var http = _httpFactory.CreateClient();
        using var req  = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        req.Content = new StringContent(payload, Encoding.UTF8, "application/json");

        using var resp = await http.SendAsync(req, ct);
        var raw = await resp.Content.ReadAsStringAsync(ct);

        _log.LogInformation("Graph TAP HTTP {Status} – body: {Body}", (int)resp.StatusCode, raw);

        if (!resp.IsSuccessStatusCode)
        {
            JsonDocument? errDoc = null;
            try { errDoc = JsonDocument.Parse(raw); } catch { }
            var message = errDoc is not null &&
                          errDoc.RootElement.TryGetProperty("error", out var errEl) &&
                          errEl.TryGetProperty("message", out var msgEl)
                ? msgEl.GetString() ?? raw
                : raw;
            throw new InvalidOperationException($"Graph {(int)resp.StatusCode}: {message}");
        }

        using var doc  = JsonDocument.Parse(raw);
        var root = doc.RootElement;

        string? pass = root.TryGetProperty("temporaryAccessPass", out var passProp)
                       && passProp.ValueKind != JsonValueKind.Null
            ? passProp.GetString()
            : null;

        int lifetime = root.TryGetProperty("lifetimeInMinutes", out var lifeProp)
            ? lifeProp.GetInt32()
            : lifetimeInMinutes;

        DateTimeOffset? startDt = root.TryGetProperty("startDateTime", out var startProp)
                                  && startProp.ValueKind != JsonValueKind.Null
            ? DateTimeOffset.Parse(startProp.GetString()!)
            : null;

        bool once = root.TryGetProperty("isUsableOnce", out var onceProp)
            ? onceProp.GetBoolean()
            : true;

        _log.LogInformation(
            "Graph TAP parsed – PassIsNull: {Null}, PassLength: {Len}, Lifetime: {Min}",
            pass is null, pass?.Length ?? -1, lifetime);

        return new TapCreationResult(pass, lifetime, startDt, once);
    }
}
