using AssettoServer.Server.Plugin;
using Autofac;

namespace DriftFactoryPlugin;

public class DriftFactoryModule : AssettoServerModule
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<DriftFactoryScript>().AsSelf().As<IAssettoServerAutostart>().SingleInstance();
    }
}
