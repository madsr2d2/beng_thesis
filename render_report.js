const puppeteer = require('/home/madsr2d2/.local/npm/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer');
const fs = require('fs');
const path = require('path');

async function render() {
    const mdPath = path.join(__dirname, 'docs/report.md');
    const htmlPath = path.join(__dirname, 'docs/report.html');
    const tempHtmlPath = path.join(__dirname, 'docs/temp_render.html');
    let markdown = fs.readFileSync(mdPath, 'utf8');

    const htmlContent = `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>B.Eng Thesis Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; line-height: 1.6; max-width: 1000px; margin: 40px auto; padding: 20px; background: #0d1117; color: #c9d1d9; }
        pre { background: #161b22; padding: 16px; border-radius: 6px; overflow: auto; border: 1px solid #30363d; }
        code { font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, Liberation Mono, monospace; font-size: 85%; }
        h1, h2, h3 { border-bottom: 1px solid #21262d; padding-bottom: .3em; color: #f0f6f2; }
        table { border-collapse: collapse; width: 100%; margin: 24px 0; border-spacing: 0; }
        th, td { border: 1px solid #30363d; padding: 6px 13px; text-align: left; }
        th { background: #161b22; font-weight: 600; }
        tr:nth-child(2n) { background: #0d1117; }
        .mermaid { background: transparent !important; margin: 20px 0; display: flex; justify-content: center; min-height: 100px; }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/mermaid@11.4.0/dist/mermaid.min.js"></script>
</head>
<body>
    <div id="content"></div>
    <script>
        (async () => {
            const rawMarkdown = ${JSON.stringify(markdown)};
            
            const renderer = new marked.Renderer();
            renderer.code = function({text, lang, escaped}) {
                if (lang === 'mermaid') {
                    const cleanText = text.replace(/---[\\s\\S]*?---/, '');
                    return '<div class="mermaid">' + cleanText + '</div>';
                }
                return '<pre><code class="language-' + lang + '">' + text + '</code></pre>';
            };

            document.getElementById('content').innerHTML = marked.parse(rawMarkdown, { renderer });

            // In Mermaid 11+ non-ESM, we might need a different approach for ELK if not bundled
            // But let's try standard init first
            mermaid.initialize({
                startOnLoad: true,
                theme: 'dark',
                securityLevel: 'loose',
                flowchart: { defaultRenderer: 'elk', curve: 'linear' },
                elk: { algorithm: 'layered', mergeEdges: false, nodePlacementStrategy: 'SIMPLE' }
            });
            
            // Wait for a few seconds to let mermaid do its thing
            setTimeout(() => {
                window.mermaidDone = true;
            }, 5000);
        })();
    </script>
</body>
</html>
`;

    fs.writeFileSync(tempHtmlPath, htmlContent);

    const browser = await puppeteer.launch({
        executablePath: '/usr/bin/google-chrome',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    const page = await browser.newPage();
    page.on('console', msg => console.log('BROWSER:', msg.text()));

    console.log('Loading temporary page...');
    await page.goto('file://' + tempHtmlPath, { waitUntil: 'networkidle0' });
    
    console.log('Waiting for Mermaid rendering...');
    await page.waitForFunction('window.mermaidDone === true', { timeout: 20000 });
    
    const finalHtml = await page.content();
    fs.writeFileSync(htmlPath, finalHtml);
    fs.unlinkSync(tempHtmlPath);
    
    console.log('Success! Report rendered to docs/report.html');
    await browser.close();
}

render().catch(err => {
    console.error(err);
    process.exit(1);
});
