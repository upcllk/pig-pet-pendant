using System.Text.Json;
using System.Text.Json.Nodes;
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
        public Dictionary<string, double> HaloSpacing { get; set; } = new();
        public Dictionary<string, double> HaloSize { get; set; } = new();
    }
    private static readonly JsonSerializerOptions options = new() { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    private static string ModeKey(DisplayMode mode) => mode == DisplayMode.GhostWave ? "ghostWave" : mode.ToString().ToLowerInvariant();
    private static string Key(Parameter parameter, DisplayMode mode)
    {
        var key = parameter switch
        {
            Parameter.Length => "RopeLength", Parameter.Size => "PigSize", Parameter.Weight => "Weight",
            Parameter.Elasticity => "Elasticity", Parameter.Sway => "NudgeSwingAmplitude", Parameter.Damping => "DampingRate", _ => "Gravity"
        };
        return key + "." + ModeKey(mode);
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
            foreach (var modeWithHalo in Enum.GetValues<DisplayMode>().Where(PendantSettings.HasHalo))
            {
                var key = ModeKey(modeWithHalo);
                if (document.HaloSpacing?.TryGetValue(key, out var spacing) == true) settings.SetHaloSpacing(modeWithHalo, spacing);
                if (document.HaloSize?.TryGetValue(key, out var size) == true) settings.SetHaloSize(modeWithHalo, size);
            }
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
        MigrateLegacyDefaults();
        using var document = JsonDocument.Parse(File.ReadAllText(defaultsPath));
        var root = document.RootElement;
        var configured = new PendantSettings();
        var modes = root.GetProperty("parameters");
        if (modes.EnumerateObject().Count() != Enum.GetValues<DisplayMode>().Length) throw new InvalidDataException("默认配置必须包含全部七种模式");
        foreach (var mode in Enum.GetValues<DisplayMode>())
        {
            var values = modes.GetProperty(ModeKey(mode));
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
        foreach (var (name, set, min, max) in new (string, Action<DisplayMode, double>, double, double)[]
        {
            ("haloSpacing", configured.SetHaloSpacing, -120, 120),
            ("haloSize", configured.SetHaloSize, 25, 300)
        })
        {
            if (!root.TryGetProperty(name, out var section)) continue;
            if (section.EnumerateObject().Count() != 3) throw new InvalidDataException($"{name} 必须包含三种光环模式");
            foreach (var mode in Enum.GetValues<DisplayMode>().Where(PendantSettings.HasHalo))
            {
                var value = section.GetProperty(ModeKey(mode)).GetDouble();
                if (!double.IsFinite(value) || value < min || value > max) throw new InvalidDataException($"{name}.{ModeKey(mode)} 超出范围");
                set(mode, value);
            }
        }
        return configured;
    }
    private void MigrateLegacyDefaults()
    {
        var root = JsonNode.Parse(File.ReadAllText(defaultsPath)) as JsonObject;
        if (root?["parameters"] is not JsonObject parameters) return;
        var legacy = Enum.GetValues<DisplayMode>().Where(mode => mode != DisplayMode.GhostWave).Select(ModeKey).ToHashSet();
        if (!parameters.Select(item => item.Key).ToHashSet().SetEquals(legacy)) return;
        using var embedded = Artwork.Open("default-settings.json");
        var bundled = JsonNode.Parse(embedded) as JsonObject;
        parameters["ghostWave"] = bundled?["parameters"]?["ghostWave"]?.DeepClone()
            ?? throw new InvalidDataException("Bundled wave ghost defaults missing");
        var temporary = defaultsPath + ".tmp";
        try { File.WriteAllText(temporary, root.ToJsonString(options)); File.Move(temporary, defaultsPath, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public void Save(PendantSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        try
        {
            var document = new Document
            {
                Mode = ModeKey(settings.Mode), Visible = settings.Visible,
                BalloonCount = settings.BalloonCount, BambooPosition = settings.BambooPosition,
                GhostOffsetX = settings.GhostOffsetX, GhostOffsetY = settings.GhostOffsetY
            };
            foreach (var mode in Enum.GetValues<DisplayMode>())
            foreach (var parameter in PendantSettings.Parameters)
                if (settings.Values.TryGetValue(mode, out var values) && values.TryGetValue(parameter, out var value))
                    document.Parameters[Key(parameter, mode)] = value;
            foreach (var mode in Enum.GetValues<DisplayMode>().Where(PendantSettings.HasHalo))
            {
                document.HaloSpacing[ModeKey(mode)] = settings.HaloSpacing(mode);
                document.HaloSize[ModeKey(mode)] = settings.HaloSize(mode);
            }
            File.WriteAllText(temporary, JsonSerializer.Serialize(document, options));
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
