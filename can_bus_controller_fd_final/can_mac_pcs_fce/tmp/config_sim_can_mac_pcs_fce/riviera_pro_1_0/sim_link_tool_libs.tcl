# Compile VHDL core files
foreach lib $tool_libraries {
    amap -link $lib
}