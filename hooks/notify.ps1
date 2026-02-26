#Requires -Version 5.1
<#
.SYNOPSIS
Claude Code PermissionRequest/Notification hook: show an urgent Windows toast.

Always shows the reminder-style toast (no stdin needed).
Used by the PermissionRequest and Notification hook events.

Install: copy to %USERPROFILE%\.claude\hooks\notify.ps1
#>

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

$xml = @'
<toast scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>&#x23F8; Claude is waiting</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Reminder"/>
</toast>
'@

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
