using System.ComponentModel.DataAnnotations;

namespace TapGenerator.Api.Models;

public class TapRequest
{
    [Required]
    [EmailAddress]
    public string TargetUpn { get; set; } = string.Empty;

    [Required]
    [Range(15, 60)]
    public int LifetimeInMinutes { get; set; }
}
