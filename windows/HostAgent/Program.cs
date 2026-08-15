using ToInfinity.HostAgent;
using ToInfinity.HostAgent.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);

builder.Services.Configure<HostAgentOptions>(builder.Configuration.GetSection("ToInfinity"));
builder.Services.AddSingleton(sp => sp.GetRequiredService<Microsoft.Extensions.Options.IOptions<HostAgentOptions>>().Value);

builder.Services.AddSingleton(sp =>
{
    var options = sp.GetRequiredService<HostAgentOptions>();
    return DeviceIdentity.LoadOrCreate(options.DeviceName);
});

builder.Services.AddSingleton<PairingGate>();
builder.Services.AddSingleton<InputInjector>();
builder.Services.AddSingleton<DesktopDuplicationCapture>();
builder.Services.AddSingleton<ControlChannelServer>();
builder.Services.AddSingleton<VideoStreamServer>();
builder.Services.AddSingleton<DiscoveryResponder>();

builder.Services.AddHostedService<Worker>();

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "toInfinity HostAgent";
});

IHost host = builder.Build();
host.Run();
