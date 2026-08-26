// Nerd Font Material Design glyphs referenced by codepoint so they survive any
// editor/tooling that strips private-use characters.
var ICONS = {
  github: 0xF02A4, star: 0xF04CE, fork: 0xF062D, pull: 0xF0632, merge: 0xF062F, branch: 0xF062C,
  commit: 0xF0718, repo: 0xF00BA, issue: 0xF001A, issueClosed: 0xF05E1, tag: 0xF04FA, shield: 0xF0498,
  discussion: 0xF028C, folder: 0xF024B, folderOpen: 0xF0770, editor: 0xF018D, code: 0xF0169,
  draft: 0xF03EB, clock: 0xF0150, lock: 0xF033E, bell: 0xF009A, play: 0xF040A, check: 0xF012C
}
function icon(name) { var cp = ICONS[name]; return cp ? String.fromCodePoint(cp) : "" }
function formatNumber(value) {
  var n = Number(value || 0)
  if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M"
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, "") + "k"
  return String(n)
}
function relativeTime(value) {
  if (!value) return ""
  var seconds = Math.max(0, Math.floor((Date.now() - Date.parse(value)) / 1000))
  if (seconds < 60) return "just now"
  if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
  if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
  if (seconds < 2592000) return Math.floor(seconds / 86400) + "d ago"
  if (seconds < 31536000) return Math.floor(seconds / 2592000) + "mo ago"
  return Math.floor(seconds / 31536000) + "y ago"
}
function notificationType(item) {
  return item && item.subject ? String(item.subject.type || "") : ""
}
function notificationIcon(item) {
  var type = notificationType(item)
  var info = item ? item._stateInfo : null
  if (type === "Issue" || type === "IssueComment") return icon(info && info.state === "CLOSED" ? "issueClosed" : "issue")
  if (type.indexOf("PullRequest") === 0) return icon(info && info.state === "MERGED" ? "merge" : "pull")
  if (type === "Commit") return icon("commit")
  if (type === "Release") return icon("tag")
  if (type === "Discussion") return "󰍩"
  if (type === "SecurityAlert") return "󰒃"
  if (type === "CheckSuite") return "󰐊"
  return "󰂚"
}
// Returns a palette role: "accent" | "success" | "warning" | "urgent" | "foreground"
function notificationTone(item) {
  var type = notificationType(item)
  var info = item ? item._stateInfo : null
  if (type === "SecurityAlert") return "urgent"
  if (type === "Release") return "warning"
  if (type.indexOf("PullRequest") === 0) return info && info.state === "MERGED" ? "foreground" : "accent"
  if (type === "Issue" || type === "IssueComment") return info && info.state === "CLOSED" ? "foreground" : "success"
  if (type === "CheckSuite") return "warning"
  return "foreground"
}
function notificationState(item) {
  var info = item ? item._stateInfo : null
  if (!info) return ""
  if (info.isDraft) return "Draft"
  var s = String(info.state || "").toLowerCase()
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : ""
}
function reasonLabel(reason) {
  var map = {
    assign: "Assigned", author: "Author", comment: "Comment", ci_activity: "CI activity",
    invitation: "Invitation", manual: "Subscribed", mention: "Mentioned", review_requested: "Review requested",
    security_alert: "Security", state_change: "State change", subscribed: "Watching", team_mention: "Team mention",
    approval_requested: "Approval requested", member_feature_requested: "Feature request"
  }
  return map[String(reason || "")] || String(reason || "").replace(/_/g, " ")
}
function workflowStatus(run) {
  if (run.status === "in_progress") return "Running"
  if (run.status === "queued" || run.status === "waiting" || run.status === "pending") return "Queued"
  if (run.conclusion === "success") return "Success"
  if (run.conclusion === "failure") return "Failed"
  if (run.conclusion === "cancelled") return "Cancelled"
  if (run.conclusion === "skipped") return "Skipped"
  if (run.conclusion === "timed_out") return "Timed out"
  return run.conclusion || run.status || "Completed"
}
// Returns a palette role for a workflow run.
function workflowTone(run) {
  if (run.status !== "completed") return "warning"
  if (run.conclusion === "success") return "success"
  if (run.conclusion === "failure" || run.conclusion === "timed_out") return "urgent"
  return "dim"
}
function workflowIcon(run) {
  if (run.status !== "completed") return "󰦖"
  if (run.conclusion === "success") return "󰄬"
  if (run.conclusion === "failure" || run.conclusion === "timed_out") return "󰅖"
  if (run.conclusion === "cancelled") return "󰜺"
  return "󰒭"
}
function workflowDuration(run) {
  if (!run || !run.run_started_at) return ""
  var end = run.status === "completed" && run.updated_at ? Date.parse(run.updated_at) : Date.now()
  var seconds = Math.max(0, Math.floor((end - Date.parse(run.run_started_at)) / 1000))
  var minutes = Math.floor(seconds / 60)
  if (minutes >= 60) return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m"
  return (minutes > 0 ? minutes + "m " : "") + (seconds % 60) + "s"
}
function localPath(jsonText, fullName) {
  try { return JSON.parse(jsonText || "{}")[fullName] || "" } catch (e) { return "" }
}
function expandHome(path, home) {
  var p = String(path || "").trim()
  if (p === "~") return home
  if (p.indexOf("~/") === 0) return home + p.slice(1)
  return p
}
var LANGUAGE_COLORS = {
  "JavaScript": "#f1e05a", "TypeScript": "#3178c6", "Python": "#3572A5", "Rust": "#dea584", "Go": "#00ADD8",
  "C": "#555555", "C++": "#f34b7d", "C#": "#178600", "Java": "#b07219", "Kotlin": "#A97BFF", "Swift": "#F05138",
  "Ruby": "#701516", "PHP": "#4F5D95", "Shell": "#89e051", "HTML": "#e34c26", "CSS": "#663399", "SCSS": "#c6538c",
  "QML": "#44a51c", "Dart": "#00B4AB", "Lua": "#000080", "Vue": "#41b883", "Svelte": "#ff3e00", "Elixir": "#6e4a7e",
  "Haskell": "#5e5086", "Zig": "#ec915c", "Nix": "#7e7eff", "Dockerfile": "#384d54", "Makefile": "#427819",
  "Scala": "#c22d40", "Objective-C": "#438eff", "Perl": "#0298c3", "R": "#198CE7", "Jupyter Notebook": "#DA5B0B",
  "Vim Script": "#199f4b", "Emacs Lisp": "#c065db", "Clojure": "#db5855", "OCaml": "#ef7a08", "Erlang": "#B83998",
  "Julia": "#a270ba", "Crystal": "#000100", "Nim": "#ffc200", "Astro": "#ff5a03", "MDX": "#fcb32c", "Markdown": "#083fa1"
}
function languageColor(language, fallback) {
  return LANGUAGE_COLORS[String(language || "")] || fallback
}
function labelTextColor(hex) {
  var h = String(hex || "").replace("#", "")
  if (h.length !== 6) return "#ffffff"
  var r = parseInt(h.substr(0, 2), 16), g = parseInt(h.substr(2, 2), 16), b = parseInt(h.substr(4, 2), 16)
  return (0.299 * r + 0.587 * g + 0.114 * b) > 150 ? "#111111" : "#ffffff"
}
function initial(name) {
  var s = String(name || "").trim()
  return s ? s.charAt(0).toUpperCase() : "?"
}
