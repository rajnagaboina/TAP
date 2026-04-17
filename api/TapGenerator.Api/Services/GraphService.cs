using Microsoft.Graph;
using Microsoft.Graph.Models;
using Microsoft.Graph.Models.ODataErrors;

namespace TapGenerator.Api.Services;

public class GraphService : IGraphService
{
    private readonly GraphServiceClient _graph;
    private readonly ILogger<GraphService> _log;

    // Privileged directory roles that must never receive a TAP via this tool.
    // Role Template GUIDs from https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference
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

    public GraphService(GraphServiceClient graph, ILogger<GraphService> log)
    {
        _graph = graph;
        _log = log;
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
            // Fail safe: if we can't verify, block generation
            return true;
        }
    }

    public async Task<TemporaryAccessPassAuthenticationMethod> CreateTapAsync(
        string userId, int lifetimeInMinutes, CancellationToken ct = default)
    {
        var body = new TemporaryAccessPassAuthenticationMethod
        {
            LifetimeInMinutes = lifetimeInMinutes,
            IsUsableOnce = true,
        };

        return await _graph.Users[userId]
            .Authentication
            .TemporaryAccessPassMethods
            .PostAsync(body, cancellationToken: ct)
            ?? throw new InvalidOperationException("Graph returned null TAP response.");
    }
}
