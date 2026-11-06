// 卡片网页的脚本（放在单独文件里，安全规则才能禁止一切内嵌脚本）
// 拾卡调用：show(正面, 背面, 是否已翻面, 主题, 是否紧凑)
function show(front, back, revealed, theme, compact) {
  document.body.className = [theme, revealed ? "revealed" : "", compact ? "compact" : ""].join(" ");
  document.getElementById("front").innerHTML = renderCard(front, "katex");
  document.getElementById("back").innerHTML = renderCard(back, "katex");
  // 多行的长内容左对齐更好读
  for (const id of ["front", "back"]) {
    const el = document.getElementById(id);
    el.classList.toggle("left", el.querySelectorAll("p, li, pre, blockquote").length > 2);
  }
  if (revealed && !compact) {
    const back = document.getElementById("back");
    const audio = back.querySelector("audio");
    if (audio) audio.play().catch(() => {});
  } else if (!revealed) {
    const audio = document.getElementById("front").querySelector("audio");
    if (audio && !compact) audio.play().catch(() => {});
  }
  window.scrollTo(0, 0);
}
