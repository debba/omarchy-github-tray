import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "community.github-tray"
  ipcTarget: "community.github-tray"
  manageIpc: false

  // ------------------------------------------------------------ palette
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.2)
  readonly property color success: "#3fb950"
  readonly property color warning: "#d29922"
  readonly property color surface: Util.alpha(foreground, 0.045)
  readonly property color surfaceStrong: Util.alpha(foreground, 0.09)
  readonly property color hairline: Util.alpha(foreground, 0.14)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real cardRadius: Math.max(Style.cornerRadius, 0)

  function toneColor(tone) {
    if (tone === "accent") return accent
    if (tone === "success") return success
    if (tone === "warning") return warning
    if (tone === "urgent") return urgent
    if (tone === "dim") return dim
    return foreground
  }

  // ------------------------------------------------------------ settings
  readonly property string helperPath: String(Qt.resolvedUrl("scripts/github-tray")).replace(/^file:\/\//, "")
  readonly property string username: String(setting("githubUsername", ""))
  readonly property string token: String(setting("githubToken", ""))
  readonly property string enterprise: String(setting("githubEnterpriseUrl", ""))
  readonly property bool showNotifications: setting("showNotifications", true) !== false
  readonly property int notificationInterval: Math.max(30, Number(setting("notificationInterval", 60)) || 60)
  readonly property string localProjects: String(setting("localProjects", "{}"))
  readonly property string panelBox: String(setting("panelBox", "right"))
  readonly property string fontSize: String(setting("fontSize", "small"))
  readonly property real fontScale: fontSize === "large" ? 1.2 : (fontSize === "medium" ? 1.1 : 1.0)
  readonly property real cardPadding: Style.space(10)
  readonly property real contentGap: Style.space(8)
  readonly property bool configured: username.trim() !== "" && token.trim() !== ""
  readonly property int unreadCount: notifications.length
  readonly property int pageSize: 8
  property string appliedPanelBox: ""

  // ------------------------------------------------------------ state
  property var repos: []
  property var notifications: []
  property var user: ({})
  property string webBase: enterprise !== "" ? enterprise.replace(/\/$/, "") : "https://github.com"
  property bool loading: false
  property bool loadedOnce: false
  property string errorMessage: ""
  property string view: "main"
  property string tab: "inbox"
  property var selectedRepo: null
  property var details: []
  property int notificationPage: 0
  property string pendingAction: ""
  property var pendingNotification: null
  property var mappingEntries: []
  property bool mappingEditorOpen: false
  property string mappingError: ""
  property bool tokenVisible: false
  property string toast: ""

  readonly property string effectiveTab: showNotifications ? tab : "repos"
  readonly property int totalStars: repos.reduce(function(s, r) { return s + (r.stargazers_count || 0) }, 0)

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  // ------------------------------------------------------------ helpers
  function boolArg(value) { return value ? "1" : "0" }
  function scaledFont(value) { return Math.round(value * fontScale) }
  function baseArgs(command) { return [helperPath, command, "--token", token, "--enterprise", enterprise] }
  function showToast(message) { toast = message; toastTimer.restart() }
  function refresh(manual) {
    if (loading || !configured) {
      if (!configured) errorMessage = ""
      return
    }
    loading = true; errorMessage = ""
    var args = baseArgs("menu")
    args.push("--username", username, "--max-repos", String(setting("maxRepos", 10)), "--sort-by", String(setting("sortBy", "updated")), "--sort-order", String(setting("sortOrder", "desc")))
    args.push("--show-notifications", boolArg(showNotifications), "--desktop", boolArg(setting("desktopNotifications", true)))
    args.push("--review", boolArg(setting("notifyReviewRequests", true)), "--mentions", boolArg(setting("notifyMentions", true)), "--assignments", boolArg(setting("notifyAssignments", true)), "--pr-comments", boolArg(setting("notifyPrComments", true)), "--issue-comments", boolArg(setting("notifyIssueComments", true)))
    args.push("--local-projects", localProjects, "--workflow-started", boolArg(setting("notifyWorkflowStarted", true)), "--workflow-success", boolArg(setting("notifyWorkflowSuccess", true)), "--workflow-failure", boolArg(setting("notifyWorkflowFailure", true)), "--workflow-cancelled", boolArg(setting("notifyWorkflowCancelled", true)))
    menuProcess.command = args; menuProcess.running = true
  }
  function parse(raw) { try { return JSON.parse(String(raw || "{}")) } catch (e) { return {ok:false,error:"The GitHub backend returned invalid data"} } }
  function openUrl(url) { if (url) Quickshell.execDetached(["xdg-open", String(url)]) }
  function localPathFor(repo) { return repo ? Model.expandHome(Model.localPath(localProjects, repo.full_name), Quickshell.env("HOME")) : "" }
  function openRepo(repo) {
    var path = localPathFor(repo)
    if (path !== "") Quickshell.execDetached([String(setting("localEditor", "code")), path])
    else openUrl(repo.html_url)
    close()
  }
  function loadDetails(repo, kind) {
    if (detailProcess.running) return
    selectedRepo = repo; view = "loading"; pendingAction = kind
    detailProcess.command = baseArgs("issues").concat(["--repo", repo.full_name]); detailProcess.running = true
  }
  function loadWorkflows(repo) {
    if (detailProcess.running) return
    selectedRepo = repo; view = "loading"; pendingAction = "workflows"
    detailProcess.command = baseArgs("workflows").concat(["--repo", repo.full_name, "--limit", String(setting("workflowRunsMaxDisplay", 10))]); detailProcess.running = true
  }
  function markRead(item, openAfter) {
    if (actionProcess.running) return
    pendingNotification = item; pendingAction = openAfter ? "mark-open" : "mark"
    actionProcess.command = baseArgs("mark-read").concat(["--id", String(item.id)]); actionProcess.running = true
  }
  function rerun(run) {
    if (actionProcess.running) return
    pendingAction = "rerun"
    actionProcess.command = baseArgs("rerun").concat(["--repo", run.repository_full_name, "--id", String(run.id)]); actionProcess.running = true
  }
  function notificationUrl(item) {
    var u = item.subject && item.subject.url ? item.subject.url : item.repository.html_url
    var api = enterprise !== "" ? enterprise.replace(/\/$/, "") + "/api/v3/repos/" : "https://api.github.com/repos/"
    u = u.replace(api, webBase + "/")
    if (item.subject && String(item.subject.type).indexOf("PullRequest") === 0) u = u.replace("/pulls/", "/pull/").replace("/issues/", "/pull/")
    return u
  }
  function detailTitle() {
    if (view === "issues") return "Issues"
    if (view === "pulls") return "Pull Requests"
    if (view === "workflows") return "Workflow Runs"
    if (pendingAction === "issues") return "Issues"
    if (pendingAction === "pulls") return "Pull Requests"
    if (pendingAction === "workflows") return "Workflow Runs"
    return ""
  }
  function detailBrowserUrl() {
    if (!selectedRepo) return webBase
    return selectedRepo.html_url + (view === "issues" ? "/issues" : view === "pulls" ? "/pulls" : "/actions")
  }

  // ------------------------------------------------------------ mappings
  function parseMappings(raw) {
    try {
      var object = JSON.parse(raw || "{}")
      return Object.keys(object).sort().map(function(repo) { return {repo: repo, path: String(object[repo])} })
    } catch (error) { return [] }
  }
  function mappingsJson() {
    var object = {}
    for (var index = 0; index < mappingEntries.length; index++)
      object[mappingEntries[index].repo] = mappingEntries[index].path
    return JSON.stringify(object)
  }
  function openMappingEditor(entry) {
    mappingRepoField.text = entry ? entry.repo : ""
    mappingPathField.text = entry ? entry.path : ""
    mappingError = ""; mappingEditorOpen = true
    Qt.callLater(function() { (entry ? mappingPathField : mappingRepoField).forceActiveFocus() })
  }
  function addMapping() {
    var repo = mappingRepoField.text.trim().replace(/^https?:\/\/[^\/]+\//, "").replace(/\.git$/, "").replace(/\/$/, "")
    var path = mappingPathField.text.trim()
    if (repo === "" || path === "") { mappingError = "Repository and local path are required"; return }
    if (!/^[^\/\s]+\/[^\/\s]+$/.test(repo)) { mappingError = "Use the owner/repository format"; return }
    if (path.charAt(0) !== "/" && path.indexOf("~") !== 0) { mappingError = "Enter an absolute path (starting with / or ~)"; return }
    var next = mappingEntries.filter(function(item) { return item.repo !== repo })
    next.push({repo: repo, path: path}); next.sort(function(a,b) { return a.repo.localeCompare(b.repo) })
    mappingEntries = next; mappingEditorOpen = false; mappingError = ""
    mappingRepoField.text = ""; mappingPathField.text = ""
  }
  function removeMapping(repo) { mappingEntries = mappingEntries.filter(function(item) { return item.repo !== repo }) }

  // ------------------------------------------------------------ settings form
  function loadSettingsForm() {
    usernameField.text = username; tokenField.text = token; enterpriseField.text = enterprise; tokenVisible = false
    panelBoxField.value = panelBox; maxReposField.value = Number(setting("maxRepos", 10))
    fontSizeField.value = fontSize; sortByField.value = String(setting("sortBy", "updated"))
    sortOrderField.value = String(setting("sortOrder", "desc")); editorField.text = String(setting("localEditor", "code"))
    mappingEntries = parseMappings(localProjects); mappingEditorOpen = false; mappingError = ""
    showNotificationsField.checked = setting("showNotifications", true)
    desktopNotificationsField.checked = setting("desktopNotifications", true)
    notificationIntervalField.value = Number(setting("notificationInterval", 60))
    reviewRequestsField.checked = setting("notifyReviewRequests", true); mentionsField.checked = setting("notifyMentions", true)
    assignmentsField.checked = setting("notifyAssignments", true); prCommentsField.checked = setting("notifyPrComments", true)
    issueCommentsField.checked = setting("notifyIssueComments", true); workflowMaxField.value = Number(setting("workflowRunsMaxDisplay", 10))
    workflowStartedField.checked = setting("notifyWorkflowStarted", true); workflowSuccessField.checked = setting("notifyWorkflowSuccess", true)
    workflowFailureField.checked = setting("notifyWorkflowFailure", true); workflowCancelledField.checked = setting("notifyWorkflowCancelled", true)
    debugModeField.checked = setting("debugMode", false)
  }
  function saveSettings() {
    var next = Object.assign({}, settings, {
      githubUsername: usernameField.text.trim(), githubToken: tokenField.text.trim(),
      githubEnterpriseUrl: enterpriseField.text.trim().replace(/\/$/, ""), panelBox: panelBoxField.value,
      maxRepos: maxReposField.value, sortBy: sortByField.value, sortOrder: sortOrderField.value,
      fontSize: fontSizeField.value, localEditor: editorField.text.trim() || "code",
      localProjects: mappingsJson(),
      showNotifications: showNotificationsField.checked,
      desktopNotifications: desktopNotificationsField.checked,
      notificationInterval: notificationIntervalField.value,
      notifyReviewRequests: reviewRequestsField.checked,
      notifyMentions: mentionsField.checked,
      notifyAssignments: assignmentsField.checked,
      notifyPrComments: prCommentsField.checked,
      notifyIssueComments: issueCommentsField.checked,
      workflowRunsMaxDisplay: workflowMaxField.value,
      notifyWorkflowStarted: workflowStartedField.checked,
      notifyWorkflowSuccess: workflowSuccessField.checked,
      notifyWorkflowFailure: workflowFailureField.checked,
      notifyWorkflowCancelled: workflowCancelledField.checked,
      debugMode: debugModeField.checked
    })
    settings = next
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, next)
    view = "main"; showToast("Settings saved")
    Qt.callLater(function() { root.refresh(true) })
  }

  // ------------------------------------------------------------ lifecycle
  Component.onCompleted: appliedPanelBox = panelBox
  onPanelBoxChanged: {
    if (appliedPanelBox !== "" && appliedPanelBox !== panelBox) {
      appliedPanelBox = panelBox
      Quickshell.execDetached(["omarchy", "bar", "move", moduleName, "--section", panelBox])
    }
  }
  onOpenedChanged: if (opened) {
    view = "main"
    Qt.callLater(function() { panelScroll.contentY = 0 })
    if (repos.length === 0) refresh(false)
  }
  onViewChanged: {
    viewFade.restart()
    Qt.callLater(function() {
      panelScroll.contentY = 0
      if (view === "settings") loadSettingsForm()
    })
  }
  onEffectiveTabChanged: { viewFade.restart(); Qt.callLater(function() { panelScroll.contentY = 0 }) }
  onSettingsChanged: refreshTimer.restart()
  onUnreadCountChanged: badgePop.restart()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function settings(): void { root.open(); Qt.callLater(function() { root.view = "settings" }) }
    function refresh(): string { root.refresh(true); return "ok" }
  }

  // ------------------------------------------------------------ processes
  Process {
    id: menuProcess
    stdout: StdioCollector { id: menuOut; waitForEnd: true }
    stderr: StdioCollector { id: menuErr; waitForEnd: true }
    onExited: function(code) {
      root.loading = false
      var result = root.parse(menuOut.text)
      if (code === 0 && result.ok) {
        root.repos = result.repos || []; root.notifications = result.notifications || []
        root.user = result.user || {}; root.webBase = result.web || root.webBase; root.errorMessage = ""
        root.loadedOnce = true
        if (root.notificationPage * root.pageSize >= root.notifications.length) root.notificationPage = 0
      } else root.errorMessage = result.error || String(menuErr.text || "Error loading repositories").trim()
    }
  }
  Process {
    id: detailProcess
    stdout: StdioCollector { id: detailOut; waitForEnd: true }
    stderr: StdioCollector { id: detailErr; waitForEnd: true }
    onExited: function(code) {
      var result = root.parse(detailOut.text)
      if (code === 0 && result.ok) {
        root.details = root.pendingAction === "issues" ? result.issues : (root.pendingAction === "pulls" ? result.pulls : result.runs)
        root.view = root.pendingAction
      } else { root.errorMessage = result.error || String(detailErr.text).trim(); root.view = "main" }
      root.pendingAction = ""
    }
  }
  Process {
    id: actionProcess
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        if (root.pendingAction.indexOf("mark") === 0 && root.pendingNotification) {
          if (root.pendingAction === "mark-open") { root.openUrl(root.notificationUrl(root.pendingNotification)); root.close() }
          else root.showToast("Marked as read")
          var id = String(root.pendingNotification.id); root.notifications = root.notifications.filter(function(n) { return String(n.id) !== id })
          if (root.notificationPage * root.pageSize >= root.notifications.length) root.notificationPage = Math.max(0, root.notificationPage - 1)
        } else if (root.pendingAction === "rerun") { root.showToast("Re-run requested"); root.loadWorkflows(root.selectedRepo) }
      } else root.showToast(root.parse(actionOut.text).error || String(actionErr.text).trim() || "Action failed")
      root.pendingAction = ""; root.pendingNotification = null
    }
  }
  Timer { id: repoTimer; interval: 300000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.refresh(false) }
  Timer { id: refreshTimer; interval: root.notificationInterval * 1000; repeat: true; running: root.showNotifications; onTriggered: root.refresh(false) }
  Timer { id: toastTimer; interval: 2200; onTriggered: root.toast = "" }

  // ------------------------------------------------------------ bar button
  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: Model.icon("github")
    active: root.unreadCount > 0
    onPressed: function(buttonCode) { if (buttonCode === Qt.MiddleButton) root.refresh(true); else root.toggle() }

    Rectangle {
      id: badge
      visible: root.unreadCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -Style.space(2)
      anchors.topMargin: -Style.space(1)
      width: Math.max(Style.space(13), badgeLabel.implicitWidth + Style.space(6))
      height: Style.space(13)
      radius: height / 2
      color: root.urgent
      border.width: 1
      border.color: Util.alpha(Color.bar.background, 0.9)
      transformOrigin: Item.Center
      SequentialAnimation {
        id: badgePop
        NumberAnimation { target: badge; property: "scale"; to: 1.3; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: badge; property: "scale"; to: 1.0; duration: 180; easing.type: Easing.OutBack }
      }
      Text {
        id: badgeLabel
        anchors.centerIn: parent
        text: root.unreadCount > 99 ? "99+" : String(root.unreadCount)
        color: "white"
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.caption * 0.9)
        font.bold: true
      }
    }
  }

  // ------------------------------------------------------------ popup
  KeyboardPanel {
    id: popup
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.view === "settings"
      onCloseRequested: root.view === "main" ? root.close() : root.view = "main"
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh(true)
        else if (text === "s" || text === "S") root.view = "settings"
        else if (text === "1" && root.view === "main" && root.showNotifications) root.tab = "inbox"
        else if (text === "2" && root.view === "main") root.tab = "repos"
        else if (text === "o" || text === "O") root.openUrl(root.view === "main" ? root.webBase : root.detailBrowserUrl())
      }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        boundsMovement: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        pixelAligned: true
        synchronousDrag: true
        maximumFlickVelocity: 5000
        flickDeceleration: 5000

        function scrollBy(delta) {
          var maximum = Math.max(0, contentHeight - height)
          contentY = Math.max(0, Math.min(maximum, contentY - delta))
        }

        WheelHandler {
          onWheel: function(event) {
            var delta = event.pixelDelta.y
            if (delta === 0) delta = event.angleDelta.y / 120 * Style.space(48)
            if (delta === 0) return
            panelScroll.scrollBy(delta)
            event.accepted = true
          }
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          // Leave room for the overlay scrollbar so trailing text isn't covered.
          width: parent.width - (panelScroll.contentHeight > panelScroll.height ? Style.space(10) : 0)
          spacing: root.contentGap

          SequentialAnimation {
            id: viewFade
            PropertyAction { target: contentColumn; property: "opacity"; value: 0 }
            NumberAnimation { target: contentColumn; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
          }

          // ---------------------------------------------------- main: hero
          UserHero { visible: root.view === "main" && root.configured; width: parent.width }

          // ---------------------------------------------------- main: onboarding
          Column {
            visible: root.view === "main" && !root.configured
            width: parent.width
            spacing: Style.space(14)

            Item { width: 1; height: Style.space(6) }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Model.icon("github")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.scaledFont(Style.font.displayLarge * 1.6)
            }
            Text {
              width: parent.width
              text: "GitHub Tray"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.scaledFont(Style.font.heading)
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }
            Text {
              width: parent.width
              text: "Repositories, notifications, issues, pull requests and Actions — right from the bar."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.scaledFont(Style.font.body)
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)
              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                iconText: "󰒓"
                text: "Connect GitHub"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                horizontalPadding: Style.space(18)
                onClicked: root.view = "settings"
              }
              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Create a personal access token  󰏌"
                foreground: root.accent
                fontFamily: root.fontFamily
                fontSize: root.scaledFont(Style.font.bodySmall)
                onClicked: root.openUrl(root.webBase + "/settings/tokens")
              }
            }
            InfoNote { width: parent.width; iconText: "󰋽"; text: "Use a classic token with the repo scope (or public_repo for public repositories only)." }
            Item { width: 1; height: Style.space(4) }
          }

          // ---------------------------------------------------- main: error
          BorderSurface {
            visible: root.view === "main" && root.configured && root.errorMessage !== ""
            width: parent.width
            implicitHeight: errorColumn.implicitHeight + root.cardPadding * 2
            radius: root.cardRadius
            color: Util.alpha(root.urgent, 0.08)
            borderSpec: Border.flat(Util.alpha(root.urgent, 0.45), 1)
            Column {
              id: errorColumn
              anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              anchors.margins: root.cardPadding
              spacing: Style.space(6)
              Row {
                spacing: Style.space(8)
                Text { text: "󰀦"; color: root.urgent; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.iconLarge) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Could not reach GitHub"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.subtitle); font.bold: true }
              }
              Text { width: parent.width; text: root.errorMessage; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.bodySmall); wrapMode: Text.WrapAnywhere }
              Row {
                spacing: Style.space(6)
                Button { iconText: "󰑐"; text: "Retry"; iconSpinning: root.loading; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; onClicked: root.refresh(true) }
                Button { text: "Check credentials"; foreground: root.accent; fontFamily: root.fontFamily; onClicked: root.view = "settings" }
              }
            }
          }

          // ---------------------------------------------------- main: first load skeleton
          Skeleton { visible: root.view === "main" && root.configured && root.loading && !root.loadedOnce && root.errorMessage === ""; width: parent.width; rows: 4 }

          // ---------------------------------------------------- main: tabs + content
          Column {
            visible: root.view === "main" && root.configured && root.errorMessage === "" && (root.loadedOnce || !root.loading)
            width: parent.width
            spacing: root.contentGap

            SegmentedTabs {
              width: parent.width
              visible: root.showNotifications
            }

            // Inbox
            Column {
              visible: root.effectiveTab === "inbox"
              width: parent.width
              spacing: root.contentGap
              RowLayout {
                width: parent.width
                PanelSectionHeader { text: "UNREAD"; foreground: root.foreground; fontFamily: root.fontFamily }
                Item { Layout.fillWidth: true }
                Button { text: "Open inbox  󰏌"; foreground: root.accent; fontFamily: root.fontFamily; fontSize: root.scaledFont(Style.font.caption); horizontalPadding: Style.space(4); verticalPadding: Style.space(2); onClicked: root.openUrl(root.webBase + "/notifications") }
              }
              EmptyState { visible: root.notifications.length === 0; width: parent.width; iconText: "󰂚"; title: "You're all caught up"; subtitle: "No unread notifications" }
              Repeater {
                model: root.notifications.slice(root.notificationPage * root.pageSize, root.notificationPage * root.pageSize + root.pageSize)
                NotificationCard { required property var modelData; item: modelData }
              }
              Pager {
                visible: root.notifications.length > root.pageSize
                width: parent.width
                page: root.notificationPage
                pages: Math.ceil(root.notifications.length / root.pageSize)
                onPrev: root.notificationPage--
                onNext: root.notificationPage++
              }
            }

            // Repositories
            Column {
              visible: root.effectiveTab === "repos"
              width: parent.width
              spacing: root.contentGap
              RowLayout {
                width: parent.width
                PanelSectionHeader { text: "REPOSITORIES"; foreground: root.foreground; fontFamily: root.fontFamily }
                Text { text: root.sortLabel(); color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); Layout.leftMargin: Style.space(4) }
                Item { Layout.fillWidth: true }
                Button { text: "View all  󰏌"; foreground: root.accent; fontFamily: root.fontFamily; fontSize: root.scaledFont(Style.font.caption); horizontalPadding: Style.space(4); verticalPadding: Style.space(2); onClicked: root.openUrl(root.webBase + "/" + root.username + "?tab=repositories") }
              }
              EmptyState { visible: root.repos.length === 0; width: parent.width; iconText: Model.icon("repo"); title: "No repositories"; subtitle: "Nothing matched your filters" }
              Repeater { model: root.repos; RepoCard { required property var modelData; repo: modelData } }
            }
          }

          // ---------------------------------------------------- detail views
          Column {
            visible: root.view === "issues" || root.view === "pulls" || root.view === "workflows" || root.view === "loading"
            width: parent.width
            spacing: root.contentGap
            DetailHeader { title: root.detailTitle(); subtitle: root.selectedRepo ? root.selectedRepo.full_name : "" }
            Skeleton { visible: root.view === "loading"; width: parent.width; rows: 3 }
            EmptyState {
              visible: root.view !== "loading" && root.details.length === 0
              width: parent.width
              iconText: root.view === "workflows" ? Model.icon("play") : (root.view === "pulls" ? Model.icon("pull") : Model.icon("issue"))
              title: root.view === "workflows" ? "No workflow runs" : (root.view === "pulls" ? "No open pull requests" : "No open issues")
              subtitle: ""
            }
            Repeater { model: root.view === "loading" ? [] : root.details; DetailCard { required property var modelData; item: modelData; kind: root.view } }
          }

          // ---------------------------------------------------- settings
          Column {
            visible: root.view === "settings"
            width: parent.width
            spacing: Style.space(8)
            DetailHeader { title: "Settings"; subtitle: "GitHub Tray"; showBrowser: false }

            FormSection { title: "ACCOUNT"; iconText: "󰀄"
              FieldLabel { text: "GitHub username" }
              TextField { id: usernameField; width: parent.width; placeholderText: "octocat"; foreground: root.foreground }
              FieldLabel { text: "Personal access token" }
              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                TextField { id: tokenField; Layout.fillWidth: true; placeholderText: "ghp_…"; password: !root.tokenVisible; foreground: root.foreground }
                PanelActionButton { iconText: root.tokenVisible ? "󰈉" : "󰈈"; tooltipText: root.tokenVisible ? "Hide token" : "Show token"; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; size: Style.spacing.controlHeight; onClicked: root.tokenVisible = !root.tokenVisible }
                PanelActionButton { iconText: "󰏌"; tooltipText: "Create a token on GitHub"; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; size: Style.spacing.controlHeight; onClicked: root.openUrl((enterpriseField.text.trim() || "https://github.com").replace(/\/$/, "") + "/settings/tokens") }
              }
              FieldLabel { text: "GitHub Enterprise Server URL"; hint: "optional" }
              TextField { id: enterpriseField; width: parent.width; placeholderText: "https://github.example.com"; foreground: root.foreground }
            }

            FormSection { title: "APPEARANCE"; iconText: "󰏘"
              Dropdown { id: panelBoxField; width: parent.width; label: "Bar section"; options: [{value:"left",label:"Left"},{value:"center",label:"Center"},{value:"right",label:"Right"}]; foreground: root.foreground; fontFamily: root.fontFamily }
              Dropdown { id: fontSizeField; width: parent.width; label: "Font size"; options: [{value:"small",label:"Small"},{value:"medium",label:"Medium"},{value:"large",label:"Large"}]; foreground: root.foreground; fontFamily: root.fontFamily }
            }

            FormSection { title: "REPOSITORIES"; iconText: Model.icon("repo")
              RowLayout {
                width: parent.width
                spacing: Style.space(8)
                Dropdown { id: sortByField; Layout.fillWidth: true; label: "Sort by"; options: [{value:"updated",label:"Last updated"},{value:"pushed",label:"Last pushed"},{value:"created",label:"Created"},{value:"stars",label:"Stars"},{value:"name",label:"Name"}]; foreground: root.foreground; fontFamily: root.fontFamily }
                Dropdown { id: sortOrderField; Layout.preferredWidth: Style.space(120); label: "Order"; options: [{value:"desc",label:"Descending"},{value:"asc",label:"Ascending"}]; foreground: root.foreground; fontFamily: root.fontFamily }
              }
              NumberField { id: maxReposField; label: "Maximum repositories shown"; from: 1; to: 50; fieldWidth: parent.width; foreground: root.foreground; fontFamily: root.fontFamily; onModified: function(v) { value = v } }
            }

            FormSection { title: "LOCAL PROJECTS"; iconText: Model.icon("folder")
              FieldLabel { text: "Editor command"; hint: "used to open mapped repositories" }
              TextField { id: editorField; width: parent.width; placeholderText: "code"; foreground: root.foreground }
              InfoNote { width: parent.width; iconText: "󰋽"; text: "Map a repository to a local folder to open it in your editor with one click and to watch its workflow runs." }

              Repeater {
                model: root.mappingEntries
                CursorSurface {
                  id: mappingRow
                  required property var modelData
                  width: parent.width
                  implicitHeight: mappingContent.implicitHeight + Style.space(12)
                  foreground: root.foreground
                  bordered: true
                  hasCursor: mappingHover.hovered
                  HoverHandler { id: mappingHover }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openMappingEditor(mappingRow.modelData) }
                  RowLayout {
                    id: mappingContent
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(6)
                    spacing: Style.space(8)
                    Text { text: Model.icon("folder"); color: root.accent; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.icon) }
                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 1
                      Text { Layout.fillWidth: true; text: mappingRow.modelData.repo; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body); font.bold: true; elide: Text.ElideRight }
                      Text { Layout.fillWidth: true; text: mappingRow.modelData.path; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); elide: Text.ElideMiddle }
                    }
                    PanelActionButton { iconText: "󰆴"; tooltipText: "Remove mapping"; foreground: root.dim; hoverColor: root.urgent; fontFamily: root.fontFamily; onClicked: root.removeMapping(mappingRow.modelData.repo) }
                  }
                }
              }

              Button {
                visible: !root.mappingEditorOpen
                width: parent.width
                iconText: "󰐕"
                text: root.mappingEntries.length === 0 ? "Add your first mapping" : "Add mapping"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.openMappingEditor(null)
              }

              BorderSurface {
                visible: root.mappingEditorOpen
                width: parent.width
                implicitHeight: mappingForm.implicitHeight + Style.space(20)
                radius: root.cardRadius
                color: root.surface
                borderSpec: Border.flat(Util.alpha(root.accent, 0.5), 1)
                Column {
                  id: mappingForm
                  anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(10)
                  spacing: Style.space(6)
                  FieldLabel { text: "Repository"; hint: "owner/name or GitHub URL" }
                  TextField { id: mappingRepoField; width: parent.width; placeholderText: "owner/repository"; foreground: root.foreground; onAccepted: mappingPathField.forceActiveFocus() }
                  FieldLabel { text: "Local path"; hint: "absolute, ~ is supported" }
                  TextField { id: mappingPathField; width: parent.width; placeholderText: "~/Projects/repository"; foreground: root.foreground; onAccepted: root.addMapping() }
                  Text { visible: root.mappingError !== ""; width: parent.width; text: "󰀦  " + root.mappingError; color: root.urgent; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); wrapMode: Text.WordWrap }
                  Row {
                    anchors.right: parent.right
                    spacing: Style.space(6)
                    Button { text: "Cancel"; foreground: root.dim; fontFamily: root.fontFamily; onClicked: { root.mappingEditorOpen = false; root.mappingError = "" } }
                    Button { iconText: "󰄬"; text: "Save mapping"; foreground: root.accent; fontFamily: root.fontFamily; bordered: true; onClicked: root.addMapping() }
                  }
                }
              }
            }

            FormSection { title: "NOTIFICATIONS"; iconText: "󰂚"
              CompactToggle { id: showNotificationsField; width: parent.width; label: "Show GitHub notifications"; description: "Inbox tab and unread badge on the bar"; onClicked: checked = !checked }
              CompactToggle { id: desktopNotificationsField; width: parent.width; label: "Desktop notifications"; description: "Alert on new activity, stars, forks and followers"; onClicked: checked = !checked }
              NumberField { id: notificationIntervalField; label: "Refresh interval (seconds)"; from: 30; to: 600; stepSize: 30; fieldWidth: parent.width; foreground: root.foreground; fontFamily: root.fontFamily; onModified: function(v) { value = v } }
              FieldLabel { text: "Include"; hint: "which notifications are shown" }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                ChipToggle { id: reviewRequestsField; iconText: "󰈈"; label: "Review requests" }
                ChipToggle { id: mentionsField; iconText: "󰁥"; label: "Mentions" }
                ChipToggle { id: assignmentsField; iconText: "󰀄"; label: "Assignments" }
                ChipToggle { id: prCommentsField; iconText: Model.icon("pull"); label: "PR comments" }
                ChipToggle { id: issueCommentsField; iconText: Model.icon("issue"); label: "Issue comments" }
              }
            }

            FormSection { title: "GITHUB ACTIONS"; iconText: "󰐊"
              NumberField { id: workflowMaxField; label: "Maximum workflow runs shown"; from: 1; to: 50; fieldWidth: parent.width; foreground: root.foreground; fontFamily: root.fontFamily; onModified: function(v) { value = v } }
              FieldLabel { text: "Notify when a workflow…"; hint: "mapped repositories only" }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                ChipToggle { id: workflowStartedField; iconText: "󰐊"; label: "Starts"; tint: root.foreground }
                ChipToggle { id: workflowSuccessField; iconText: "󰄬"; label: "Succeeds"; tint: root.success }
                ChipToggle { id: workflowFailureField; iconText: "󰅖"; label: "Fails"; tint: root.urgent }
                ChipToggle { id: workflowCancelledField; iconText: "󰜺"; label: "Is cancelled"; tint: root.warning }
              }
            }

            FormSection { title: "ADVANCED"; iconText: "󰒓"
              CompactToggle { id: debugModeField; width: parent.width; label: "Debug mode"; description: "Show a test-notification button in the header"; onClicked: checked = !checked }
            }

            Item { width: 1; height: Style.space(2) }
            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              Text { text: "Esc discards changes"; color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption) }
              Item { Layout.fillWidth: true }
              Button { text: "Cancel"; foreground: root.dim; fontFamily: root.fontFamily; onClicked: root.view = "main" }
              Button { iconText: "󰄬"; text: "Save"; foreground: root.accent; fontFamily: root.fontFamily; bordered: true; horizontalPadding: Style.space(16); onClicked: root.saveSettings() }
            }
          }
        }
      }

      // Background-refresh indicator: a slim animated bar hugging the top edge.
      Item {
        id: progressBar
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: -Style.spacing.popupPadding + Style.space(2)
        height: Style.space(2)
        visible: root.loading && root.loadedOnce && root.view === "main"
        clip: true
        Rectangle {
          id: progressSweep
          width: parent.width * 0.35
          height: parent.height
          radius: height / 2
          color: root.accent
          opacity: 0.85
          x: -width
          NumberAnimation on x { from: -progressSweep.width; to: progressBar.width; duration: 1100; loops: Animation.Infinite; running: progressBar.visible; easing.type: Easing.InOutQuad }
        }
      }

      // Toast
      BorderSurface {
        id: toastPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
        implicitWidth: toastRow.implicitWidth + Style.space(24)
        implicitHeight: toastRow.implicitHeight + Style.space(12)
        radius: root.cardRadius > 0 ? height / 2 : 0
        color: Color.popups.background
        borderSpec: Border.flat(Util.alpha(root.accent, 0.6), 1)
        opacity: root.toast !== "" ? 1 : 0
        scale: root.toast !== "" ? 1 : 0.92
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Util.alpha(root.accent, 0.10) }
        Row {
          id: toastRow
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text { text: "󰄬"; color: root.accent; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body) }
          Text { text: root.toast; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.bodySmall) }
        }
      }
    }
  }

  function sortLabel() {
    var by = String(setting("sortBy", "updated"))
    var map = {updated: "by update", pushed: "by push", created: "by creation", stars: "by stars", name: "by name"}
    return "· " + (map[by] || by) + (String(setting("sortOrder", "desc")) === "asc" ? " ↑" : " ↓")
  }

  // ============================================================ components

  component UserHero: Item {
    id: userHero
    implicitHeight: Math.max(avatarFrame.height, heroLabels.implicitHeight, heroActions.implicitHeight)

    Item {
      id: avatarFrame
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(44)
      height: width
      readonly property real frameRadius: root.cardRadius > 0 ? Math.max(root.cardRadius, Style.space(10)) : 0

      Rectangle {
        anchors.fill: parent
        radius: avatarFrame.frameRadius
        color: root.surfaceStrong
        border.width: 1
        border.color: root.hairline
      }
      Text {
        anchors.centerIn: parent
        visible: avatarImage.status !== Image.Ready
        text: Model.initial(root.user.login || root.username)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.scaledFont(Style.font.heading)
        font.bold: true
      }
      Image {
        id: avatarImage
        anchors.fill: parent
        anchors.margins: 1
        source: root.user.avatar_url ? root.user.avatar_url + (String(root.user.avatar_url).indexOf("?") >= 0 ? "&" : "?") + "s=128" : ""
        sourceSize.width: 128
        sourceSize.height: 128
        fillMode: Image.PreserveAspectCrop
        visible: false
        asynchronous: true
      }
      Item {
        id: avatarMask
        anchors.fill: avatarImage
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: Math.max(0, avatarFrame.frameRadius - 1); color: "black" }
      }
      MultiEffect {
        anchors.fill: avatarImage
        source: avatarImage
        visible: avatarImage.status === Image.Ready
        maskEnabled: true
        maskSource: avatarMask
      }
      // Presence dot: pulses while a refresh is in flight.
      Rectangle {
        id: presenceDot
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: -Style.space(2); anchors.bottomMargin: -Style.space(2)
        width: Style.space(11); height: width; radius: width / 2
        color: root.errorMessage !== "" ? root.urgent : root.success
        border.width: 2
        border.color: Color.popups.background
        SequentialAnimation {
          id: presencePulse
          running: root.loading
          loops: Animation.Infinite
          NumberAnimation { target: presenceDot; property: "opacity"; to: 0.25; duration: 500; easing.type: Easing.InOutSine }
          NumberAnimation { target: presenceDot; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
          onRunningChanged: if (!running) presenceDot.opacity = 1
        }
      }
    }

    Column {
      id: heroLabels
      anchors.left: avatarFrame.right
      anchors.leftMargin: Style.space(12)
      anchors.right: heroActions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(5)
      Text {
        width: parent.width
        text: root.user.login || root.username
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.scaledFont(Style.font.title)
        font.bold: true
        elide: Text.ElideRight
      }
      Row {
        spacing: Style.space(5)
        StatChip { iconText: "󰀄"; valueText: Model.formatNumber(root.user.followers); tooltipText: "Followers" }
        StatChip { iconText: Model.icon("repo"); valueText: Model.formatNumber(root.user.public_repos); tooltipText: "Repositories" }
        StatChip { iconText: Model.icon("star"); valueText: Model.formatNumber(root.totalStars); tooltipText: "Stars across listed repositories"; tint: root.warning }
      }
    }

    Row {
      id: heroActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      HeroButton { visible: setting("debugMode", false); glyph: "󰂞"; tooltipText: "Send a test notification"; onClicked: Quickshell.execDetached(["notify-send", "--app-name=GitHub Tray", "GitHub Tray", "Desktop notifications are working"]) }
      HeroButton { glyph: "󰑐"; spinning: root.loading; tooltipText: root.loading ? "Refreshing…" : "Refresh  (r)"; onClicked: root.refresh(true) }
      HeroButton { glyph: "󰒓"; tooltipText: "Settings  (s)"; onClicked: root.view = "settings" }
    }
  }

  // Header icon buttons share one geometry so their glyphs sit on the same
  // baseline regardless of which one is spinning or hovered.
  component HeroButton: Button {
    id: heroButton
    property string glyph: ""
    property bool spinning: false
    foreground: root.foreground
    fontFamily: root.fontFamily
    implicitWidth: Style.space(26)
    implicitHeight: Style.space(26)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    Text {
      id: heroGlyph
      anchors.centerIn: parent
      text: heroButton.glyph
      color: heroButton.foreground
      font.family: root.fontFamily
      font.pixelSize: root.scaledFont(Style.font.icon)
      transformOrigin: Item.Center
      RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: heroButton.spinning }
    }
    // The animation leaves `rotation` wherever it stopped; snap the glyph upright.
    onSpinningChanged: if (!spinning) heroGlyph.rotation = 0
  }

  component StatChip: BorderSurface {
    id: statChip
    property string iconText: ""
    property string valueText: ""
    property string tooltipText: ""
    property color tint: root.dim
    implicitWidth: chipRow.implicitWidth + Style.space(12)
    implicitHeight: chipRow.implicitHeight + Style.space(6)
    radius: root.cardRadius
    color: chipHover.hovered ? root.surfaceStrong : root.surface
    borderSpec: Border.flat(root.hairline, 1)
    Behavior on color { ColorAnimation { duration: 90 } }
    HoverHandler { id: chipHover }
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(4)
      Text { text: statChip.iconText; color: statChip.tint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); anchors.verticalCenter: parent.verticalCenter }
      Text { text: statChip.valueText; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); font.bold: true; font.features: { "tnum": 1 }; anchors.verticalCenter: parent.verticalCenter }
    }
    PanelToolTip { visible: statChip.tooltipText !== "" && chipHover.hovered; text: statChip.tooltipText; fontFamily: root.fontFamily }
  }

  component SegmentedTabs: BorderSurface {
    id: segmented
    implicitHeight: Style.spacing.controlHeight + Style.space(4)
    radius: root.cardRadius
    color: root.surface
    borderSpec: Border.flat(root.hairline, 1)
    readonly property int count: 2
    readonly property real segmentWidth: (width - Style.space(4)) / count
    readonly property int activeIndex: root.effectiveTab === "inbox" ? 0 : 1

    Rectangle {
      id: thumb
      x: Style.space(2) + segmented.activeIndex * segmented.segmentWidth
      y: Style.space(2)
      width: segmented.segmentWidth
      height: parent.height - Style.space(4)
      radius: Math.max(0, root.cardRadius - 1)
      color: Style.selectedFillFor(root.foreground, root.accent)
      border.width: 1
      border.color: Util.alpha(root.foreground, 0.18)
      Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }
    Row {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      TabSegment { width: segmented.segmentWidth; iconText: "󰂚"; label: "Inbox"; count: root.notifications.length; selected: segmented.activeIndex === 0; badgeTint: root.urgent; onClicked: root.tab = "inbox" }
      TabSegment { width: segmented.segmentWidth; iconText: Model.icon("repo"); label: "Repositories"; count: root.repos.length; selected: segmented.activeIndex === 1; onClicked: root.tab = "repos" }
    }
  }

  component TabSegment: Item {
    id: tabSegment
    property string iconText: ""
    property string label: ""
    property int count: 0
    property bool selected: false
    property color badgeTint: root.foreground
    signal clicked()
    height: parent.height
    Row {
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text { text: tabSegment.iconText; color: tabSegment.selected ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.bodySmall); anchors.verticalCenter: parent.verticalCenter; Behavior on color { ColorAnimation { duration: 150 } } }
      Text { text: tabSegment.label; color: tabSegment.selected ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.bodySmall); font.bold: tabSegment.selected; anchors.verticalCenter: parent.verticalCenter; Behavior on color { ColorAnimation { duration: 150 } } }
      Rectangle {
        visible: tabSegment.count > 0
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(16), countLabel.implicitWidth + Style.space(8))
        height: Style.space(15)
        radius: root.cardRadius > 0 ? height / 2 : 0
        color: tabSegment.selected ? Util.alpha(tabSegment.badgeTint, 0.22) : root.surfaceStrong
        Text { id: countLabel; anchors.centerIn: parent; text: tabSegment.count > 99 ? "99+" : String(tabSegment.count); color: tabSegment.selected ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: Math.round(root.scaledFont(Style.font.caption) * 0.92); font.bold: true; font.features: { "tnum": 1 } }
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tabSegment.clicked() }
  }

  component Pager: RowLayout {
    id: pager
    property int page: 0
    property int pages: 1
    signal prev()
    signal next()
    spacing: Style.space(10)
    Item { Layout.fillWidth: true }
    PanelActionButton { iconText: "󰅁"; enabled: pager.page > 0; tooltipText: "Previous page"; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; onClicked: pager.prev() }
    Row {
      spacing: Style.space(4)
      Layout.alignment: Qt.AlignVCenter
      Repeater {
        model: Math.min(pager.pages, 12)
        Rectangle {
          required property int index
          width: index === pager.page ? Style.space(14) : Style.space(5)
          height: Style.space(5)
          radius: height / 2
          anchors.verticalCenter: parent.verticalCenter
          color: index === pager.page ? root.accent : root.hairline
          Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }
    }
    Text { text: (pager.page + 1) + " / " + pager.pages; color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); font.features: { "tnum": 1 } }
    PanelActionButton { iconText: "󰅂"; enabled: pager.page + 1 < pager.pages; tooltipText: "Next page"; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; onClicked: pager.next() }
    Item { Layout.fillWidth: true }
  }

  component EmptyState: Column {
    id: emptyState
    property string iconText: ""
    property string title: ""
    property string subtitle: ""
    spacing: Style.space(4)
    topPadding: Style.space(18)
    bottomPadding: Style.space(18)
    Text { anchors.horizontalCenter: parent.horizontalCenter; text: emptyState.iconText; color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.displayLarge) }
    Text { width: parent.width; text: emptyState.title; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body); font.bold: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
    Text { visible: emptyState.subtitle !== ""; width: parent.width; text: emptyState.subtitle; color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
  }

  component Skeleton: Column {
    id: skeleton
    property int rows: 3
    spacing: root.contentGap
    opacity: 0.55
    SequentialAnimation on opacity {
      running: skeleton.visible
      loops: Animation.Infinite
      NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.7; duration: 650; easing.type: Easing.InOutSine }
    }
    Repeater {
      model: skeleton.rows
      Rectangle {
        required property int index
        width: parent.width
        height: Style.space(62)
        radius: root.cardRadius
        color: root.surface
        border.width: 1
        border.color: root.hairline
        Column {
          anchors.left: parent.left; anchors.top: parent.top; anchors.margins: root.cardPadding
          spacing: Style.space(8)
          Rectangle { width: Style.space(120 + (index % 3) * 30); height: Style.space(10); radius: Style.space(3); color: root.surfaceStrong }
          Rectangle { width: Style.space(220 - (index % 2) * 40); height: Style.space(8); radius: Style.space(3); color: root.surfaceStrong }
        }
      }
    }
  }

  component InfoNote: BorderSurface {
    id: infoNote
    property string iconText: "󰋽"
    property string text: ""
    implicitHeight: noteRow.implicitHeight + Style.space(14)
    radius: root.cardRadius
    color: root.surface
    borderSpec: Border.flat(root.hairline, 1)
    RowLayout {
      id: noteRow
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(8)
      spacing: Style.space(8)
      Text { text: infoNote.iconText; color: root.accent; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body); Layout.alignment: Qt.AlignTop }
      Text { Layout.fillWidth: true; text: infoNote.text; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); wrapMode: Text.WordWrap }
    }
  }

  component FieldLabel: RowLayout {
    id: fieldLabel
    property string text: ""
    property string hint: ""
    width: parent ? parent.width : implicitWidth
    spacing: Style.space(6)
    Text { text: fieldLabel.text; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); font.bold: true }
    Text { visible: fieldLabel.hint !== ""; text: fieldLabel.hint; color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); font.italic: true }
    Item { Layout.fillWidth: true }
  }

  component FormSection: Column {
    id: formSection
    property string title: ""
    property string iconText: ""
    default property alias content: sectionBody.children
    width: parent ? parent.width : implicitWidth
    spacing: Style.space(6)
    topPadding: Style.space(6)
    Row {
      spacing: Style.space(6)
      Text { text: formSection.iconText; color: root.accent; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); anchors.verticalCenter: parent.verticalCenter }
      PanelSectionHeader { text: formSection.title; foreground: root.foreground; fontFamily: root.fontFamily; anchors.verticalCenter: parent.verticalCenter }
    }
    PanelSeparator { width: parent.width; foreground: root.foreground }
    Column { id: sectionBody; width: parent.width; spacing: Style.space(6) }
  }

  component ChipToggle: BorderSurface {
    id: chipToggle
    property string iconText: ""
    property string label: ""
    property bool checked: true
    property color tint: root.accent
    implicitWidth: chipContent.implicitWidth + Style.space(18)
    implicitHeight: chipContent.implicitHeight + Style.space(10)
    radius: root.cardRadius > 0 ? height / 2 : 0
    color: checked ? Util.alpha(chipToggle.tint, chipHover.hovered ? 0.24 : 0.16) : (chipHover.hovered ? root.surfaceStrong : root.surface)
    borderSpec: Border.flat(checked ? Util.alpha(chipToggle.tint, 0.6) : root.hairline, 1)
    Behavior on color { ColorAnimation { duration: 120 } }
    HoverHandler { id: chipHover }
    Row {
      id: chipContent
      anchors.centerIn: parent
      spacing: Style.space(5)
      Text { text: chipToggle.checked ? "󰄬" : chipToggle.iconText; color: chipToggle.checked ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); anchors.verticalCenter: parent.verticalCenter }
      Text { text: chipToggle.label; color: chipToggle.checked ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); font.bold: chipToggle.checked; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chipToggle.checked = !chipToggle.checked }
  }

  component CompactToggle: CursorSurface {
    id: compactToggle
    property string label: ""
    property string description: ""
    property bool checked: false
    signal clicked()
    implicitHeight: toggleContent.implicitHeight + Style.space(16)
    foreground: root.foreground
    bordered: true
    hasCursor: toggleHover.hovered
    HoverHandler { id: toggleHover }
    RowLayout {
      id: toggleContent
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Text { Layout.fillWidth: true; text: compactToggle.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body); elide: Text.ElideRight }
        Text { visible: compactToggle.description !== ""; Layout.fillWidth: true; text: compactToggle.description; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); wrapMode: Text.WordWrap }
      }
      ToggleSwitch { checked: compactToggle.checked; interactive: false; trackHeight: Style.space(16); foreground: root.foreground }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: compactToggle.clicked() }
  }

  component DetailHeader: RowLayout {
    id: detailHeader
    property string title: ""
    property string subtitle: ""
    property bool showBrowser: true
    width: parent ? parent.width : 0
    spacing: Style.space(8)
    PanelActionButton { iconText: "󰅁"; tooltipText: "Back  (Esc)"; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; onClicked: root.view = "main" }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      Text { Layout.fillWidth: true; text: detailHeader.title; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.subtitle); font.bold: true; elide: Text.ElideRight }
      Text { visible: detailHeader.subtitle !== ""; Layout.fillWidth: true; text: detailHeader.subtitle; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); elide: Text.ElideMiddle }
    }
    PanelActionButton { visible: detailHeader.showBrowser; iconText: "󰏌"; tooltipText: "Open on GitHub  (o)"; foreground: root.foreground; fontFamily: root.fontFamily; bordered: true; onClicked: root.openUrl(root.detailBrowserUrl()) }
  }

  component Metric: Item {
    id: metric
    property string iconText: ""
    property string valueText: ""
    property string tooltipText: ""
    property color tint: root.dim
    property bool actionable: false
    signal activated()
    readonly property bool hot: metricHover.hovered && actionable
    implicitWidth: metricRow.implicitWidth + Style.space(8)
    implicitHeight: metricRow.implicitHeight + Style.space(4)
    Rectangle { anchors.fill: parent; radius: root.cardRadius; color: metric.hot ? root.surfaceStrong : "transparent"; Behavior on color { ColorAnimation { duration: 90 } } }
    Row {
      id: metricRow
      anchors.centerIn: parent
      spacing: Style.space(3)
      Text { text: metric.iconText; color: metric.hot ? root.foreground : metric.tint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); anchors.verticalCenter: parent.verticalCenter }
      Text { text: metric.valueText; color: metric.hot ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); font.weight: Font.Medium; font.features: { "tnum": 1 }; anchors.verticalCenter: parent.verticalCenter }
    }
    HoverHandler { id: metricHover }
    MouseArea { anchors.fill: parent; enabled: metric.actionable; cursorShape: Qt.PointingHandCursor; onClicked: metric.activated() }
    PanelToolTip { visible: metric.tooltipText !== "" && metricHover.hovered; text: metric.tooltipText; fontFamily: root.fontFamily }
  }

  component Pill: Rectangle {
    id: pill
    property string text: ""
    property color tint: root.dim
    property bool outlined: true
    visible: text !== ""
    implicitWidth: pillLabel.implicitWidth + Style.space(10)
    implicitHeight: pillLabel.implicitHeight + Style.space(4)
    radius: root.cardRadius > 0 ? height / 2 : 0
    color: Util.alpha(pill.tint, 0.14)
    border.width: outlined ? 1 : 0
    border.color: Util.alpha(pill.tint, 0.5)
    Text { id: pillLabel; anchors.centerIn: parent; text: pill.text; color: pill.tint; font.family: root.fontFamily; font.pixelSize: Math.round(root.scaledFont(Style.font.caption) * 0.95); font.bold: true }
  }

  component NotificationCard: CursorSurface {
    id: notificationCard
    property var item: null
    readonly property color tone: root.toneColor(Model.notificationTone(item))
    readonly property bool busy: root.pendingNotification && item && String(root.pendingNotification.id) === String(item.id)
    width: parent ? parent.width : 0
    implicitHeight: notificationColumn.implicitHeight + root.cardPadding * 2
    foreground: root.foreground
    bordered: true
    hasCursor: cardHover.hovered
    opacity: busy ? 0.5 : 1
    Behavior on opacity { NumberAnimation { duration: 120 } }
    HoverHandler { id: cardHover }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; scrollGestureEnabled: false; onClicked: root.markRead(notificationCard.item, true) }
    Rectangle {
      anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
      anchors.margins: Style.space(6)
      width: Style.space(3)
      radius: width / 2
      color: notificationCard.tone
      opacity: 0.9
    }
    RowLayout {
      id: notificationColumn
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: root.cardPadding + Style.space(8); anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)
      Text { text: Model.notificationIcon(notificationCard.item); color: notificationCard.tone; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.iconLarge); Layout.alignment: Qt.AlignTop; Layout.topMargin: Style.space(1) }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(3)
        Text { Layout.fillWidth: true; text: notificationCard.item.subject.title; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body); font.weight: Font.DemiBold; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text { text: notificationCard.item.repository.full_name; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); elide: Text.ElideMiddle; Layout.maximumWidth: Style.space(170) }
          Pill { text: Model.notificationState(notificationCard.item); tint: notificationCard.tone }
          Text { text: Model.reasonLabel(notificationCard.item.reason); color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); elide: Text.ElideRight; Layout.fillWidth: true }
          Text { text: Model.relativeTime(notificationCard.item.updated_at); color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption) }
        }
      }
      PanelActionButton { iconText: "󰄬"; tooltipText: "Mark as read"; foreground: root.dim; hoverColor: root.success; fontFamily: root.fontFamily; enabled: !notificationCard.busy; Layout.alignment: Qt.AlignVCenter; onClicked: root.markRead(notificationCard.item, false) }
    }
  }

  component RepoCard: CursorSurface {
    id: repoCard
    property var repo: null
    readonly property string path: root.localPathFor(repo)
    readonly property bool isOwn: repo && (!repo.owner || repo.owner.login === root.username)
    width: parent ? parent.width : 0
    implicitHeight: repoColumn.implicitHeight + root.cardPadding * 2
    foreground: root.foreground
    bordered: true
    hasCursor: repoHover.hovered
    HoverHandler { id: repoHover }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; scrollGestureEnabled: false; onClicked: root.openRepo(repoCard.repo) }
    ColumnLayout {
      id: repoColumn
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.margins: root.cardPadding; anchors.rightMargin: Style.space(6)
      spacing: Style.space(4)
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)
        Text { text: repoCard.repo.fork ? Model.icon("fork") : (repoCard.repo.private ? Model.icon("lock") : Model.icon("repo")); color: repoCard.repo.private ? root.warning : root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.bodySmall) }
        Text {
          Layout.fillWidth: true
          textFormat: Text.StyledText
          text: repoCard.isOwn ? repoCard.repo.name : ("<font color=\"" + root.dim + "\">" + repoCard.repo.owner.login + "/</font>" + repoCard.repo.name)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.scaledFont(Style.font.body)
          font.bold: true
          elide: Text.ElideRight
        }
        Row {
          visible: !!repoCard.repo.language
          spacing: Style.space(4)
          Layout.alignment: Qt.AlignVCenter
          Rectangle { width: Style.space(8); height: width; radius: width / 2; color: Model.languageColor(repoCard.repo.language, root.dim); anchors.verticalCenter: parent.verticalCenter; border.width: 1; border.color: Util.alpha("#000000", 0.25) }
          Text { text: repoCard.repo.language || ""; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption); anchors.verticalCenter: parent.verticalCenter }
        }
        Text { text: Model.relativeTime(repoCard.repo.pushed_at || repoCard.repo.updated_at); color: root.faint; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.caption) }
      }
      Text {
        visible: !!repoCard.repo.description
        Layout.fillWidth: true
        text: repoCard.repo.description || ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: root.scaledFont(Style.font.caption)
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Metric { iconText: Model.icon("star"); valueText: Model.formatNumber(repoCard.repo.stargazers_count); tint: root.warning; tooltipText: "Stars" }
        Metric { iconText: Model.icon("fork"); valueText: Model.formatNumber(repoCard.repo.forks_count); tooltipText: "Forks" }
        Metric { iconText: Model.icon("issue"); valueText: Model.formatNumber(repoCard.repo._issuesCount); tint: root.success; actionable: true; tooltipText: "Open issues"; onActivated: root.loadDetails(repoCard.repo, "issues") }
        Metric { iconText: Model.icon("pull"); valueText: Model.formatNumber(repoCard.repo._pullsCount); tint: root.accent; actionable: true; tooltipText: "Open pull requests"; onActivated: root.loadDetails(repoCard.repo, "pulls") }
        Item { Layout.fillWidth: true }
        PanelActionButton { iconText: "󰐊"; tooltipText: "Workflow runs"; foreground: root.dim; hoverColor: root.foreground; fontFamily: root.fontFamily; onClicked: root.loadWorkflows(repoCard.repo) }
        PanelActionButton { iconText: "󰏌"; tooltipText: "Open on GitHub"; foreground: root.dim; hoverColor: root.foreground; fontFamily: root.fontFamily; onClicked: { root.openUrl(repoCard.repo.html_url); root.close() } }
        PanelActionButton { visible: repoCard.path !== ""; iconText: Model.icon("folderOpen"); tooltipText: "Open in " + String(setting("localEditor", "code")) + "\n" + repoCard.path; foreground: root.accent; hoverColor: root.accent; fontFamily: root.fontFamily; onClicked: root.openRepo(repoCard.repo) }
      }
    }
  }

  component DetailCard: CursorSurface {
    id: detailCard
    property var item: null
    property string kind: ""
    readonly property bool isRun: kind === "workflows"
    readonly property color tone: isRun ? root.toneColor(Model.workflowTone(item)) : (item && item.draft ? root.dim : (kind === "pulls" ? root.accent : root.success))
    readonly property bool canRerun: isRun && item.status === "completed" && (item.conclusion === "failure" || item.conclusion === "cancelled" || item.conclusion === "timed_out")
    width: parent ? parent.width : 0
    implicitHeight: detailColumn.implicitHeight + root.cardPadding * 2
    foreground: root.foreground
    bordered: true
    hasCursor: detailHover.hovered
    HoverHandler { id: detailHover }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; scrollGestureEnabled: false; onClicked: { root.openUrl(detailCard.item.html_url); root.close() } }
    RowLayout {
      id: detailColumn
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.margins: root.cardPadding; anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)
      Item {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(1)
        implicitWidth: Style.space(18); implicitHeight: implicitWidth
        Text {
          anchors.centerIn: parent
          text: detailCard.isRun ? Model.workflowIcon(detailCard.item) : (detailCard.kind === "pulls" ? Model.icon(detailCard.item.draft ? "draft" : "pull") : Model.icon("issue"))
          color: detailCard.tone
          font.family: root.fontFamily
          font.pixelSize: root.scaledFont(Style.font.icon)
          RotationAnimation on rotation { from: 0; to: 360; duration: 1200; loops: Animation.Infinite; running: detailCard.isRun && detailCard.item.status !== "completed" }
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(3)
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Text { visible: !detailCard.isRun; text: "#" + detailCard.item.number; color: root.dim; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body); font.features: { "tnum": 1 } }
          Text { Layout.fillWidth: true; text: detailCard.isRun ? (detailCard.item.display_title || detailCard.item.name) : detailCard.item.title; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.scaledFont(Style.font.body); font.weight: Font.DemiBold; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          Pill { visible: detailCard.isRun; text: Model.workflowStatus(detailCard.item); tint: detailCard.tone }
          Pill { visible: !detailCard.isRun && detailCard.item.draft; text: "Draft"; tint: root.dim }
          Text {
            Layout.fillWidth: true
            text: detailCard.isRun
              ? [detailCard.item.name, detailCard.item.head_branch ? Model.icon("branch") + " " + detailCard.item.head_branch : "", Model.workflowDuration(detailCard.item) ? "󰔟 " + Model.workflowDuration(detailCard.item) : "", Model.relativeTime(detailCard.item.updated_at)].filter(function(s) { return s }).join("  ·  ")
              : [(detailCard.item.user ? "@" + detailCard.item.user.login : ""), Model.relativeTime(detailCard.item.updated_at)].filter(function(s) { return s }).join("  ·  ")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.scaledFont(Style.font.caption)
            elide: Text.ElideRight
          }
        }
        Flow {
          visible: !detailCard.isRun && detailCard.item.labels && detailCard.item.labels.length > 0
          Layout.fillWidth: true
          spacing: Style.space(4)
          Repeater {
            model: detailCard.item.labels ? detailCard.item.labels.slice(0, 6) : []
            Rectangle {
              required property var modelData
              readonly property color labelColor: "#" + modelData.color
              implicitWidth: labelText.implicitWidth + Style.space(10)
              implicitHeight: labelText.implicitHeight + Style.space(4)
              radius: root.cardRadius > 0 ? height / 2 : 0
              color: Util.alpha(labelColor, 0.22)
              border.width: 1
              border.color: Util.alpha(labelColor, 0.7)
              Text { id: labelText; anchors.centerIn: parent; text: modelData.name; color: Qt.lighter(parent.labelColor, 1.35); font.family: root.fontFamily; font.pixelSize: Math.round(root.scaledFont(Style.font.caption) * 0.95); font.bold: true }
            }
          }
        }
      }
      Button {
        visible: detailCard.canRerun
        Layout.alignment: Qt.AlignVCenter
        iconText: "󰑐"
        text: "Re-run"
        iconSpinning: root.pendingAction === "rerun"
        foreground: root.accent
        fontFamily: root.fontFamily
        fontSize: root.scaledFont(Style.font.caption)
        iconSize: root.scaledFont(Style.font.caption)
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(4)
        bordered: true
        onClicked: root.rerun(detailCard.item)
      }
    }
  }
}
