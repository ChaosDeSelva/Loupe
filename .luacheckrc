-- LÖVE runs on LuaJIT; target its standard library everywhere.
std = "luajit"
max_line_length = 100
codes = true

-- .claude/ holds agent worktrees: full copies of the repo with their own checks.
exclude_files = { "lua_modules/", ".luarocks/", ".claude/" }

-- The library may read `love`, but never define globals. (core/ must not
-- touch `love` at all; tools/check.sh enforces that with a grep.)
files["loupe"] = { read_globals = { "love" } }

-- Games define callbacks by assigning fields on the `love` table.
files["examples"] = { globals = { "love" } }

files["spec"] = { std = "+busted", globals = { "love" } }
