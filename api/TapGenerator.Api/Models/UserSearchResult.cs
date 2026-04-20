namespace TapGenerator.Api.Models;

public record UserSearchResult(
    string DisplayName,
    string GivenName,
    string Surname,
    string Upn
);
