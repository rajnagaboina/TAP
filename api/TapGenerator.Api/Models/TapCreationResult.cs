namespace TapGenerator.Api.Models;

public record TapCreationResult(
    string? TemporaryAccessPass,
    int LifetimeInMinutes,
    DateTimeOffset? StartDateTime,
    bool IsUsableOnce
);
