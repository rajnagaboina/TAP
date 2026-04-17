using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Graph.Models.ODataErrors;
using TapGenerator.Api.Models;
using TapGenerator.Api.Services;

namespace TapGenerator.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = "TapGeneratorRole")]
public class TapController : ControllerBase
{
    private static readonly int[] AllowedDurations = [15, 30, 45, 60];

    private readonly IGraphService _graph;
    private readonly ILogger<TapController> _log;

    public TapController(IGraphService graph, ILogger<TapController> log)
    {
        _graph = graph;
        _log = log;
    }

    /// <summary>
    /// Generate a one-time Temporary Access Pass for the specified non-privileged user.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(TapResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> CreateTap(
        [FromBody] TapRequest request,
        CancellationToken ct)
    {
        if (!AllowedDurations.Contains(request.LifetimeInMinutes))
            return BadRequest(new { error = "lifetimeInMinutes must be 15, 30, 45, or 60." });

        var operatorUpn = User.FindFirst("preferred_username")?.Value
            ?? User.FindFirst("upn")?.Value
            ?? "unknown";

        _log.LogInformation("TAP requested – target: {Target}, duration: {Mins}m, by: {Operator}",
            request.TargetUpn, request.LifetimeInMinutes, operatorUpn);

        var targetUser = await _graph.GetUserAsync(request.TargetUpn, ct);
        if (targetUser is null)
            return NotFound(new { error = $"User '{request.TargetUpn}' not found." });

        if (targetUser.AccountEnabled == false)
            return BadRequest(new { error = "Target account is disabled." });

        // Defense-in-depth: block privileged targets even though APIM already checked the operator role.
        bool isPrivileged = await _graph.IsPrivilegedUserAsync(targetUser.Id!, ct);
        if (isPrivileged)
        {
            _log.LogWarning("TAP BLOCKED – target {Target} holds a privileged role, by {Operator}",
                request.TargetUpn, operatorUpn);
            return StatusCode(StatusCodes.Status403Forbidden,
                new { error = "TAP cannot be generated for users with privileged directory roles." });
        }

        try
        {
            var tap = await _graph.CreateTapAsync(targetUser.Id!, request.LifetimeInMinutes, ct);

            // NOTE: TAP value is intentionally NOT logged.
            _log.LogInformation("TAP created – target: {Target}, duration: {Mins}m, by: {Operator}",
                request.TargetUpn, request.LifetimeInMinutes, operatorUpn);

            if (string.IsNullOrEmpty(tap.TemporaryAccessPass))
            {
                _log.LogError("Graph returned a TAP with null/empty pass for {Target}. Check Managed Identity has UserAuthenticationMethod.ReadWrite.All.", request.TargetUpn);
                return StatusCode(500, new { error = "TAP was created but the pass code was not returned by Microsoft Graph. Verify the Managed Identity has UserAuthenticationMethod.ReadWrite.All permission." });
            }

            return Ok(new TapResponse
            {
                TemporaryAccessPass = tap.TemporaryAccessPass,
                LifetimeInMinutes   = tap.LifetimeInMinutes ?? request.LifetimeInMinutes,
                StartDateTime       = tap.StartDateTime,
                IsUsableOnce        = tap.IsUsableOnce ?? true,
            });
        }
        catch (ODataError ex)
        {
            _log.LogError(ex, "Graph OData error creating TAP for {Target}", request.TargetUpn);

            return ex.ResponseStatusCode switch
            {
                400 => BadRequest(new { error = "Graph rejected the TAP request. A TAP may already exist for this user.", detail = ex.Error?.Message }),
                403 => StatusCode(403, new { error = "Managed Identity lacks UserAuthenticationMethod.ReadWrite.All permission." }),
                _   => StatusCode(500, new { error = "An unexpected error occurred." })
            };
        }
        catch (InvalidOperationException ex)
        {
            _log.LogError(ex, "Graph HTTP error creating TAP for {Target}", request.TargetUpn);
            var msg = ex.Message;
            if (msg.StartsWith("Graph 400:"))
                return BadRequest(new { error = "Graph rejected the TAP request. A TAP may already exist for this user.", detail = msg });
            if (msg.StartsWith("Graph 403:"))
                return StatusCode(403, new { error = "Managed Identity lacks UserAuthenticationMethod.ReadWrite.All permission." });
            return StatusCode(500, new { error = msg });
        }
    }
}
