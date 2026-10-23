namespace UidDoctor.Tests;

using Chickensoft.GoDotTest;
using Godot;
using Shouldly;

public class SceneContentTest : TestClass
{
  private const string FIXTURE_DIR = "user://scene_content_test";
  private const string HAND_WRITTEN_SCENE = """
    [gd_scene load_steps=2 format=3]

    [sub_resource type="BoxMesh" id="BoxMesh_box"]
    size = Vector3(2, 1, 1)

    [node name="Root" type="Node3D"]
    visible = true

    [node name="Mesh" type="MeshInstance3D" parent="." groups=["solid", "a_group"]]
    mesh = SubResource("BoxMesh_box")

    [node name="Timer" type="Timer" parent="."]
    wait_time = 1.0

    [connection signal="timeout" from="Timer" to="." method="queue_free"]

    """;
  private const string EDITOR_SAVED_SCENE = """
    [gd_scene format=3 uid="uid://debhv7jdsjou3"]

    [sub_resource type="BoxMesh" id="BoxMesh_x1y2z"]
    size = Vector3(2, 1, 1)

    [node name="Root" type="Node3D" unique_id=426156238]

    [node name="Mesh" type="MeshInstance3D" parent="." unique_id=1009011494 groups=["a_group", "solid"]]
    mesh = SubResource("BoxMesh_x1y2z")

    [node name="Timer" type="Timer" parent="." unique_id=118225747]

    [connection signal="timeout" from="Timer" to="." method="queue_free"]

    """;
  private const string RESIZED_SCENE = """
    [gd_scene format=3]

    [sub_resource type="BoxMesh" id="BoxMesh_box"]
    size = Vector3(3, 1, 1)

    [node name="Root" type="Node3D"]

    [node name="Mesh" type="MeshInstance3D" parent="." groups=["solid", "a_group"]]
    mesh = SubResource("BoxMesh_box")

    [node name="Timer" type="Timer" parent="."]

    [connection signal="timeout" from="Timer" to="." method="queue_free"]

    """;
  private const string INSTANCING_SCENE = """
    [gd_scene format=3]

    [ext_resource type="PackedScene" path="user://scene_content_test/instanced.tscn" id="1_instanced"]

    [node name="Root" type="Node3D"]

    [node name="Instanced" parent="." instance=ExtResource("1_instanced")]

    [node name="Mesh" parent="Instanced" index="0"]
    visible = false

    [connection signal="timeout" from="Instanced/Timer" to="." method="hide"]

    """;
  private const string EDITABLE_INSTANCE = "[editable path=\"Instanced\"]\n";

  private static readonly GDScript _sceneContent = GD.Load<GDScript>("res://addons/uid_doctor/scene_content.gd");

  public SceneContentTest(Node testScene) : base(testScene) { }

  [Setup]
  public void Setup() => SceneToolFixtures.Recreate(FIXTURE_DIR);

  [Cleanup]
  public void Cleanup() => SceneToolFixtures.Delete(FIXTURE_DIR);

  [Test]
  public void SpellingThatAnEditorSaveChangesLeavesTheContentEqual()
  {
    var handWritten = OfFile(WriteFixture("hand_written.tscn", HAND_WRITTEN_SCENE));
    var editorSaved = OfFile(WriteFixture("editor_saved.tscn", EDITOR_SAVED_SCENE));

    Differences(handWritten, editorSaved).ShouldBeEmpty();
  }

  [Test]
  public void ReportsAChangedEmbeddedResource()
  {
    var handWritten = OfFile(WriteFixture("hand_written.tscn", HAND_WRITTEN_SCENE));
    var resized = OfFile(WriteFixture("resized.tscn", RESIZED_SCENE));

    var differences = Differences(handWritten, resized);

    differences.Length.ShouldBe(1);
    differences[0].ShouldStartWith("node Mesh, mesh:");
  }

  [Test]
  public void RepackingDropsOverridesAndConnectionsInsideANonEditableInstance()
  {
    WriteFixture("instanced.tscn", HAND_WRITTEN_SCENE);
    var path = WriteFixture("instancing.tscn", INSTANCING_SCENE);

    Differences(OfFile(path), OfSceneRepacked(path)).ShouldBe(
      [
        "node Instanced/Mesh, visible: false -> true",
        "node Instanced/Timer, (connections): [\"timeout -> .:hide\", \"timeout -> Instanced:queue_free\"]" +
          " -> [\"timeout -> Instanced:queue_free\"]",
      ]
    );
  }

  [Test]
  public void RepackingKeepsAnOverrideInsideAnEditableInstance()
  {
    WriteFixture("instanced.tscn", HAND_WRITTEN_SCENE);
    var path = WriteFixture("instancing.tscn", INSTANCING_SCENE + "\n" + EDITABLE_INSTANCE);

    Differences(OfFile(path), OfSceneRepacked(path)).ShouldBeEmpty();
  }

  private static Variant OfFile(string path) => _sceneContent.Call("of_file", path);

  private static Variant OfSceneRepacked(string path) => _sceneContent.Call("of_scene_repacked", path);

  private static string[] Differences(Variant before, Variant after) =>
    _sceneContent.Call("differences", before, after).AsStringArray();

  private static string WriteFixture(string fileName, string content) =>
    SceneToolFixtures.Write(FIXTURE_DIR.PathJoin(fileName), content);
}
