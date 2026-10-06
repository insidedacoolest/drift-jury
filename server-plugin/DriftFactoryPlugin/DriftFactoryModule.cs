using AssettoServer.Server.Plugin;
using Autofac;

namespace DriftFactoryPlugin;

public class DriftFactoryModule : AssettoServerModule<DriftFactoryConfiguration>
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<DriftFactoryScript>().AsSelf().As<IAssettoServerAutostart>().SingleInstance();
        builder.RegisterType<DriftFactoryCommunity>().AsSelf().As<IAssettoServerAutostart>().SingleInstance();
    }
}
