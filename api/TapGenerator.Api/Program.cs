using Azure.Identity;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Graph;
using Microsoft.Identity.Web;
using Microsoft.OpenApi.Models;
using TapGenerator.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// ── Authentication & Authorization ──────────────────────────────────────────
builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration, "AzureAd");

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("TapGeneratorRole", policy =>
        policy.RequireAuthenticatedUser()
              .RequireRole("TAP.Generator"));
});

// ── Microsoft Graph (Managed Identity in production, developer creds locally) ─
builder.Services.AddSingleton<GraphServiceClient>(_ =>
{
    var credential = new DefaultAzureCredential();
    return new GraphServiceClient(credential, ["https://graph.microsoft.com/.default"]);
});

// ── Application services ─────────────────────────────────────────────────────
builder.Services.AddScoped<IGraphService, GraphService>();

// ── Application Insights ─────────────────────────────────────────────────────
builder.Services.AddApplicationInsightsTelemetry();

// ── Controllers & OpenAPI ────────────────────────────────────────────────────
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title   = "TAP Generator API",
        Version = "v1",
        Description = "Issues one-time Microsoft Entra Temporary Access Passes for non-privileged users."
    });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Type        = SecuritySchemeType.Http,
        Scheme      = JwtBearerDefaults.AuthenticationScheme,
        BearerFormat = "JWT",
        Description = "Paste the Entra access token with TAP.Generator role."
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" } },
            Array.Empty<string>()
        }
    });

    // Include XML doc comments in Swagger UI
    var xmlFile = $"{System.Reflection.Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath)) c.IncludeXmlComments(xmlPath);
});

// ── Health checks ─────────────────────────────────────────────────────────────
builder.Services.AddHealthChecks();

var app = builder.Build();

// ── Middleware pipeline ───────────────────────────────────────────────────────
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();
