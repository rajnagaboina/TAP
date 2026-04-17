using Microsoft.Graph.Models;

namespace TapGenerator.Api.Services;

public interface IGraphService
{
    Task<User?> GetUserAsync(string upnOrId, CancellationToken ct = default);
    Task<TemporaryAccessPassAuthenticationMethod> CreateTapAsync(
        string userId, int lifetimeInMinutes, CancellationToken ct = default);
    Task<bool> IsPrivilegedUserAsync(string userId, CancellationToken ct = default);
}
