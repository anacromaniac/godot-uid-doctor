namespace UidDoctor.Tests;

using Chickensoft.GoDotTest;
using Godot;
using Shouldly;

public class SceneUidsTest : TestClass
{
  private const string FIXTURE_DIR = "user://scene_uids_test";
  private const string SCENE_UID = "uid://debhv7jdsjou3";
  private const string OTHER_SCENE_UID = "uid://bn46p12yipiix";
  private const string SCRIPT_UID = "uid://r2t1wovol5si";
  private const string TEXTURE_UID = "uid://nr2okyjjjb2d";
  // Invented by hand: it overflows 63 bits, so the editor rewrites it on save.
  private const string NON_CANONICAL_UID = "uid://2xekg173r5uhh";
  private const string SCENE_FILE = "scene.tscn";
  private const string CHILD_SCENE_FILE = "child.tscn";
  private const string SCRIPT_FILE = "helper.gd";
  private const string TEXTURE_FILE = "texture.png";
  private const string NODE_WITH_UNIQUE_ID = "[node name=\"Root\" type=\"Node\" unique_id=426156238]\n";
  private const string NODE_WITHOUT_UNIQUE_ID = "[node name=\"Root\" type=\"Node\"]\n";

  private static readonly GDScript _sceneUids = GD.Load<GDScript>("res://addons/uid_doctor/scene_uids.gd");

  public SceneUidsTest(Node testScene) : base(testScene) { }

  [Setup]
  public void Setup() => SceneToolFixtures.Recreate(FIXTURE_DIR);

  [Cleanup]
  public void Cleanup() => SceneToolFixtures.Delete(FIXTURE_DIR);

  [Test]
  public void AcceptsAnEditorSavedSceneWhoseExtResourcesMatchTheirTargets()
  {
    var scriptPath = WriteFixture(SCRIPT_FILE, "extends Node\n");
    WriteFixture(SCRIPT_FILE + ".uid", SCRIPT_UID + "\n");
    var childPath = WriteFixture(CHILD_SCENE_FILE, SceneText(OTHER_SCENE_UID, "", NODE_WITH_UNIQUE_ID));
    var texturePath = WriteFixture(TEXTURE_FILE, "");
    WriteFixture(TEXTURE_FILE + ".import", $"[remap]\n\nimporter=\"texture\"\nuid=\"{TEXTURE_UID}\"\n");
    var extResources =
      ExtResource("Script", SCRIPT_UID, scriptPath, "1") +
      ExtResource("PackedScene", OTHER_SCENE_UID, childPath, "2") +
      ExtResource("Texture2D", TEXTURE_UID, texturePath, "3");
    var scenePath = WriteFixture(SCENE_FILE, SceneText(SCENE_UID, extResources, NODE_WITH_UNIQUE_ID));

    FindProblems(scenePath).ShouldBeEmpty();
  }

  [Test]
  public void ReportsASceneWithoutHeaderUid()
  {
    var scenePath = WriteFixture(SCENE_FILE, $"[gd_scene format=3]\n\n{NODE_WITH_UNIQUE_ID}");

    FindProblems(scenePath).ShouldBe([$"{scenePath}:1: no header UID"]);
  }

  [Test]
  public void ReportsANonCanonicalHeaderUid()
  {
    var scenePath = WriteFixture(SCENE_FILE, SceneText(NON_CANONICAL_UID, "", NODE_WITH_UNIQUE_ID));

    FindProblems(scenePath).ShouldBe([$"{scenePath}:1: UID {NON_CANONICAL_UID} is not in canonical form"]);
  }

  [Test]
  public void ReportsAnExtResourceWithoutUid()
  {
    var childPath = WriteFixture(CHILD_SCENE_FILE, SceneText(OTHER_SCENE_UID, "", NODE_WITH_UNIQUE_ID));
    var extResource = $"[ext_resource type=\"PackedScene\" path=\"{childPath}\" id=\"1\"]\n";
    var scenePath = WriteFixture(SCENE_FILE, SceneText(SCENE_UID, extResource, NODE_WITH_UNIQUE_ID));

    FindProblems(scenePath).ShouldBe([$"{scenePath}:3: ext_resource has no UID"]);
  }

