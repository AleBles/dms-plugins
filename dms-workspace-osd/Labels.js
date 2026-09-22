// Pure string helpers for the Workspace OSD card. No QML state: everything comes in through `opts`,
// including the translated templates, so this file never needs I18n.
.pragma library

// Label for a workspace number and its (optional) name.
// opts: { showName, labelStyle: prefixed|compact|nameOnly, prefixed: "Workspace %1: %2", plain: "Workspace %1" }
function labelFor(number, name, opts) {
    const hasNumber = typeof number === "number" && number >= 0;
    const num = hasNumber ? String(number) : "";
    let n = (name || "").trim();
    if (n === num) n = "";
    // DMS's Hyprland rename dialog stores "<id> <name>"; strip the duplicated id.
    if (hasNumber) {
        const m = n.match(new RegExp("^" + num + "\\s+(.+)$"));
        if (m) n = m[1];
    }
    if (!opts.showName && hasNumber) n = "";
    if (!hasNumber) return n;                       // named-only workspace (sway): the name is all there is
    switch (opts.labelStyle) {
    case "nameOnly":
        return n !== "" ? n : num;
    case "compact":
        return n !== "" ? num + "  ·  " + n : num;
    default:
        return n !== "" ? opts.prefixed.arg(num).arg(n) : opts.plain.arg(num);
    }
}

// entries: [{ name, title }] per window -> lines for the card.
// opts: { appLineStyle: title|name, maxApps, appLineMaxChars, more: "+%1 more" }
function summarize(entries, opts) {
    const lines = [];
    if (opts.appLineStyle === "name") {
        const counts = {};
        const order = [];
        for (const e of entries) {
            if (!e.name) continue;
            if (counts[e.name] === undefined) { counts[e.name] = 0; order.push(e.name); }
            counts[e.name]++;
        }
        for (const n of order) lines.push(counts[n] > 1 ? n + " ×" + counts[n] : n);
    } else {
        for (const e of entries) {
            const title = (e.title || "").trim();
            if (title === "") { if (e.name) lines.push(e.name); continue; }
            // Titles like "Inbox - Google Chrome" already carry the app name; otherwise prefix it.
            const hasName = e.name && title.toLowerCase().includes(e.name.toLowerCase());
            lines.push(hasName || !e.name ? title : e.name + "  ·  " + title);
        }
    }
    const shown = lines.slice(0, opts.maxApps).map(l => truncate(l, opts.appLineMaxChars));
    if (lines.length > opts.maxApps) shown.push(opts.more.arg(lines.length - opts.maxApps));
    return shown;
}

function truncate(line, max) {
    if (max <= 0 || line.length <= max) return line;
    return line.slice(0, Math.max(1, max - 1)).replace(/\s+$/, "") + "…";
}
