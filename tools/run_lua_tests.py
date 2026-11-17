"""Run every Tests/*.lua under Lua 5.1 (pip install lupa), once as Retail and once as WoW Forever.

Tests run with the addon root as the working directory; the JustLoot handoff tests load
..\\JustLoot\\JustLoot.lua, so a JustLoot checkout must sit next to this one.

Run: python tools/run_lua_tests.py
"""
import glob
import os
import sys

try:
    import lupa.lua51 as lua51
except ImportError:
    sys.exit("needs Lua 5.1 bindings: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    os.chdir(ROOT)
    failures = 0
    for client in ("retail", "forever"):
        for test in sorted(glob.glob(os.path.join("Tests", "*.lua"))):
            lua = lua51.LuaRuntime(unpack_returned_tuples=True)
            run = lua.eval("function(path, ...) return assert(loadfile(path))(...) end")
            try:
                run(test, ROOT, client)
                print(f"PASS [{client}] {test}")
            except Exception as err:  # noqa: BLE001 - report every Lua error
                failures += 1
                print(f"FAIL [{client}] {test}: {str(err).splitlines()[0][:400]}")
    print(f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
