namespace UidDoctor.Tests;

using System.Reflection;
using Chickensoft.GoDotTest;
using Godot;

public partial class Tests : Node
{
  public override void _Ready() =>
    _ = GoTest.RunTests(Assembly.GetExecutingAssembly(), this, TestEnvironment.From(OS.GetCmdlineArgs()));
}
