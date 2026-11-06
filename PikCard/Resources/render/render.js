// 把卡片的 Markdown 变成网页：公式先用 KaTeX 排好（不让 Markdown 把公式里的 _ * 当成格式），再交给 markdown-it。
// mathMode = "katex"：拾卡里显示；"anki"：导出给 Anki，公式换成 Anki 认识的 \( \) 和 \[ \]
(function () {
  const md = markdownit({ html: true, linkify: true, breaks: true });
  const MATH = /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$([^\s$](?:[^$\n]*?[^\s$\\])?)\$/g;

  function escapeHTML(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  globalThis.renderCard = function (src, mathMode) {
    const pieces = [];
    const text = String(src || "").replace(MATH, (whole, a, b, c, d) => {
      const tex = a ?? b ?? c ?? d;
      const display = a != null || b != null;
      let html;
      if (mathMode === "anki") {
        html = display ? "\\[" + escapeHTML(tex) + "\\]" : "\\(" + escapeHTML(tex) + "\\)";
      } else {
        try {
          html = katex.renderToString(tex, { displayMode: display, throwOnError: false });
        } catch (e) {
          html = escapeHTML(whole);
        }
      }
      pieces.push(html);
      return "" + (pieces.length - 1) + "";
    });
    return md.render(text).replace(/(\d+)/g, (_, i) => pieces[+i]);
  };
})();
