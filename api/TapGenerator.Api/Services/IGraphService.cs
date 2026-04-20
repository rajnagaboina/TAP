using Microsoft.Graph.Models;
using TapGenerator.Api.Models;

namespace TapGenerator.Api.Services;

public interface IGraphService
{
    Task<User?> GetUserAsync(string upnOrId, CancellationToken ct = default);
    Task<List<UserSearchResult>> SearchUsersAsync(string query, CancellationToken ct = default);
    Task<TapCreationResult> CreateTapAsync(string userId, int lifetimeInMinutes, CancellationToken ct = default);
    Task<bool> IsPrivilegedUserAsync(string userId, CancellationToken ct = default);
}
