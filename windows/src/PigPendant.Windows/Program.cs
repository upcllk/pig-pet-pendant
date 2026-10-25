using System.Diagnostics;
using System.IO.Pipes;
using System.Security.Principal;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Microsoft.Win32;
using PigPendant.Core;
using Forms = System.Windows.Forms;
using Application = System.Windows.Application;
using ComboBox = System.Windows.Controls.ComboBox;
using CheckBox = System.Windows.Controls.CheckBox;
using Button = System.Windows.Controls.Button;
using Orientation = System.Windows.Controls.Orientation;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace PigPendant.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        #if TESTING
        if (args.Contains("--self-check"))
        {
            try
            {
                var artwork = new Artwork();
                if (artwork.RopeFrameCount != 75 || artwork.GhostFrameCount != 8)
                    throw new InvalidDataException("Character frame count");
                foreach (var mode in Enum.GetValues<DisplayMode>())
                    if (artwork.Get(mode, 0).PixelWidth <= 0) throw new InvalidDataException($"Artwork {mode}");
                using (var notice = typeof(Program).Assembly.GetManifestResourceStream("PigPendant.Licenses.NAudio.txt"))
                    if (notice is null || notice.Length < 500) throw new InvalidDataException("NAudio license notice");
                var opaqueRed = Artwork.Bitmap([0, 0, 255, 255], 1, 1);
                var opaqueBlue = Artwork.Bitmap([255, 0, 0, 255], 1, 1);
                var blender = new FrameBlender();
                var halfway = blender.Compose(opaqueRed, opaqueBlue, .5);
                var mixed = Artwork.Pixels(halfway).Pixels;
                if (mixed[3] != 255 || mixed[0] is < 127 or > 128 || mixed[2] is < 127 or > 128 ||
                    !ReferenceEquals(halfway, blender.Compose(opaqueRed, opaqueBlue, .5)))
                    throw new InvalidDataException("Opaque crossfade changed alpha or missed cache");
                var transparent = Artwork.Bitmap([0, 0, 0, 0], 1, 1);
                var edge = Artwork.Pixels(blender.Compose(transparent, opaqueBlue, .5)).Pixels;
                if (edge[3] is < 127 or > 128 || edge[0] is < 127 or > 128)
                    throw new InvalidDataException("Premultiplied edge blend changed alpha");
                var previousConfig = Environment.GetEnvironmentVariable("PIGPENDANT_CONFIG_DIR");
                var checkDirectory = Path.Combine(Path.GetTempPath(), "PigPendant-settings-check-" + Guid.NewGuid().ToString("N"));
                try
                {
                    Environment.SetEnvironmentVariable("PIGPENDANT_CONFIG_DIR", checkDirectory);
                    var settingsStore = new SettingsStore();
                    var defaults = settingsStore.Defaults();
                    if (defaults.Get(Parameter.Sway) != 100) throw new InvalidDataException("Bundled default sway");
                    defaults.Set(Parameter.Sway, 75);
                    settingsStore.Save(defaults);
                    var configurationPath = Path.Combine(checkDirectory, "default-settings.json");
                    var edited = File.ReadAllText(configurationPath).Replace("\"sway\": 100", "\"sway\": 120");
                    File.WriteAllText(configurationPath, edited);
                    if (settingsStore.Load().Get(Parameter.Sway) != 75 || settingsStore.Defaults().Get(Parameter.Sway) != 120)
                        throw new InvalidDataException("User settings precedence or edited defaults");
                }
                finally
                {
                    Environment.SetEnvironmentVariable("PIGPENDANT_CONFIG_DIR", previousConfig);
                    var resolved = Path.GetFullPath(checkDirectory);
                    if (resolved.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase) && Directory.Exists(resolved))
                        Directory.Delete(resolved, true);
                }
                return 0;
            }
            catch (Exception e) { File.WriteAllText(Path.Combine(Path.GetTempPath(), "PigPendant-self-check-error.txt"), e.ToString()); return 1; }
        }
        #endif
        var identity = WindowsIdentity.GetCurrent().User?.Value?.Replace('-', '_') ?? Environment.UserName;
        var name = "PigPendant_" + identity + "_" + Process.GetCurrentProcess().SessionId;
        using var mutex = new Mutex(true, name, out var first);
        if (!first)
        {
            try
            {
                using var client = new NamedPipeClientStream(".", name, PipeDirection.Out);
                client.Connect(500);
                client.WriteByte(1);
            }
            catch { }
            return 0;
        }
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        try
        {
            var controller = new Controller(app, name);
            app.Exit += (_, _) => controller.Dispose();
            controller.Start();
            #if TESTING
            if (args.Contains("--smoke"))
            {
                if (!controller.OverlayStylesValid) throw new InvalidOperationException("Overlay styles missing");
                var smokeTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                smokeTimer.Tick += (_, _) => { smokeTimer.Stop(); app.Shutdown(); };
                smokeTimer.Start();
            }
            #endif
            app.Run();
            return 0;
        }
        catch (Exception e)
        {
            System.Windows.MessageBox.Show($"启动失败：{e.Message}", "猪猪挂件", MessageBoxButton.OK, MessageBoxImage.Error);
            return 1;
        }
    }
}

