using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TapGenerator.Api.Services;

namespace TapGenerator.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "TapGeneratorRole")]
public class UsersController : ControllerBase
{
    private readonly IGraphService _graph;

    public UsersController(IGraphService graph) => _graph = graph;

    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] string q, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(q) || q.Trim().Length < 2)
            return BadRequest(new { error = "Query must be at least 2 characters." });

        var results = await _graph.SearchUsersAsync(q.Trim(), ct);
        return Ok(results);
    }
}
