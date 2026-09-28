#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QResource>

#include <cstdio>
#include <sys/resource.h>

namespace
{
    constexpr qint64 MAX_THEME_RESOURCE_SIZE = 64 * 1024 * 1024;
    constexpr qint64 MAX_CONFIG_SIZE = 1024 * 1024;

    bool limitResources()
    {
        const rlimit cpuLimit {2, 2};
        if (setrlimit(RLIMIT_CPU, &cpuLimit) != 0)
            return false;
        return true;
    }

    int fail(const char *message)
    {
        std::fputs(message, stderr);
        std::fputc('\n', stderr);
        return 1;
    }
}

int main(int argc, char *argv[])
{
    if (!limitResources())
        return fail("Could not apply the compiled theme resource limits.");

    QCoreApplication application(argc, argv);

    if (argc != 2)
        return fail("Expected one .qbtheme file path.");

    const QString themePath = QString::fromLocal8Bit(argv[1]);
    const QFileInfo themeInfo {themePath};
    if (!themeInfo.isFile() || themeInfo.size() > MAX_THEME_RESOURCE_SIZE)
        return fail("The .qbtheme file is missing or larger than 64 MB.");

    if (!QResource::registerResource(themeInfo.absoluteFilePath(), QStringLiteral("/uitheme")))
        return fail("Qt could not open this compiled theme resource.");

    const QResource configResource {QStringLiteral(":/uitheme/config.json")};
    if (!configResource.isValid())
        return fail("The .qbtheme resource does not contain config.json.");
    if (configResource.uncompressedSize() < 0 || configResource.uncompressedSize() > MAX_CONFIG_SIZE)
        return fail("The theme config.json is larger than 1 MB.");

    QFile configFile {QStringLiteral(":/uitheme/config.json")};
    if (!configFile.open(QIODevice::ReadOnly))
        return fail("Qt could not read config.json from this theme.");

    const QByteArray configData = configFile.read(MAX_CONFIG_SIZE + 1);
    if (configData.size() > MAX_CONFIG_SIZE || configFile.error() != QFileDevice::NoError)
        return fail("The theme config.json could not be read within the 1 MB limit.");

    const size_t written = std::fwrite(configData.constData(), 1, static_cast<size_t>(configData.size()), stdout);
    if (written != static_cast<size_t>(configData.size()))
        return fail("Could not return the theme config.json to qBitX.");

    return 0;
}
