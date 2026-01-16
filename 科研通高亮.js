// ==UserScript==
// @name         科研通求助：命中期刊白名单就高亮（刺眼版）
// @namespace    https://www.ablesci.com/
// @version      0.1.0
// @description  在科研通求助列表页，若条目前的期刊名命中白名单则高亮并打标签（亮黄底+红边）
// @match        https://www.ablesci.com/*
// @run-at       document-idle
// ==/UserScript==

(() => {
  "use strict";

  /***********************
   * 1) 你的“有权限期刊列表”
   ***********************/
  const ALLOWED_JOURNALS = [
    "CHIN J NAT MEDICINES",
    "VET CLIN N AM-SMALL",
    "ACTA OTO-LARYNGOL",
      "APPL PHYS LETT"
    // ...继续加
  ];

  /***********************
   * 2) 工具：规范化（避免大小写/多空格/破折号差异）
   ***********************/
  const norm = (s) =>
    (s || "")
      .toUpperCase()
      .trim()
      .replace(/\s+/g, " ")
      .replace(/[‐-–—]/g, "-"); // 各种破折号统一成 -

  const allowedSet = new Set(ALLOWED_JOURNALS.map(norm));

  /***********************
   * 3) 注入 CSS（刺眼高亮）
   ***********************/
  function injectStyleOnce() {
    if (document.getElementById("ablesci-allowed-style")) return;

    const style = document.createElement("style");
    style.id = "ablesci-allowed-style";
    style.textContent = `
      .ablesci-allowed {
        outline: 4px solid #ff0033 !important;
        border-radius: 12px !important;
        background: rgba(255, 230, 0, 0.45) !important;
        box-shadow: 0 0 0 6px rgba(255, 230, 0, 0.25), 0 12px 28px rgba(0,0,0,0.18) !important;
        animation: ablesciPulse 1.2s ease-in-out infinite;
      }

      .ablesci-allowed-tag {
        display: inline-block;
        margin-left: 8px;
        padding: 2px 8px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 700;
        border: 2px solid #ff0033;
        background: #ff0033;
        color: #ffffff;
      }

      @keyframes ablesciPulse {
        0%, 100% { filter: saturate(1) brightness(1); }
        50% { filter: saturate(1.6) brightness(1.15); }
      }
    `;
    document.head.appendChild(style);
  }

  /***********************
   * 4) 找“每条求助”的根节点 + 提取期刊名 span
   ***********************/
  function getRequestItems() {
    const links = [...document.querySelectorAll('a[href*="/assist/detail"]')];
    const items = new Set();
    for (const a of links) {
      const root = a.closest("li, article, .item, .card, .list-item, .ant-list-item, div");
      if (root) items.add(root);
    }
    return [...items];
  }

  function extractJournalFromItem(item) {
    const spans = [...item.querySelectorAll("span[title]")]
      .filter((s) => (s.getAttribute("style") || "").includes("#ededed"));

    const pick =
      spans.find((s) => /^[A-Z0-9][A-Z0-9 .&\-]+$/.test(s.textContent.trim())) || spans[0];

    if (!pick) return null;
    return pick.getAttribute("title")?.trim() || pick.textContent.trim();
  }

  /***********************
   * 5) 高亮逻辑（可重复调用）
   ***********************/
  function highlightAllowed() {
    // 详情页不处理（只在列表页高亮）
    if (location.pathname.includes("/assist/detail")) return;

    injectStyleOnce();

    const items = getRequestItems();
    const unmatched = new Set();

    for (const item of items) {
      // 清理旧状态（无限滚动/翻页重复渲染不会叠）
      item.classList.remove("ablesci-allowed");
      item.querySelectorAll(".ablesci-allowed-tag").forEach((el) => el.remove());

      const j = extractJournalFromItem(item);
      if (!j) continue;

      const ok = allowedSet.has(norm(j));
      if (ok) {
        item.classList.add("ablesci-allowed");

        const tag = document.createElement("span");
        tag.className = "ablesci-allowed-tag";
        tag.textContent = "本校有权限";

        // 尽量插在期刊 span 附近；找不到就塞到条目末尾
        const journalSpan = [...item.querySelectorAll("span[title]")].find(
          (s) => norm(s.getAttribute("title") || s.textContent) === norm(j)
        );
        (journalSpan?.parentElement || item).appendChild(tag);
      } else {
        unmatched.add(norm(j));
      }
    }

    // 给你一个“补白名单”的线索
    if (unmatched.size) {
      console.log("未命中的期刊（可拿去补白名单）:", [...unmatched].sort());
    }
  }

  /***********************
   * 6) 触发：初次 + 监听异步加载（无限滚动/切换页）
   ***********************/
  highlightAllowed();

  const obs = new MutationObserver(() => {
    clearTimeout(highlightAllowed._t);
    highlightAllowed._t = setTimeout(highlightAllowed, 300);
  });
  obs.observe(document.documentElement, { childList: true, subtree: true });

  // 兜底：偶尔扫一次（有些站点更新 DOM 不触发 observer 的情况）
  setInterval(highlightAllowed, 2500);
})();