  [Test]
  public void ReportsAnExtResourceWhoseTargetHasNoUidEither()
  {
    var childPath = WriteFixture(CHILD_SCENE_FILE, $"[gd_scene format=3]\n\n{NODE_WITH_UNIQUE_ID}");
    var extResource = $"[ext_resource type=\"PackedScene\" path=\"{childPath}\" id=\"1\"]\n";
    var scenePath = WriteFixture(SCENE_FILE, SceneText(SCENE_UID, extResource, NODE_WITH_UNIQUE_ID));

    FindProblems(scenePath).ShouldBe([$"{scenePath}:3: ext_resource has no UID, and its target {childPath} has none either"]);
  }

  [Test]
  public void ReportsAnExtResourceUidThatDiffersFromItsTarget()
  {
    var childPath = WriteFixture(CHILD_SCENE_FILE, SceneText(OTHER_SCENE_UID, "", NODE_WITH_UNIQUE_ID));
    var extResource = ExtResource("PackedScene", SCRIPT_UID, childPath, "1");
    var scenePath = WriteFixture(SCENE_FILE, SceneText(SCENE_UID, extResource, NODE_WITH_UNIQUE_ID));

    FindProblems(scenePath).ShouldBe(
      [$"{scenePath}:3: ext_resource UID {SCRIPT_UID} differs from {OTHER_SCENE_UID}, the UID of {childPath}"]
    );
  }

  [Test]
  public void ReportsANodeWithoutUniqueId()
  {
    var scenePath = WriteFixture(SCENE_FILE, SceneText(SCENE_UID, "", NODE_WITHOUT_UNIQUE_ID));

    FindProblems(scenePath).ShouldBe([$"{scenePath}:3: node has no unique_id"]);
  }

  [Test]
  public void ReportsEveryFileThatSharesAHeaderUid()
  {
    var scenePath = WriteFixture(SCENE_FILE, SceneText(SCENE_UID, "", NODE_WITH_UNIQUE_ID));
    var copyPath = WriteFixture(CHILD_SCENE_FILE, SceneText(SCENE_UID, "", NODE_WITH_UNIQUE_ID));

    FindProblemsUnder(FIXTURE_DIR).ShouldBe(
      [
        $"{copyPath}:1: header UID {SCENE_UID} is also the UID of {scenePath}",
        $"{scenePath}:1: header UID {SCENE_UID} is also the UID of {copyPath}",
      ],
      ignoreOrder: true
    );
  }

  [Test]
  public void SkipsAddonsHiddenFoldersAndFoldersGodotIgnores()
  {
    var withoutUid = $"[gd_scene format=3]\n\n{NODE_WITH_UNIQUE_ID}";
    WriteFixture("addons/plugin/" + SCENE_FILE, withoutUid);
    WriteFixture(".hidden/" + SCENE_FILE, withoutUid);
    WriteFixture("ignored/.gdignore", "");
    WriteFixture("ignored/" + SCENE_FILE, withoutUid);
    var checkedPath = WriteFixture("checked/" + SCENE_FILE, withoutUid);

    FindProblemsUnder(FIXTURE_DIR).ShouldBe([$"{checkedPath}:1: no header UID"]);
  }

  private static string[] FindProblems(string path) =>
    _sceneUids.Call("find_problems", path).AsStringArray();

  private static string[] FindProblemsUnder(string rootDir) =>
    _sceneUids.Call("find_problems_under", rootDir).AsStringArray();

  private static string WriteFixture(string relativePath, string content) =>
    SceneToolFixtures.Write(FIXTURE_DIR.PathJoin(relativePath), content);

  private static string SceneText(string uid, string extResources, string nodes) =>
    $"[gd_scene format=3 uid=\"{uid}\"]\n\n{extResources}{(extResources.Length > 0 ? "\n" : "")}{nodes}";

  private static string ExtResource(string type, string uid, string path, string id) =>
    $"[ext_resource type=\"{type}\" uid=\"{uid}\" path=\"{path}\" id=\"{id}\"]\n";
}
