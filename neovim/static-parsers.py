"""Small source adaptation for the seven upstream parsers on static musl.

No dummy .so files: real archives are linked into nvim and selected explicitly.
Explicit custom parser paths still use the upstream loader (and cannot dlopen).
"""
from pathlib import Path

languages = ('c', 'lua', 'vim', 'vimdoc', 'query', 'markdown', 'markdown_inline')
for filename in ('TreesitterParserCMakeLists.txt', 'MarkdownParserCMakeLists.txt'):
    path = Path('cmake.deps/cmake') / filename
    source = path.read_text()
    assert 'MODULE' in source and 'LIBRARY DESTINATION' in source
    path.write_text(source.replace('MODULE', 'STATIC').replace('LIBRARY DESTINATION', 'ARCHIVE DESTINATION'))

path = Path('src/nvim/CMakeLists.txt')
with path.open('a') as output:
    output.write('\n# Local static-musl adaptation: upstream bundled parser archives.\n')
    for language in languages:
        output.write(f'target_link_libraries(nvim_bin PRIVATE "${{DEPS_PREFIX}}/lib/nvim/parser/{language}.a")\n')

path = Path('src/nvim/lua/treesitter.c')
source = path.read_text()
marker = '#include <tree_sitter/api.h>'
assert source.count(marker) == 1
declarations = '\n'.join(f'extern const TSLanguage *tree_sitter_{lang}(void);' for lang in languages)
source = source.replace(marker, marker + '\n' + declarations)
marker = '  uv_lib_t lib;\n'
assert source.count(marker) == 1
dispatch = '  if (strcmp(path, ":builtin:") == 0) {\n'
for lang in languages:
    dispatch += f'    if (strcmp(symbol, "{lang}") == 0) {{ return tree_sitter_{lang}(); }}\n'
dispatch += '    luaL_error(L, "No statically linked parser: %s", symbol);\n  }\n'
path.write_text(source.replace(marker, dispatch + marker))

path = Path('runtime/lua/vim/treesitter/language.lua')
source = path.read_text()
marker = '  if path == nil then\n'
assert source.count(marker) == 1
table = ', '.join(lang + ' = true' for lang in languages)
dispatch = ('  -- Local static-musl adaptation: real built-in parsers, not runtime .so files.\n'
            f'  local builtin = {{ {table} }}\n'
            '  if path == nil and builtin[lang] then\n'
            '    path = ":builtin:"\n'
            '  end\n\n')
path.write_text(source.replace(marker, dispatch + marker))
