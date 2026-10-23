namespace UidDoctor.Tests;

using Godot;

// Writes the fixture files of the addon tests to a scratch folder outside the project.
public static class SceneToolFixtures
{
  public static void Recreate(string dir)
  {
    Delete(dir);
    DirAccess.MakeDirRecursiveAbsolute(dir);
  }

  public static void Delete(string dir)
  {
    if (!DirAccess.DirExistsAbsolute(dir))
    {
      return;
    }
    foreach (var subdir in DirAccess.GetDirectoriesAt(dir))
    {
      Delete(dir.PathJoin(subdir));
    }
    foreach (var file in DirAccess.GetFilesAt(dir))
    {
      DirAccess.RemoveAbsolute(dir.PathJoin(file));
    }
    DirAccess.RemoveAbsolute(dir);
  }

  public static string Write(string path, string content)
  {
    DirAccess.MakeDirRecursiveAbsolute(path.GetBaseDir());
    using var file = FileAccess.Open(path, FileAccess.ModeFlags.Write);
    file.StoreString(content);
    return path;
  }
}
