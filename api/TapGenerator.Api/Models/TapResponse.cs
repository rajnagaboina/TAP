namespace TapGenerator.Api.Models;

public class TapResponse
{
    public string? TemporaryAccessPass { get; set; }
    public int LifetimeInMinutes { get; set; }
    public DateTimeOffset? StartDateTime { get; set; }
    public DateTimeOffset? MethodUsabilityReason { get; set; }
    public bool IsUsableOnce { get; set; }
}
