#Requires -Version 5.1
<#
.SYNOPSIS
Claude Code Stop hook: show a Windows toast notification with type indicator.

Reads the Stop hook JSON from stdin, checks last_assistant_message, and shows:
  done     -> default notification sound, normal scenario
  question -> reminder sound, reminder scenario (prominent, persistent)

Install: copy to %USERPROFILE%\.claude\hooks\stop.ps1
#>

$json = [Console]::In.ReadToEnd()
try {
    $data = $json | ConvertFrom-Json
} catch {
    exit 0  # malformed JSON — silent exit, don't break Claude
}

# Suppress toast when Windows Terminal is the foreground window — user is already there
try {
    Add-Type -Name 'FgWin' -Namespace 'Claude' -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
'@
    $hwnd  = [Claude.FgWin]::GetForegroundWindow()
    $fgPid = 0
    [Claude.FgWin]::GetWindowThreadProcessId($hwnd, [ref]$fgPid) | Out-Null
    $fgProc = Get-Process -Id ([int]$fgPid) -ErrorAction SilentlyContinue
    if ($fgProc -and $fgProc.Name -eq 'WindowsTerminal') { exit 0 }
} catch { <# fail open — show toast if focus check errors #> }

$msg  = if ($data.last_assistant_message) { $data.last_assistant_message.TrimEnd() } else { '' }
$type = if ($msg.EndsWith('?')) { 'question' } else { 'done' }

if ($type -eq 'question') {
    $xml = @'
<toast scenario="reminder" activationType="protocol" launch="windowsterminal:">
  <visual>
    <binding template="ToastGeneric">
      <text>&#x2753; Claude has a question</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Reminder"/>
</toast>
'@
} else {
    $xml = @'
<toast activationType="protocol" launch="windowsterminal:">
  <visual>
    <binding template="ToastGeneric">
      <text>&#x2705; Response is ready</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default"/>
</toast>
'@
}

try {
    $XmlDoc = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]::New()
    $XmlDoc.LoadXml($xml)
    $toast = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]::New($XmlDoc)
    $toast.Tag   = 'claude-bell'
    $toast.Group = 'claude-bell'
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::CreateToastNotifier('ClaudeCode').Show($toast)
} catch {
    # Toast failed silently — don't break Claude Code
}
