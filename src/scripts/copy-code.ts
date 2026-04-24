// Copy-to-clipboard for code migration panels.
// Reads `data-copy` → panel id (`code-py` | `code-js` | `code-curl`),
// copies the panel's textContent, flips label to "Copied ✓" for 2s.
const COPIED_MS = 2000;

document.querySelectorAll<HTMLButtonElement>("button.copy[data-copy]").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const key = btn.getAttribute("data-copy");
    const target = key ? document.getElementById(`code-${key}`) : null;
    if (!target) return;
    try {
      await navigator.clipboard.writeText(target.innerText.trim());
    } catch {
      return;
    }
    const orig = btn.textContent;
    btn.textContent = "Copied ✓";
    btn.classList.add("copied");
    window.setTimeout(() => {
      btn.textContent = orig;
      btn.classList.remove("copied");
    }, COPIED_MS);
  });
});
