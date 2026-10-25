using PigPendant.Core;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var settings = new PendantSettings();
Check(settings.Mode == DisplayMode.Rope && settings.BalloonCount == 2, "defaults");
Check(settings.Get(Parameter.Sway) == 100, "rope nudge default");
settings.Set(Parameter.Sway, 500);
Check(settings.Get(Parameter.Sway) == 200, "rope nudge bound");
settings.Set(Parameter.Length, 5000);
Check(settings.Get(Parameter.Length) == 1200, "length bound");
settings.Mode = DisplayMode.Balloon;
Check(settings.Get(Parameter.Length) == 140, "mode isolation");
settings.BalloonCount = 8;
var simulation = new PendantSimulation(settings);
simulation.Reset(new Vec(-500, 400));
Check(simulation.ActiveRopes.Count() == 8, "balloon count");
for (var i = 0; i < 480; i++) simulation.Advance(new Vec(-500 + i * .2, 400), 1.0 / 120);
foreach (var rope in simulation.ActiveRopes)
{
    Check(rope.Nodes.All(n => double.IsFinite(n.X) && double.IsFinite(n.Y)), "finite rope");
    Check(rope.EndPoint.Y > rope.Nodes[0].Y, "upward balloon");
    for (var i = 0; i < RopePhysics.Segments; i++)
        Check((rope.Nodes[i + 1] - rope.Nodes[i]).Length <= rope.CurrentLength * 1.121 / RopePhysics.Segments, "stretch limit");
}
settings.Mode = DisplayMode.Rope;
simulation.Apply(settings);
simulation.Reset(new Vec(0, 0));
for (var i = 0; i < 240; i++) simulation.Advance(new Vec(i * .3, 0), 1.0 / 60);
Check(simulation.Rope.EndPoint.Y < 0, "downward rope");
settings.Mode = DisplayMode.Ghost;
simulation.Apply(settings);
simulation.Reset(new Vec(10, -10));
Check(simulation.GhostPosition == new Vec(54, 22), "ghost offset");
simulation.Advance(new Vec(100, 100), 1);
Check(simulation.GhostPosition.X > 54 && simulation.GhostPosition.X < 144, "ghost smoothing");
var ropeAnimation = new RopeCharacterAnimation(Enumerable.Repeat(.04, 75).ToArray(), 42);
Check(ropeAnimation.Sample == FrameSample.Rest, "character rest");
var animated = false;
for (var i = 0; i < 600; i++) animated |= ropeAnimation.Advance(1.0 / 60, default, default);
Check(animated, "idle character actions");
var blink = new GhostBlinkAnimation(42);
var sawBlink = false;
for (var i = 0; i < 600; i++) { blink.Advance(1.0 / 60); sawBlink |= blink.IsAnimating; }
Check(sawBlink, "ghost blink");
var body = new GhostBodyAnimation();
body.Advance(1.0 / 60, true, 0);
for (var i = 0; i < 60; i++) body.Advance(1.0 / 60, false, 0);
Check(body.Pose.HemStep > 0 && body.Pose.Step > 0, "ghost gestures and flowing hem");
var halo = new HaloAnimation(42);
for (var i = 0; i < 30; i++) halo.Advance(1.0 / 60, new Vec(300, 0), false);
Check(halo.Pose.Angle < 0 && halo.Pose.Offset.X < 0, "halo motion response");
var detector = new DrumBeatDetector(48000);
Check(detector.Process(new float[4096]) == 0, "silence must not trigger beat");
var pulse = new float[4800];
for (var i = 0; i < pulse.Length; i++) pulse[i] = (float)(.85 * Math.Sin(2 * Math.PI * 75 * i / 48000));
Check(detector.Process(pulse) > .08, "bass onset must trigger beat");
var resting = new PendantSimulation(new PendantSettings());
resting.Reset(new Vec(0, 0));
var nudged = false;
for (var i = 0; i < 7200 && !nudged; i++)
{
    resting.Advance(new Vec(0, 0), 1.0 / 60);
    nudged = Math.Abs(resting.Rope.EndPoint.X) > .1;
}
Check(nudged, "settled character stretch must nudge rope");
var noSwaySettings = new PendantSettings();
noSwaySettings.Set(Parameter.Sway, 0);
var noSway = new PendantSimulation(noSwaySettings);
noSway.Reset(new Vec(0, 0));
for (var i = 0; i < 7200; i++) noSway.Advance(new Vec(0, 0), 1.0 / 60);
Check(Math.Abs(noSway.Rope.EndPoint.X) < .001, "zero sway must not nudge rope");
Console.WriteLine("Core checks passed");
