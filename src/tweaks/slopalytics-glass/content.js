(function () {
  "use strict";

  // Presentation only: React keeps ownership of every chart, control and route.
  const host = location.hostname.toLowerCase().replace(/\.$/, "");
  if (window.self !== window.top || !["slopalytics.com", "www.slopalytics.com"].includes(host) ||
      document.documentElement?.hasAttribute("data-graft-ui")) return;
  const ATTRIBUTE = "data-graft-slopalytics-glass";
  const STYLE_ID = "graft-slopalytics-glass-style";
  const KEY = "slopalyticsGlassEnabled";
  let revision = 0;

  const CSS = String.raw`
html[data-graft-slopalytics-glass] {
  --bg: #f4f7fe; --surface: #f8faff; --hover: #e9e5fc;
  --fg: #151c3b; --fg-2: #485774; --fg-3: #60708a;
  --line: #dce2f0; --line-2: #bdc8df; --accent: #7447f5; --on-accent: #fff;
  --sg-panel: rgba(250,252,255,.76); --sg-solid: #f8faff;
  --sg-selected: #e9e3fc; --sg-shadow: 0 8px 30px #52689812, inset 0 1px 0 #ffffffb3;
  --sg-backdrop: radial-gradient(ellipse at 5% 0%, #dcecff 0%, transparent 55%), radial-gradient(ellipse at 95% 15%, #e7defb 0%, transparent 55%);
  color-scheme: light !important;
}
html[data-graft-slopalytics-glass][data-theme="dark"] {
  --bg: #121a2e; --surface: #1b2640; --hover: #2b3652;
  --fg: #edf1ff; --fg-2: #c0c9e2; --fg-3: #99a9c9;
  --line: #303d59; --line-2: #4a5b7d; --accent: #b9a2ff; --on-accent: #151d32;
  --sg-panel: rgba(27,38,64,.84); --sg-solid: #1b2640;
  --sg-selected: #3b315c; --sg-shadow: 0 8px 30px #03081826, inset 0 1px 0 #ffffff0c;
  --sg-backdrop: radial-gradient(ellipse at 5% 0%, #1b3555 0%, transparent 55%), radial-gradient(ellipse at 95% 15%, #302447 0%, transparent 55%);
  color-scheme: dark !important;
}
html[data-graft-slopalytics-glass] body { background: var(--sg-backdrop), var(--bg); color-scheme: inherit !important; }
html[data-graft-slopalytics-glass] .app { padding: 16px; gap: 14px; }
html[data-graft-slopalytics-glass] .app-header,
html[data-graft-slopalytics-glass] .sidebar,
html[data-graft-slopalytics-glass] .chart-section {
  border: 1px solid var(--line); border-radius: 20px;
  background: var(--sg-panel); box-shadow: var(--sg-shadow);
}
html[data-graft-slopalytics-glass] .app-header,
html[data-graft-slopalytics-glass] .sidebar {
  -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px);
}
html[data-graft-slopalytics-glass] .app-header { padding: 10px 18px; position: relative; z-index: 8; }
html[data-graft-slopalytics-glass] .brand strong { font-weight: 650; letter-spacing: -1px; }
html[data-graft-slopalytics-glass] .brand strong span { color: var(--fg); }
html[data-graft-slopalytics-glass] .section-tabs { gap: 5px; border: 0; padding-right: 0; }
html[data-graft-slopalytics-glass] .section-tabs button { padding: 8px 14px; border-radius: 12px; font-size: 13px; font-weight: 600; }
html[data-graft-slopalytics-glass] .view-tabs { gap: 5px; align-items: center; }
html[data-graft-slopalytics-glass] .view-tabs button { min-height: 36px; padding: 8px 13px; border-radius: 11px; }
html[data-graft-slopalytics-glass] .view-tabs button.active:after { display: none; }
html[data-graft-slopalytics-glass] :is(.view-tabs,.section-tabs) button.active {
  color: var(--accent); background: var(--sg-selected); box-shadow: inset 0 0 0 1px var(--line);
}
html[data-graft-slopalytics-glass] .tab-divider { display: none; }
html[data-graft-slopalytics-glass] :is(.icon-button,.chart-settings summary) {
  border: 1px solid var(--line); border-radius: 11px; background: var(--sg-panel); width: 34px; height: 34px;
}
html[data-graft-slopalytics-glass] .header-actions { gap: 7px; }
html[data-graft-slopalytics-glass] .body-layout { gap: 14px; }
html[data-graft-slopalytics-glass] .chart-feed { border-radius: 20px; }
html[data-graft-slopalytics-glass] .chart-section { padding: 20px 24px 12px; }
html[data-graft-slopalytics-glass] .chart-section + .chart-section { margin-top: 14px; }
html[data-graft-slopalytics-glass] .chart-heading { margin-bottom: 12px; }
html[data-graft-slopalytics-glass] .chart-heading h2,
html[data-graft-slopalytics-glass] .popularity-section > h2 { font-size: 21px; font-weight: 650; letter-spacing: -.5px; }
html[data-graft-slopalytics-glass] .chart-controls { gap: 12px; }
html[data-graft-slopalytics-glass] .chart-scale,
html[data-graft-slopalytics-glass] .pop-switch { gap: 3px; padding: 3px; border: 1px solid var(--line); border-radius: 11px; background: var(--sg-panel); }
html[data-graft-slopalytics-glass] :is(.chart-scale,.pop-switch) button { padding: 5px 10px; border: 0; border-radius: 8px; }
html[data-graft-slopalytics-glass] .chart-scale button[aria-pressed="true"],
html[data-graft-slopalytics-glass] .pop-switch button.active { color: var(--accent); background: var(--sg-selected); }
html[data-graft-slopalytics-glass] .sidebar { padding: 20px 16px; gap: 19px; }
html[data-graft-slopalytics-glass] .side-heading h2 { font-size: 18px; font-weight: 650; }
html[data-graft-slopalytics-glass] .search { border: 1px solid var(--line-2); border-radius: 12px; padding: 0 10px; min-height: 38px; background: var(--sg-panel); }
html[data-graft-slopalytics-glass] .search:focus-within { outline: 2px solid var(--accent); outline-offset: 2px; }
html[data-graft-slopalytics-glass] .effort-filter > div { gap: 5px; }
html[data-graft-slopalytics-glass] .effort-filter button { border: 1px solid var(--line); border-radius: 8px; padding: 5px 7px; }
html[data-graft-slopalytics-glass] .effort-filter button[aria-pressed="true"] { background: var(--sg-selected); color: var(--accent); }
html[data-graft-slopalytics-glass] .model-row { width: 100%; margin: 3px 0; padding: 6px 8px; border-radius: 9px; min-height: 31px; }
html[data-graft-slopalytics-glass] .model-row[aria-pressed="true"] { background: var(--hover); }
html[data-graft-slopalytics-glass] :is(.model-row,.pop-filter):hover { box-shadow: inset 0 0 0 1px var(--line-2); }
html[data-graft-slopalytics-glass] :is(.settings-popover,.chart-tooltip,.context-menu) {
  background: var(--sg-solid); border: 1px solid var(--line-2); border-radius: 15px; box-shadow: 0 14px 40px #10234426;
}
html[data-graft-slopalytics-glass] .pop-filter { border-radius: 9px; padding: 7px; margin: 3px 0; }
html[data-graft-slopalytics-glass] .pop-filter.selected { background: var(--hover); }
html[data-graft-slopalytics-glass] .pop-check { border-radius: 4px; }
html[data-graft-slopalytics-glass] .pop-toolbar { gap: 14px; flex-wrap: wrap; }
html[data-graft-slopalytics-glass] .pop-metrics { padding-right: 14px; }
html[data-graft-slopalytics-glass] .pop-rank { border-radius: 8px; padding: 2px 5px; }
html[data-graft-slopalytics-glass] .pop-stats { gap: 10px; }
html[data-graft-slopalytics-glass] .pop-stats > div { border: 1px solid var(--line); border-radius: 10px; padding: 10px; background: var(--sg-panel); }
html[data-graft-slopalytics-glass] .pop-stats strong { font-size: 16px; }
html[data-graft-slopalytics-glass] .pop-method pre { background: var(--hover); border-radius: 10px; padding: 10px; }
html[data-graft-slopalytics-glass] footer { border: 0; padding: 9px 12px 0; }
/* Desktop follows the chosen concept: top bar, left inspector, separate view strip. */
@media (min-width: 901px) {
  html[data-graft-slopalytics-glass] { --header-height: 80px; --sidebar-width: 286px; }
  html[data-graft-slopalytics-glass] .app { padding: 20px 18px 60px; gap: 18px; }
  html[data-graft-slopalytics-glass] .app > .app-header { display: flex; gap: 42px; padding: 14px 24px; }
  html[data-graft-slopalytics-glass] .brand strong { font-size: 32px; font-weight: 700; }
  html[data-graft-slopalytics-glass] .brand::before { content: ""; width: 39px; height: 30px; display: inline-block; vertical-align: middle; margin-right: 10px; background: linear-gradient(135deg,#58d5f1,#9a72ff 65%,#ded7ff); clip-path: polygon(0 90%,27% 30%,45% 57%,65% 0,83% 13%,100% 90%,78% 90%,65% 48%,47% 88%,28% 63%,15% 100%); }
  html[data-graft-slopalytics-glass] .section-tabs { background: var(--hover); border-radius: 18px; padding: 4px; gap: 6px; }
  html[data-graft-slopalytics-glass] .section-tabs button { font-size: 18px; padding: 10px 22px; min-height: 46px; border-radius: 15px; }
  html[data-graft-slopalytics-glass] .view-tabs { position: absolute; top: calc(100% + 19px); left: calc(var(--sidebar-width) + 18px); width: calc(100% - var(--sidebar-width) - 18px); height: 60px; padding: 8px; gap: 5px; border: 1px solid var(--line); border-radius: 17px; background: var(--sg-panel); box-shadow: var(--sg-shadow); backdrop-filter: blur(18px); }
  html[data-graft-slopalytics-glass] .view-tabs button { min-height: 42px; padding: 8px 12px; font-size: 13px; flex: 1 0 auto; justify-content: center; border: 1px solid var(--line); background: var(--sg-panel); box-shadow: 0 3px 7px #6275a512; }
  html[data-graft-slopalytics-glass] .view-tabs button.active { background: var(--sg-selected); }
  html[data-graft-slopalytics-glass] .view-tabs button::before { content: ""; width: 15px; height: 15px; margin-right: 7px; flex-shrink: 0; background: currentColor; mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'%3E%3Ccircle cx='4' cy='14' r='2'/%3E%3Ccircle cx='8' cy='9' r='2'/%3E%3Ccircle cx='13' cy='11' r='2'/%3E%3Ccircle cx='16' cy='4' r='2'/%3E%3C/svg%3E") center/contain no-repeat; }
  html[data-graft-slopalytics-glass] :is(.icon-button,.chart-settings summary) { width: 44px; height: 44px; border-radius: 14px; box-shadow: 0 3px 8px #6275a512; }
  html[data-graft-slopalytics-glass] .body-layout { gap: 18px; grid-template-columns: var(--sidebar-width) minmax(0,1fr); }
  html[data-graft-slopalytics-glass] .body-layout > main { grid-column: 2; grid-row: 1; padding-top: 78px; }
  html[data-graft-slopalytics-glass] .body-layout > .sidebar { grid-column: 1; grid-row: 1; }
  html[data-graft-slopalytics-glass] .chart-heading { flex-direction: column; align-items: flex-start; gap: 15px; margin-bottom: 16px; }
  html[data-graft-slopalytics-glass] .chart-heading h2 { font-size: 30px; font-weight: 700; }
  html[data-graft-slopalytics-glass] .chart-controls { gap: 20px; }
  html[data-graft-slopalytics-glass] .chart-controls :is(.pareto-toggle,.chart-scale button) { font-size: 15px; min-height: 36px; }
  html[data-graft-slopalytics-glass] .view-tabs:has(button:nth-of-type(6)) button:nth-of-type(2)::before { mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='black' stroke-width='1.5'%3E%3Ccircle cx='10' cy='10' r='8'/%3E%3Cpath d='M10 4v6l4 3'/%3E%3C/svg%3E"); }
  html[data-graft-slopalytics-glass] .view-tabs:has(button:nth-of-type(6)) button:nth-of-type(3)::before { mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='black' stroke-width='1.5'%3E%3Cpath d='m2 7 8-5 8 5-8 5zM2 11l8 5 8-5M2 15l8 4 8-4'/%3E%3C/svg%3E"); }
  html[data-graft-slopalytics-glass] .view-tabs:has(button:nth-of-type(6)) button:nth-of-type(4)::before { mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='black' stroke-width='1.5'%3E%3Cellipse cx='10' cy='4' rx='7' ry='3'/%3E%3Cpath d='M3 4v12c0 4 14 4 14 0V4M3 10c0 4 14 4 14 0'/%3E%3C/svg%3E"); }
  html[data-graft-slopalytics-glass] .view-tabs:has(button:nth-of-type(6)) button:nth-of-type(5)::before { mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='black' stroke-width='1.5'%3E%3Cellipse cx='7' cy='9' rx='5' ry='2'/%3E%3Cpath d='M2 9v7c0 3 10 3 10 0V9M8 5c0-3 10-3 10 0v8c0 2-3 3-5 2'/%3E%3C/svg%3E"); }
  html[data-graft-slopalytics-glass] .view-tabs:has(button:nth-of-type(6)) button:nth-of-type(6)::before { mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20' fill='none' stroke='black' stroke-width='1.5'%3E%3Crect x='2' y='3' width='16' height='14' rx='2'/%3E%3Cpath d='M2 7h16M5 13h5'/%3E%3C/svg%3E"); }
  html[data-graft-slopalytics-glass] footer { position: fixed; bottom: 10px; left: 18px; right: 18px; min-height: 39px; padding: 8px 20px; border-radius: 15px; border: 1px solid var(--line); background: var(--sg-panel); font-size: 12px; }
  html[data-graft-slopalytics-glass] .pop-stats { grid-template-columns: repeat(4,minmax(0,1fr)); }
}
@media (max-width: 1150px) and (min-width: 901px) {
  html[data-graft-slopalytics-glass] { --sidebar-width: 242px; }
  html[data-graft-slopalytics-glass] .app > .app-header { gap: 22px; padding: 12px 18px; }
  html[data-graft-slopalytics-glass] .brand strong { font-size: 27px; }
  html[data-graft-slopalytics-glass] .brand::before { width: 28px; margin-right: 7px; }
  html[data-graft-slopalytics-glass] .section-tabs button { font-size: 15px; padding: 10px 15px; }
  html[data-graft-slopalytics-glass] .chart-section { padding: 16px; }
  html[data-graft-slopalytics-glass] .chart-controls { flex-wrap: wrap; }
  html[data-graft-slopalytics-glass] .pop-panel-body { grid-template-columns: minmax(0,1fr) 200px; }
}
@media (max-width: 900px) {
  html[data-graft-slopalytics-glass] .app { padding: 8px; }
  html[data-graft-slopalytics-glass] .app > .app-header { position: sticky; top: 8px; padding: 0; gap: 0; background: var(--sg-solid); border-radius: 16px; }
  html[data-graft-slopalytics-glass] .brand { padding-left: 12px; }
  html[data-graft-slopalytics-glass] .section-tabs { margin-left: 10px; gap: 2px; }
  html[data-graft-slopalytics-glass] .section-tabs button { padding: 6px; font-size: 11px; }
  html[data-graft-slopalytics-glass] .header-actions { padding-right: 7px; gap: 3px; }
  html[data-graft-slopalytics-glass] .view-tabs { padding: 4px 8px; height: 48px; border-top: 1px solid var(--line); }
  html[data-graft-slopalytics-glass] .view-tabs button { min-height: 38px; padding: 7px 11px; }
  html[data-graft-slopalytics-glass] .body-layout { margin-top: 12px; }
  html[data-graft-slopalytics-glass] .chart-section { padding: 16px 12px 20px; scroll-margin-top: 120px; }
  html[data-graft-slopalytics-glass] .chart-heading h2 { font-size: 18px; }
  html[data-graft-slopalytics-glass] .chart-controls { gap: 8px; }
  html[data-graft-slopalytics-glass] :is(.chart-scale,.pop-switch) button { padding: 5px 8px; }
  html[data-graft-slopalytics-glass] .sidebar { border-radius: 0; padding: 0 16px calc(24px + env(safe-area-inset-bottom)); background: var(--sg-solid); }
  html[data-graft-slopalytics-glass] .side-heading { background: var(--sg-solid); }
  html[data-graft-slopalytics-glass] .model-row { min-height: 44px; }
  html[data-graft-slopalytics-glass] .pop-stats { grid-template-columns: repeat(2,minmax(0,1fr)); }
  html[data-graft-slopalytics-glass] footer { padding: 18px 8px; }
}
@media (max-width: 370px) {
  html[data-graft-slopalytics-glass] .brand strong { font-size: 18px; }
  html[data-graft-slopalytics-glass] .section-tabs { margin-left: 5px; }
}
/* Match the concept's larger inspector controls without replacing any DOM nodes. */
html[data-graft-slopalytics-glass] .side-heading h2 { font-size: 22px; }
html[data-graft-slopalytics-glass] .sidebar { gap: 22px; padding-top: 20px; }
html[data-graft-slopalytics-glass] .search { min-height: 42px; border-radius: 14px; box-shadow: 0 4px 10px #5268980c; }
html[data-graft-slopalytics-glass] .search input { font-size: 14px; }
html[data-graft-slopalytics-glass] :is(.effort-filter h3,.section-head h3) { font-size: 15px; }
html[data-graft-slopalytics-glass] .effort-filter > div { display: grid; grid-template-columns: repeat(3,minmax(0,1fr)); gap: 7px; }
html[data-graft-slopalytics-glass] .effort-filter button { border-radius: 14px; font-size: 13px; padding: 7px; background: var(--sg-panel); box-shadow: 0 3px 8px #52689812; }
html[data-graft-slopalytics-glass] .effort-filter button[aria-pressed="false"] { text-decoration: none; }
html[data-graft-slopalytics-glass] .model-row { gap: 9px; min-height: 33px; font-size: 13px; }
html[data-graft-slopalytics-glass] .model-row > .lab-logo,
html[data-graft-slopalytics-glass] .model-row > .lab-monogram,
html[data-graft-slopalytics-glass] .model-dot { display: none; }
html[data-graft-slopalytics-glass] .model-row::before { content: ""; width: 17px; height: 17px; flex-shrink: 0; border: 1px solid var(--sg-series,var(--line-2)); border-radius: 5px; display: grid; place-items: center; font-size: 13px; }
html[data-graft-slopalytics-glass] .model-row[aria-pressed="true"]::before { background: var(--sg-series,var(--accent)) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'%3E%3Cpath d='m4 10 4 4 8-9' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E") center/15px no-repeat; }
html[data-graft-slopalytics-glass] .model-row[aria-pressed="true"] { background: var(--sg-tint,var(--hover)); }
html[data-graft-slopalytics-glass] .model-row[title$="· OpenAI"] { --sg-series: #8655ef; --sg-tint: #955ff51c; }
html[data-graft-slopalytics-glass] .model-row[title$="· Anthropic"] { --sg-series: #ec715f; --sg-tint: #ff80661c; }
html[data-graft-slopalytics-glass] .model-row[title$="· Google"] { --sg-series: #139faf; --sg-tint: #22bacb1c; }
html[data-graft-slopalytics-glass] .browse-options > button { padding: 10px 12px; border-radius: 12px; text-align: center; color: white; background: linear-gradient(135deg,#9168fb,#7545e8); box-shadow: 0 5px 12px #8052d92e; }
html[data-graft-slopalytics-glass] .pareto-toggle { padding: 5px 11px; border: 1px solid var(--line); border-radius: 12px; background: var(--sg-panel); }
html[data-graft-slopalytics-glass] .selection { width: 17px; height: 17px; border-radius: 5px; }
html[data-graft-slopalytics-glass] .selection.checked { background: linear-gradient(135deg,#a17aff,#7b4cf0); border-color: #9168ec; color: white; }
html[data-graft-slopalytics-glass] .chart-svg > rect:first-child { fill: transparent; }
html[data-graft-slopalytics-glass] .chart-svg line[stroke="var(--line)"] { stroke-dasharray: none; opacity: .8; }
@media (max-width: 900px) {
  html[data-graft-slopalytics-glass] .sidebar { padding-top: 0; }
  html[data-graft-slopalytics-glass] .model-row { min-height: 44px; font-size: 15px; }
}
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#586878, #c5cbd3)"] { fill: #8051d4; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#586878, #c5cbd3)"] { stroke: #8051d4; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#586878, #c5cbd3)"] { fill: #b59afa; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#586878, #c5cbd3)"] { stroke: #b59afa; }
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#697788, #acb6c2)"] { fill: #9667ed; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#697788, #acb6c2)"] { stroke: #9667ed; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#697788, #acb6c2)"] { fill: #c8adff; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#697788, #acb6c2)"] { stroke: #c8adff; }
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#303840, #f1f3f5)"] { fill: #6840bd; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#303840, #f1f3f5)"] { stroke: #6840bd; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#303840, #f1f3f5)"] { fill: #e0cfff; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#303840, #f1f3f5)"] { stroke: #e0cfff; }
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#748292, #939daa)"] { fill: #a783dd; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#748292, #939daa)"] { stroke: #a783dd; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#748292, #939daa)"] { fill: #9c7ed6; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#748292, #939daa)"] { stroke: #9c7ed6; }
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#903e2b, #cc785c)"] { fill: #e56b61; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#903e2b, #cc785c)"] { stroke: #e56b61; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#903e2b, #cc785c)"] { fill: #ff9b90; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#903e2b, #cc785c)"] { stroke: #ff9b90; }
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#c4805f, #b98a74)"] { fill: #e99a7b; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#c4805f, #b98a74)"] { stroke: #e99a7b; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#c4805f, #b98a74)"] { fill: #edaf99; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#c4805f, #b98a74)"] { stroke: #edaf99; }
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#ae5235, #df9477)"] { fill: #ec806d; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#ae5235, #df9477)"] { stroke: #ec806d; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#ae5235, #df9477)"] { fill: #ffc2ad; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#ae5235, #df9477)"] { stroke: #ffc2ad; }
html[data-graft-slopalytics-glass] .chart-svg [fill="light-dark(#176b38, #34a853)"] { fill: #0da9bd; }
html[data-graft-slopalytics-glass] .chart-svg [stroke="light-dark(#176b38, #34a853)"] { stroke: #0da9bd; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [fill="light-dark(#176b38, #34a853)"] { fill: #56d8e7; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-svg [stroke="light-dark(#176b38, #34a853)"] { stroke: #56d8e7; }
/* Keep inline mobile legends consistent with the recolored benchmark plots. */
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(88, 104, 120)"] { color: #8051d4 !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(88, 104, 120)"] { color: #b59afa !important; }
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(105, 119, 136)"] { color: #9667ed !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(105, 119, 136)"] { color: #c8adff !important; }
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(48, 56, 64)"] { color: #6840bd !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(48, 56, 64)"] { color: #e0cfff !important; }
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(116, 130, 146)"] { color: #a783dd !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(116, 130, 146)"] { color: #9c7ed6 !important; }
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(144, 62, 43)"] { color: #e56b61 !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(144, 62, 43)"] { color: #ff9b90 !important; }
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(196, 128, 95)"] { color: #e99a7b !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(196, 128, 95)"] { color: #edaf99 !important; }
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(174, 82, 53)"] { color: #ec806d !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(174, 82, 53)"] { color: #ffc2ad !important; }
html[data-graft-slopalytics-glass] .chart-section [style*="color: light-dark(rgb(23, 107, 56)"] { color: #0da9bd !important; }
html[data-graft-slopalytics-glass][data-theme="dark"] .chart-section [style*="color: light-dark(rgb(23, 107, 56)"] { color: #56d8e7 !important; }
@media (prefers-reduced-transparency: reduce) {
  html[data-graft-slopalytics-glass] { --sg-panel: var(--sg-solid); }
  html[data-graft-slopalytics-glass] :is(.app-header,.sidebar) { -webkit-backdrop-filter: none; backdrop-filter: none; }
}
@media (forced-colors: active) {
  html[data-graft-slopalytics-glass] { --sg-panel: Canvas; --sg-solid: Canvas; --sg-selected: Highlight; --fg: CanvasText; --fg-2: CanvasText; --fg-3: CanvasText; --accent: LinkText; --line: ButtonBorder; --line-2: ButtonBorder; --hover: Canvas; --bg: Canvas; --sg-shadow: none; --sg-backdrop: none; }
}
`;

  function remove() {
    document.documentElement?.removeAttribute(ATTRIBUTE);
    document.getElementById(STYLE_ID)?.remove();
  }

  function apply(enabled) {
    if (!enabled) { remove(); return; }
    if (!document.documentElement) return;
    let style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement("style");
      style.id = STYLE_ID;
      style.textContent = CSS;
      (document.head || document.documentElement).appendChild(style);
    }
    document.documentElement.setAttribute(ATTRIBUTE, "");
  }

  function changed(changes, area) {
    if (area !== "sync" || !(KEY in changes)) return;
    revision += 1;
    try {
      if (!chrome.runtime?.id) { remove(); return; }
      apply(changes[KEY].newValue === true);
    } catch { remove(); }
  }

  try {
    chrome.storage.onChanged.addListener(changed);
    const initialRevision = revision;
    chrome.storage.sync.get({ [KEY]: false }, (stored) => {
      try {
        if (!chrome.runtime?.id || chrome.runtime.lastError || revision !== initialRevision) return;
        apply(stored[KEY] === true);
      } catch { remove(); }
    });
  } catch { remove(); }
})();
