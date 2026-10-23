# UID Doctor

Development tools for Godot 4 projects whose text scenes and resources (`.tscn`, `.tres`) are written by hand.
Godot writes identifiers into these files when the editor saves them: the header UID, each `ext_resource` UID and each node `unique_id`.
A hand-written file lacks them, or carries wrong ones.

- `check_scene_uids.gd` fails when a text scene or resource outside `addons/` lacks one of these identifiers or carries a wrong one.
- `resave_scenes.gd` saves the listed files as the editor does, so they get the identifiers an editor save adds.

The tools run as `-s` scripts and have no editor plugin. They are meant for development: exclude `addons/uid_doctor/*` from your export presets.

## Install

With [GodotEnv](https://github.com/chickensoft-games/GodotEnv), declare the addon in `addons.jsonc`:

```jsonc
{
  "addons": {
    "uid_doctor": {
      "url": "https://github.com/anacromaniac/godot-uid-doctor.git",
      "checkout": "v0.1.0",
      "subfolder": "addons/uid_doctor"
    }
  }
}
```

Then run `godotenv addons install`. Without GodotEnv, copy `addons/uid_doctor/` into your project's `addons/`.

## Use

Check every text scene and resource of the project. The exit status is 1 when it finds a problem:

```sh
godot --headless -s res://addons/uid_doctor/check_scene_uids.gd
```

Save hand-written files as the editor does. It needs `--editor`, and C# projects need a `dotnet build` first:

```sh
godot --headless --editor -s res://addons/uid_doctor/resave_scenes.gd -- <res:// paths>
```

Judge both by their exit status: Godot prints leak warnings when a script quits it.

## Develop

The repository root is a Godot C# project that tests the addon with [GoDotTest](https://github.com/chickensoft-games/GoDotTest).

```sh
dotnet build
godot --headless --run-tests --quit-on-finish
```
