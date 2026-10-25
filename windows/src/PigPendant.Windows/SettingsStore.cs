using System.Text.Json;
using System.IO;
using PigPendant.Core;

namespace PigPendant.Windows;

internal sealed class SettingsStore
{
    private readonly string path;
    private readonly string defaultsPath;
    public SettingsStore()
    {
        var root = Environment.GetEnvironmentVariable("PIGPENDANT_CONFIG_DIR");
        if (string.IsNullOrWhiteSpace(root)) root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PigPendant");
        path = Path.Combine(root, "settings.json");
        defaultsPath = Path.Combine(root, "default-settings.json");
    }
    private sealed class Document
    {
        public int SchemaVersion { get; set; } = 1;
        public string Mode { get; set; } = "rope";
        public bool Visible { get; set; } = true;
        public int BalloonCount { get; set; } = 2;
        public double BambooPosition { get; set; } = 50;
        public double GhostOffsetX { get; set; } = 44;
        public double GhostOffsetY { get; set; } = 32;
        public Dictionary<string, double> Parameters { get; set; } = new();
    }
    private static readonly JsonSerializerOptions options = new() { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    private static string Key(Parameter parameter, DisplayMode mode)
    {
        var key = parameter switch
        {
            Parameter.Length => "RopeLength", Parameter.Size => "PigSize", Parameter.Weight => "Weight",
            Parameter.Elasticity => "Elasticity", Parameter.Sway => "NudgeSwingAmplitude", Parameter.Damping => "DampingRate", _ => "Gravity"
        };
        return key + "." + mode.ToString().ToLowerInvariant();
    }
    public PendantSettings Load()
    {
        var configured = Defaults();
        try
        {
            if (!File.Exists(path)) return configured;
            var document = JsonSerializer.Deserialize<Document>(File.ReadAllText(path), options);
            if (document?.SchemaVersion != 1) throw new InvalidDataException("Unsupported settings schema");
            var settings = configured;
            settings.Mode = Enum.TryParse<DisplayMode>(document.Mode, true, out var mode) ? mode : DisplayMode.Rope;
            settings.Visible = document.Visible; settings.BalloonCount = document.BalloonCount;
            settings.BambooPosition = document.BambooPosition;
            settings.GhostOffsetX = document.GhostOffsetX; settings.GhostOffsetY = document.GhostOffsetY;
            foreach (var entry in document.Parameters ?? new())
            foreach (var candidateMode in Enum.GetValues<DisplayMode>())
            foreach (var parameter in PendantSettings.Parameters)
                if (entry.Key == Key(parameter, candidateMode)) settings.Set(parameter, entry.Value, candidateMode);
            settings.Normalize();
            return settings;
        }
        catch (Exception e)
        {
            System.Diagnostics.Trace.WriteLine($"Invalid settings: {e}");
            return configured;
        }
    }
    public PendantSettings Defaults()
    {
        if (!File.Exists(defaultsPath))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(defaultsPath)!);
            using var embedded = Artwork.Open("default-settings.json");
            using var destination = File.Create(defaultsPath);
            embedded.CopyTo(destination);
        }
        using var document = JsonDocument.Parse(File.ReadAllText(defaultsPath));
        var root = document.RootElement;
        var configured = new PendantSettings();
        var modes = root.GetProperty("parameters");
        if (modes.EnumerateObject().Count() != Enum.GetValues<DisplayMode>().Length) throw new InvalidDataException("默认配置必须包含全部六种模式");
        foreach (var mode in Enum.GetValues<DisplayMode>())
        {
            var values = modes.GetProperty(mode.ToString().ToLowerInvariant());
            if (values.EnumerateObject().Count() != PendantSettings.Parameters.Length) throw new InvalidDataException($"{mode} 必须包含全部七项参数");
            foreach (var parameter in PendantSettings.Parameters)
            {
                var key = parameter switch
                {
                    Parameter.Length => "length", Parameter.Size => "size", Parameter.Weight => "weight",
                    Parameter.Elasticity => "elasticity", Parameter.Sway => "sway", Parameter.Damping => "damping", _ => "gravity"
                };
                var value = values.GetProperty(key).GetDouble();
                var (min, max, _) = PendantSettings.Spec(parameter);
                if (!double.IsFinite(value) || value < min || value > max) throw new InvalidDataException($"{mode}.{key} 超出范围 {min}–{max}");
                configured.Set(parameter, value, mode);
            }
        }
        configured.BalloonCount = root.GetProperty("balloonCount").GetInt32();
        configured.BambooPosition = root.GetProperty("bambooPosition").GetDouble();
        var offsets = root.GetProperty("ghostOffsets");
        configured.GhostOffsetX = offsets.GetProperty("horizontal").GetDouble();
        configured.GhostOffsetY = offsets.GetProperty("vertical").GetDouble();
        if (configured.BalloonCount is < 1 or > 8 || !double.IsFinite(configured.BambooPosition) || configured.BambooPosition is < 0 or > 100 ||
            !double.IsFinite(configured.GhostOffsetX) || configured.GhostOffsetX is < -300 or > 300 ||
            !double.IsFinite(configured.GhostOffsetY) || configured.GhostOffsetY is < -300 or > 300)
            throw new InvalidDataException("默认配置中的数量、位置或幽灵偏移超出范围");
        return configured;
    }
    public void Save(PendantSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        try
        {
            var document = new Document
            {
                Mode = settings.Mode.ToString().ToLowerInvariant(), Visible = settings.Visible,
                BalloonCount = settings.BalloonCount, BambooPosition = settings.BambooPosition,
                GhostOffsetX = settings.GhostOffsetX, GhostOffsetY = settings.GhostOffsetY
            };
            foreach (var mode in Enum.GetValues<DisplayMode>())
            foreach (var parameter in PendantSettings.Parameters)
                if (settings.Values.TryGetValue(mode, out var values) && values.TryGetValue(parameter, out var value))
                    document.Parameters[Key(parameter, mode)] = value;
            File.WriteAllText(temporary, JsonSerializer.Serialize(document, options));
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
