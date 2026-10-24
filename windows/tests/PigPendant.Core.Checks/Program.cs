using PigPendant.Core;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var settings = new PendantSettings();
Check(settings.Mode == DisplayMode.Rope && settings.BalloonCount == 2, "defaults");
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
Console.WriteLine("Core checks passed");
