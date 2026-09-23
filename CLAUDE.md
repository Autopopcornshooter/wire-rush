# Wire Rush — project instructions

## GDScript investigation
- When investigating GDScript (`.gd`) code in this project — structure, symbol lookup, cross-file references, dependencies — use the **gdscript MCP** tools first (`get_gdscript_structure`, `find_gdscript_symbol`, `find_references`, `get_gdscript_dependencies`, `analyze_gdscript_file`), before falling back to reading whole files with the general-purpose Read tool.
- Only read a full file directly when the MCP tools can't answer the question (e.g. inspecting exact surrounding code/comments at a specific line, or the MCP server isn't connected).
- If the gdscript MCP isn't connected, set the project root first: `set_project_root` → `D:\GameProject\WireSwing`.
