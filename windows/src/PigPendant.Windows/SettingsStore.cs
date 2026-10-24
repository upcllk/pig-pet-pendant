using System.Text.Json;
using System.IO;
using PigPendant.Core;

namespace PigPendant.Windows;

internal sealed class SettingsStore
{
    private readonly string path;
    public SettingsStore()
    {
        var root = Environment.GetEnvironmentVariable("PIGPENDANT_CONFIG_DIR");
        if (string.IsNullOrWhiteSpace(root)) root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PigPendant");
        path = Path.Combine(root, "settings.json");
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
            Parameter.Elasticity => "Elasticity", Parameter.Damping => "DampingRate", _ => "Gravity"
        };
        return key + "." + mode.ToString().ToLowerInvariant();
    }
    public PendantSettings Load()
    {
        try
        {
            if (!File.Exists(path)) return new();
            var document = JsonSerializer.Deserialize<Document>(File.ReadAllText(path), options);
            if (document?.SchemaVersion != 1) throw new InvalidDataException("Unsupported settings schema");
            var settings = new PendantSettings
            {
                Mode = Enum.TryParse<DisplayMode>(document.Mode, true, out var mode) ? mode : DisplayMode.Rope,
                Visible = document.Visible, BalloonCount = document.BalloonCount,
                BambooPosition = document.BambooPosition,
                GhostOffsetX = document.GhostOffsetX, GhostOffsetY = document.GhostOffsetY
            };
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
            return new();
        }
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
