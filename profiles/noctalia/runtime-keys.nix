# Noctalia's settings.toml is applied last and wins over declarations, so
# these keys are enforced in the file itself. Nested attrs are TOML tables.
{
  keys = {
    shell.telemetry_enabled = false;
  };

  mkScript =
    pkgs: keys:
    pkgs.writers.writePython3Bin "noctalia-runtime-keys"
      {
        libraries = [ pkgs.python3Packages.tomlkit ];
      }
      ''
        import json
        import os
        import sys

        import tomlkit

        # Usage: noctalia-runtime-keys SETTINGS_TOML
        KEYS = json.loads(${builtins.toJSON (builtins.toJSON keys)})


        def apply(doc, keys):
            for name, value in keys.items():
                if isinstance(value, dict):
                    if name not in doc:
                        doc[name] = tomlkit.table()
                    apply(doc[name], value)
                else:
                    doc[name] = value


        path = sys.argv[1]
        text = ""
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
        doc = tomlkit.parse(text)
        apply(doc, KEYS)
        out = tomlkit.dumps(doc)
        if out != text:
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as handle:
                handle.write(out)
            os.replace(tmp, path)
      '';
}
