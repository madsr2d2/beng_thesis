import re
import subprocess
import os
import base64

def render_mermaid_to_svg(mmd_content):
    temp_mmd = "temp_diag.mmd"
    temp_svg = "temp_diag.svg"
    
    # Strip any existing YAML config from the content to prevent conflicts
    clean_mmd = re.sub(r'---[\s\S]*?---', '', mmd_content).strip()
    
    with open(temp_mmd, "w") as f:
        f.write(clean_mmd)
    
    # Force mmdc to use our config file
    cmd = [
        "mmdc",
        "-i", temp_mmd,
        "-o", temp_svg,
        "-c", "mermaid-config.json",
        "-b", "transparent"
    ]
    
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        with open(temp_svg, "r") as f:
            svg = f.read()
        return svg
    except Exception as e:
        print(f"Error rendering mermaid: {e}")
        return f"<pre>{mmd_content}</pre>"
    finally:
        if os.path.exists(temp_mmd): os.remove(temp_mmd)
        if os.path.exists(temp_svg): os.remove(temp_svg)

def main():
    with open("docs/report.md", "r") as f:
        content = f.read()

    # Find all mermaid blocks
    mermaid_blocks = re.findall(r'```mermaid([\s\S]*?)```', content)
    
    # Render each block to SVG
    for block in mermaid_blocks:
        print("Rendering diagram with ELK...")
        svg_content = render_mermaid_to_svg(block)
        # We replace the whole block including backticks
        content = content.replace(f"```mermaid{block}```", svg_content)

    # Now use pandoc to convert the "SVG-injected" markdown to HTML
    temp_md = "docs/report_inflated.md"
    with open(temp_md, "w") as f:
        f.write(content)
        
    print("Converting to final HTML...")
    subprocess.run([
        "pandoc", 
        temp_md, 
        "--standalone", 
        "--self-contained",
        "-o", "docs/report.html",
        "--metadata", "title=B.Eng Thesis Report"
    ], check=True)
    
    os.remove(temp_md)
    print("Done! docs/report.html is ready.")

if __name__ == "__main__":
    main()
