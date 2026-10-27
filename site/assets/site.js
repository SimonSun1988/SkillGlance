"use strict";

// Synthetic evidence for the public preview. No local records are read or requested.
const evidence = [
  {
    "skill": "frontend-design",
    "codex": [
      0,
      8,
      0,
      3
    ],
    "cursor": [
      0,
      4,
      0,
      2
    ],
    "antigravity": [
      0,
      0,
      2,
      0
    ]
  },
  {
    "skill": "code-review",
    "claude-desktop": [
      4,
      2,
      0,
      2
    ],
    "claude-code": [
      3,
      2,
      0,
      2
    ],
    "cursor": [
      0,
      2,
      1,
      1
    ]
  },
  {
    "skill": "systematic-debugging",
    "codex": [
      0,
      5,
      0,
      2
    ],
    "claude-desktop": [
      2,
      3,
      0,
      1
    ],
    "gemini": [
      1,
      3,
      0,
      2
    ],
    "antigravity": [
      0,
      0,
      1,
      0
    ]
  },
  {
    "skill": "verification-before-completion",
    "codex": [
      0,
      6,
      0,
      2
    ],
    "claude-code": [
      2,
      3,
      1,
      2
    ],
    "cursor": [
      0,
      1,
      0,
      1
    ]
  },
  {
    "skill": "brainstorming",
    "claude-desktop": [
      6,
      4,
      0,
      2
    ],
    "gemini": [
      2,
      2,
      0,
      1
    ]
  },
  {
    "skill": "using-superpowers",
    "codex": [
      0,
      5,
      0,
      3
    ],
    "claude-code": [
      1,
      3,
      0,
      2
    ],
    "gemini": [
      0,
      2,
      1,
      1
    ]
  }
];

// Counts are [calls, confirmed reads, reads with unknown result, confirmed active chats].
// Each provider's example chats are distinct. Unknown requests do not create confirmed chats.
const providers = ["codex", "claude-desktop", "claude-code", "gemini", "cursor", "antigravity"];
const preview = document.querySelector("#usage-preview");

if (preview) {
  const filter = preview.querySelector("#tool-filter");
  const rows = [...preview.querySelectorAll("[data-skill]")];
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  function showTool(tool) {
    if (tool !== "all" && !providers.includes(tool)) return;
    const selectedProviders = tool === "all" ? providers : [tool];
    let calls = 0;
    let reads = 0;
    let unknown = 0;
    evidence.forEach(item => {
      const counts = selectedProviders.reduce((sum, key) => sum.map((count, index) => count + (item[key]?.[index] ?? 0)), [0, 0, 0, 0]);
      const row = rows.find(row => row.dataset.skill === item.skill);
      calls += counts[0];
      reads += counts[1];
      unknown += counts[2];
      row.querySelector("[data-calls]").textContent = String(counts[0]);
      row.querySelector("[data-reads]").textContent = String(counts[1]);
      row.querySelector("[data-unknown]").textContent = String(counts[2]);
      row.querySelector("[data-chats]").textContent = String(counts[3]);
      row.hidden = counts[0] === 0 && counts[1] === 0 && counts[2] === 0;
    });
    preview.querySelector("[data-total-calls]").textContent = String(calls);
    preview.querySelector("[data-total-reads]").textContent = String(reads);
    preview.querySelector("[data-total-unknown]").textContent = String(unknown);
    const note = tool === "antigravity" ? preview.dataset.antigravityNote : preview.dataset.defaultNote;
    preview.querySelector("[data-evidence-note]").textContent = note;
    const announcement = preview.querySelector("[data-announcement]");
    announcement.textContent = `${filter.selectedOptions[0].textContent}: ${calls} ${preview.dataset.callsLabel}, ${reads} ${preview.dataset.readsLabel}, ${unknown} ${preview.dataset.unknownLabel}. ${note}`;
    if (!reducedMotion.matches && typeof preview.animate === "function") {
      preview.querySelector("tbody").animate([{ opacity: .5 }, { opacity: 1 }], { duration: 180 });
    }
  }

  filter.value = "all";
  filter.addEventListener("change", () => showTool(filter.value));
  document.documentElement.classList.add("enhanced");
}

// Preserve the reading position across the three real, independently readable HTML pages.
document.querySelectorAll(".languages a").forEach(link => {
  link.addEventListener("click", () => {
    if (location.hash && /^#[a-z-]+$/.test(location.hash)) {
      link.hash = location.hash;
    }
  });
});