internal sealed class Controller : IDisposable
{
    private readonly Application app;
    private readonly string pipeName;
    private readonly SettingsStore store = new();
    private readonly Artwork artwork = new();
    private readonly DispatcherTimer timer = new();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private long previousTicks;
    private readonly CancellationTokenSource cancel = new();
    private readonly List<OverlayWindow> overlays = new();
    private readonly Forms.NotifyIcon tray = new();
    private System.Drawing.Icon? trayIcon;
    private readonly System.Drawing.Image trayAnimation;
    private readonly Stream trayAnimationStream;
    private readonly System.Drawing.Imaging.FrameDimension trayFrameDimension;
    private readonly DispatcherTimer trayTimer = new() { Interval = TimeSpan.FromSeconds(1.0 / 60) };
    private readonly Stopwatch trayClock = Stopwatch.StartNew();
    private double previousTrayTime;
    private double trayScale = 1;
    private readonly SystemAudioMonitor audio = new();
    private Window? settingsWindow;
    private bool suspended;
    private PendantSettings settings;
    private readonly PendantSimulation simulation;
    private readonly Forms.ContextMenuStrip menu = new();
    #if TESTING
    public bool OverlayStylesValid => overlays.Count == Forms.Screen.AllScreens.Length && overlays.All(Native.HasOverlayStyles);
    #endif
    private static readonly (DisplayMode mode, string title)[] modes =
    [
        (DisplayMode.Rope, "绳子挂件"), (DisplayMode.Ghost, "幽灵猪"),
        (DisplayMode.Balloon, "猪猪气球"), (DisplayMode.Net, "网兜小猪"),
        (DisplayMode.Bamboo, "竹子小猪"), (DisplayMode.Hanging, "猪上吊")
    ];
    public Controller(Application app, string pipeName)
    {
        this.app = app; this.pipeName = pipeName;
        settings = store.Load();
        simulation = new(settings, artwork.RopeDelays);
        trayAnimationStream = Artwork.Open("status-pig-spin.gif");
        trayAnimation = System.Drawing.Image.FromStream(trayAnimationStream);
        trayFrameDimension = new System.Drawing.Imaging.FrameDimension(trayAnimation.FrameDimensionsList[0]);
        trayTimer.Tick += (_, _) => AdvanceTrayIcon();
        AdvanceTrayIcon();
        timer.Interval = TimeSpan.FromSeconds(1.0 / 60);
        timer.Tick += (_, _) => Tick();
        tray.Icon = trayIcon;
        tray.Text = "猪猪挂件";
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => ShowSettings();
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool DestroyIcon(nint icon);
    private void AdvanceTrayIcon()
    {
        var count = trayAnimation.GetFrameCount(trayFrameDimension);
        var now = trayClock.Elapsed.TotalSeconds;
        var phase = now % 2.4 / 2.4;
        trayAnimation.SelectActiveFrame(trayFrameDimension, Math.Min(count - 1, (int)(phase * count)));
        trayScale = AudioReactiveScale.Smoothed(trayScale, audio.TargetScale(), now - previousTrayTime);
        previousTrayTime = now;
        using var bitmap = new System.Drawing.Bitmap(32, 32);
        using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
        {
            graphics.Clear(System.Drawing.Color.Transparent);
            graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            var side = 23 * trayScale;
            graphics.DrawImage(trayAnimation, new System.Drawing.RectangleF((float)((32 - side) / 2 + 1), (float)((32 - side) / 2), (float)side, (float)side));
        }
        var handle = bitmap.GetHicon();
        var replacement = (System.Drawing.Icon)System.Drawing.Icon.FromHandle(handle).Clone();
        DestroyIcon(handle);
        if (tray.Visible) tray.Icon = replacement;
        var old = trayIcon;
        trayIcon = replacement;
        old?.Dispose();
    }
    public void Start()
    {
        tray.Visible = true;
        try { audio.Start(); } catch (Exception error) { Trace.WriteLine($"System audio capture unavailable: {error}"); }
        trayTimer.Start();
        RebuildMenu();
        RebuildOverlays();
        SystemEvents.DisplaySettingsChanged += DisplayChanged;
        SystemEvents.PowerModeChanged += PowerChanged;
        _ = ListenForSecondInstance(cancel.Token);
        previousTicks = clock.ElapsedTicks;
        if (settings.Visible) timer.Start();
    }
    private async Task ListenForSecondInstance(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            using var server = new NamedPipeServerStream(pipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            try
            {
                await server.WaitForConnectionAsync(token);
                if (server.ReadByte() == 1) _ = app.Dispatcher.BeginInvoke(ShowSettings);
            }
            catch (OperationCanceledException) { return; }
            catch (Exception e) { Trace.WriteLine(e); }
        }
    }
    private Vec Anchor()
    {
        var point = Native.Cursor();
        return settings.Mode == DisplayMode.Ghost ? point : point + new Vec(4, settings.Mode == DisplayMode.Balloon ? -6 : 6);
    }
    private void Tick()
    {
        var now = clock.ElapsedTicks;
        var elapsed = (double)(now - previousTicks) / Stopwatch.Frequency;
        previousTicks = now;
        if (suspended || !settings.Visible) return;
        simulation.Advance(Anchor(), elapsed);
        Refresh();
    }
    private void Refresh() { foreach (var overlay in overlays) overlay.Refresh(simulation); }
    private void RebuildOverlays()
    {
        foreach (var overlay in overlays) overlay.Close();
        overlays.Clear();
        foreach (var screen in Forms.Screen.AllScreens)
        {
            var overlay = new OverlayWindow(screen.Bounds, artwork, simulation);
            overlays.Add(overlay);
            if (settings.Visible && !suspended) overlay.Show();
        }
        simulation.Reset(Anchor());
        previousTicks = clock.ElapsedTicks;
        Refresh();
    }
    private void DisplayChanged(object? sender, EventArgs e) => app.Dispatcher.BeginInvoke(RebuildOverlays);
    private void PowerChanged(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend) { suspended = true; timer.Stop(); foreach (var overlay in overlays) overlay.Hide(); }
        else if (e.Mode == PowerModes.Resume)
        {
            suspended = false;
            RebuildOverlays();
            if (settings.Visible) timer.Start();
        }
    }
    private void Save()
    {
        try { store.Save(settings); }
        catch (Exception e) { System.Windows.MessageBox.Show($"设置保存失败：{e.Message}", "猪猪挂件", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private void Changed(bool reset = false)
    {
        settings.Normalize();
        simulation.Apply(settings);
        if (reset) simulation.Reset(Anchor());
        Save();
        Refresh();
        RebuildMenu();
    }
    private void SetVisible(bool visible)
    {
        settings.Visible = visible;
        if (visible && !suspended)
        {
            simulation.Reset(Anchor());
            foreach (var overlay in overlays) overlay.Show();
            previousTicks = clock.ElapsedTicks;
            timer.Start();
        }
        else { timer.Stop(); foreach (var overlay in overlays) overlay.Hide(); }
        Changed();
    }
    private void RebuildMenu()
    {
        menu.Items.Clear();
        menu.Items.Add("设置…", null, (_, _) => ShowSettings());
        var modeMenu = new Forms.ToolStripMenuItem("模式");
        foreach (var (mode, title) in modes)
        {
            var item = new Forms.ToolStripMenuItem(title) { Checked = settings.Mode == mode };
            item.Click += (_, _) => { settings.Mode = mode; Changed(true); RebuildOverlays(); };
            modeMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(modeMenu);
        menu.Items.Add(new Forms.ToolStripSeparator());
        var visible = menu.Items.Add(settings.Mode switch
        {
            DisplayMode.Balloon => "显示 / 隐藏猪猪气球", DisplayMode.Net => "显示 / 隐藏网兜小猪",
            DisplayMode.Bamboo => "显示 / 隐藏竹子小猪", DisplayMode.Hanging => "显示 / 隐藏上吊猪",
            DisplayMode.Ghost => "显示 / 隐藏幽灵猪", _ => "显示 / 隐藏小猪"
        });
        if (visible is Forms.ToolStripMenuItem visibleItem) visibleItem.Checked = settings.Visible;
        visible.Click += (_, _) => SetVisible(!settings.Visible);
        if (settings.Mode == DisplayMode.Balloon)
        {
            var count = new Forms.ToolStripMenuItem("气球数量");
            for (var n = 1; n <= 8; n++)
            {
                var selected = n;
                var option = new Forms.ToolStripMenuItem($"{n} 只") { Checked = n == settings.BalloonCount };
                option.Click += (_, _) => { settings.BalloonCount = selected; Changed(true); };
                count.DropDownItems.Add(option);
            }
            menu.Items.Add(count);
        }
        var sizeMenu = new Forms.ToolStripMenuItem("小猪尺寸");
        foreach (var n in new[] { 16, 24, 36, 48, 64, 96, 128, 192, 256 })
        {
            var option = new Forms.ToolStripMenuItem($"{n} 点") { Checked = Math.Abs(settings.Get(Parameter.Size) - n) < .1 };
            option.Click += (_, _) => { settings.Set(Parameter.Size, n); Changed(); };
            sizeMenu.DropDownItems.Add(option);
        }
        menu.Items.Add(sizeMenu);
        if (settings.Mode != DisplayMode.Ghost)
        {
            var lengthMenu = new Forms.ToolStripMenuItem(settings.Mode == DisplayMode.Bamboo ? "竹子长度" : "绳子长度");
            foreach (var n in new[] { 20, 60, 100, 140, 220, 320, 440, 600, 900, 1200 })
            {
                var option = new Forms.ToolStripMenuItem($"{n} 点") { Checked = Math.Abs(settings.Get(Parameter.Length) - n) < .1 };
                option.Click += (_, _) => { settings.Set(Parameter.Length, n); Changed(); };
                lengthMenu.DropDownItems.Add(option);
            }
            menu.Items.Add(lengthMenu);
        }
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("重置位置", null, (_, _) => { simulation.Reset(Anchor()); Refresh(); });
        menu.Items.Add("退出猪猪挂件", null, (_, _) => app.Shutdown());
    }
    private void ShowSettings()
    {
        if (settingsWindow is { IsVisible: true }) { settingsWindow.Activate(); return; }
        var window = new Window
        {
            Title = "猪猪挂件 · 设置", Width = 490, Height = 610, MinWidth = 420, MinHeight = 460,
            WindowStartupLocation = WindowStartupLocation.CenterScreen
        };
        settingsWindow = window;
        var panel = new StackPanel { Margin = new Thickness(18) };
        var scroll = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        window.Content = scroll;
        var heading = new TextBlock { Text = "猪猪挂件", FontSize = 21, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 12) };
        panel.Children.Add(heading);
        var modeBox = new ComboBox { ItemsSource = modes.Select(x => x.title).ToArray(), SelectedIndex = Array.FindIndex(modes, x => x.mode == settings.Mode), Margin = new Thickness(0, 0, 0, 10) };
        panel.Children.Add(modeBox);
        var visible = new CheckBox { Content = settings.Mode == DisplayMode.Ghost ? "显示幽灵猪" : settings.Mode == DisplayMode.Hanging ? "显示上吊猪" : "显示小猪", IsChecked = settings.Visible, Margin = new Thickness(0, 0, 0, 10) };
        panel.Children.Add(visible);
        var dynamic = new StackPanel(); panel.Children.Add(dynamic);
        void AddSlider(string title, double min, double max, double value, Action<double> update, bool integer = false)
        {
            var label = new TextBlock { Text = title + $"：{value:0.##}", Margin = new Thickness(0, 8, 0, 0) };
            var slider = new Slider { Minimum = min, Maximum = max, Value = value, TickFrequency = integer ? 1 : .1, IsSnapToTickEnabled = integer };
            slider.ValueChanged += (_, _) => { if (!window.IsLoaded) return; label.Text = title + $"：{slider.Value:0.##}"; update(slider.Value); Changed(); };
            dynamic.Children.Add(label); dynamic.Children.Add(slider);
        }
        void BuildRows()
        {
            dynamic.Children.Clear();
            if (settings.Mode == DisplayMode.Balloon)
                AddSlider("气球数量", 1, 8, settings.BalloonCount, v => { settings.BalloonCount = (int)v; simulation.Apply(settings); simulation.Reset(Anchor()); }, true);
            if (settings.Mode == DisplayMode.Bamboo)
                AddSlider("小猪位置", 0, 100, settings.BambooPosition, v => settings.BambooPosition = v);
            if (settings.Mode == DisplayMode.Ghost)
            {
                AddSlider("水平偏移", -300, 300, settings.GhostOffsetX, v => settings.GhostOffsetX = v);
                AddSlider("垂直偏移", -300, 300, settings.GhostOffsetY, v => settings.GhostOffsetY = v);
            }
            else foreach (var parameter in PendantSettings.Parameters)
            {
                if (parameter == Parameter.Sway && settings.Mode != DisplayMode.Rope) continue;
                var (min, max, _) = PendantSettings.Spec(parameter);
                var label = parameter switch
                {
                    Parameter.Length => settings.Mode == DisplayMode.Bamboo ? "竹子长度" : "绳子长度",
                    Parameter.Size => "小猪尺寸", Parameter.Weight => "重量感", Parameter.Elasticity => settings.Mode == DisplayMode.Bamboo ? "竹子弹性" : "绳子弹性", Parameter.Sway => "拱身晃动 (%)",
                    Parameter.Damping => "摆动衰减", _ => settings.Mode == DisplayMode.Balloon ? "浮力" : "重力"
                };
                AddSlider(label, min, max, settings.Get(parameter), v => settings.Set(parameter, v));
            }
            if (settings.Mode == DisplayMode.Ghost)
            {
                var (min, max, _) = PendantSettings.Spec(Parameter.Size);
                AddSlider("小猪尺寸", min, max, settings.Get(Parameter.Size), v => settings.Set(Parameter.Size, v));
            }
        }
        modeBox.SelectionChanged += (_, _) =>
        {
            if (!window.IsLoaded) return;
            settings.Mode = modes[modeBox.SelectedIndex].mode;
            Changed(true); RebuildOverlays();
            visible.Content = settings.Mode == DisplayMode.Ghost ? "显示幽灵猪" : settings.Mode == DisplayMode.Hanging ? "显示上吊猪" : "显示小猪";
            BuildRows();
        };
        visible.Checked += (_, _) => { if (window.IsLoaded) SetVisible(true); };
        visible.Unchecked += (_, _) => { if (window.IsLoaded) SetVisible(false); };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        var licenses = new Button { Content = "第三方许可…", Margin = new Thickness(0, 0, 10, 0), Padding = new Thickness(10, 5, 10, 5) };
        licenses.Click += (_, _) =>
        {
            using var resource = typeof(Program).Assembly.GetManifestResourceStream("PigPendant.Licenses.NAudio.txt")
                ?? throw new InvalidDataException("Missing NAudio license notice");
            using var reader = new StreamReader(resource);
            var notice = new Window { Title = "第三方许可", Owner = window, Width = 650, Height = 450, WindowStartupLocation = WindowStartupLocation.CenterOwner };
            notice.Content = new ScrollViewer { Content = new TextBlock { Text = reader.ReadToEnd(), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(20) } };
            notice.ShowDialog();
        };
        var restore = new Button { Content = "恢复默认", Margin = new Thickness(0, 0, 10, 0), Padding = new Thickness(10, 5, 10, 5) };
        restore.Click += (_, _) =>
        {
            try
            {
                settings = store.Defaults(); Changed(true); RebuildOverlays();
                modeBox.SelectedIndex = 0; visible.IsChecked = true; BuildRows();
            }
            catch (Exception error)
            {
                System.Windows.MessageBox.Show($"默认参数配置无效：{error.Message}", "猪猪挂件", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        };
        var done = new Button { Content = "完成", Padding = new Thickness(12, 5, 12, 5) };
        done.Click += (_, _) => window.Close();
        buttons.Children.Add(licenses); buttons.Children.Add(restore); buttons.Children.Add(done); panel.Children.Add(buttons);
        BuildRows();
        window.Show(); window.Activate();
    }
    public void Dispose()
    {
        cancel.Cancel(); timer.Stop(); trayTimer.Stop();
        SystemEvents.DisplaySettingsChanged -= DisplayChanged;
        SystemEvents.PowerModeChanged -= PowerChanged;
        audio.Dispose(); tray.Visible = false; tray.Dispose(); trayIcon?.Dispose(); trayAnimation.Dispose(); trayAnimationStream.Dispose(); menu.Dispose();
        foreach (var overlay in overlays) overlay.Close();
        cancel.Dispose();
    }
}
