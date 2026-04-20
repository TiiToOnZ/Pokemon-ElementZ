# Replacement for the legacy extendtext.exe utility.
# Usage:
#   1. Open a Show Text / Script / Comment dialog in RPG Maker XP.
#   2. Run extendtext_replacement.cmd
# Optional parameters:
#   -TargetEditWidth 560 -TargetEditHeight 220
#   The watcher stays alive and auto-expands new dialogs until RPG Maker XP is closed.
param(
  [int]$TargetEditWidth = 840,
  [int]$TargetEditHeight = 240,
  [int]$PollIntervalMs = 250,
  [switch]$Silent = $true
)

Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ExtendTextWin32
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool ScreenToClient(IntPtr hWnd, ref POINT point);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
}
"@

$dialogTitles = @(
  'Show Text',
  'Script',
  'Comment',
  'Batch Text Entry',
  'Afficher un texte',
  'Commentaire'
)

$multilineEditClasses = @('EDIT', 'Edit', 'RichEdit20A', 'RichEdit20W', 'RICHEDIT')
$mutexName = 'RPGXP-ExpandText-E0E82E69-D201-42A9-9F65-38F18051161D-Replacement'

function Get-WindowTextValue {
  param([System.IntPtr]$Handle)

  $builder = New-Object System.Text.StringBuilder 512
  [void][ExtendTextWin32]::GetWindowText($Handle, $builder, $builder.Capacity)
  return $builder.ToString()
}

function Get-ClassNameValue {
  param([System.IntPtr]$Handle)

  $builder = New-Object System.Text.StringBuilder 256
  [void][ExtendTextWin32]::GetClassName($Handle, $builder, $builder.Capacity)
  return $builder.ToString()
}

function Get-WindowRectValue {
  param([System.IntPtr]$Handle)

  $rect = New-Object ExtendTextWin32+RECT
  if (-not [ExtendTextWin32]::GetWindowRect($Handle, [ref]$rect)) {
    return $null
  }

  return [pscustomobject]@{
    Left = $rect.Left
    Top = $rect.Top
    Right = $rect.Right
    Bottom = $rect.Bottom
    Width = $rect.Right - $rect.Left
    Height = $rect.Bottom - $rect.Top
  }
}

function Get-ClientRectValue {
  param([System.IntPtr]$Handle)

  $rect = New-Object ExtendTextWin32+RECT
  if (-not [ExtendTextWin32]::GetClientRect($Handle, [ref]$rect)) {
    return $null
  }

  return [pscustomobject]@{
    Left = $rect.Left
    Top = $rect.Top
    Right = $rect.Right
    Bottom = $rect.Bottom
    Width = $rect.Right - $rect.Left
    Height = $rect.Bottom - $rect.Top
  }
}

function Convert-WindowRectToClientRect {
  param(
    [System.IntPtr]$ParentHandle,
    [System.IntPtr]$ChildHandle
  )

  $windowRect = Get-WindowRectValue $ChildHandle
  if (-not $windowRect) {
    return $null
  }

  $topLeft = New-Object ExtendTextWin32+POINT
  $topLeft.X = $windowRect.Left
  $topLeft.Y = $windowRect.Top
  $bottomRight = New-Object ExtendTextWin32+POINT
  $bottomRight.X = $windowRect.Right
  $bottomRight.Y = $windowRect.Bottom
  [void][ExtendTextWin32]::ScreenToClient($ParentHandle, [ref]$topLeft)
  [void][ExtendTextWin32]::ScreenToClient($ParentHandle, [ref]$bottomRight)

  return [pscustomobject]@{
    Left = $topLeft.X
    Top = $topLeft.Y
    Right = $bottomRight.X
    Bottom = $bottomRight.Y
    Width = $bottomRight.X - $topLeft.X
    Height = $bottomRight.Y - $topLeft.Y
  }
}

function Get-ChildWindows {
  param([System.IntPtr]$ParentHandle)

  $children = New-Object System.Collections.Generic.List[System.IntPtr]
  $callback = [ExtendTextWin32+EnumWindowsProc]{
    param($hWnd, $lParam)
    $null = $children.Add($hWnd)
    return $true
  }

  [void][ExtendTextWin32]::EnumChildWindows($ParentHandle, $callback, [System.IntPtr]::Zero)
  return $children
}

function Get-DialogChildrenInfo {
  param([System.IntPtr]$DialogHandle)

  $clientRect = Get-ClientRectValue $DialogHandle
  if (-not $clientRect) {
    return @()
  }

  return @(Get-ChildWindows $DialogHandle | ForEach-Object {
    $handle = $_
    $className = Get-ClassNameValue $handle
    $text = Get-WindowTextValue $handle
    $rect = Convert-WindowRectToClientRect $DialogHandle $handle
    if (-not $rect) {
      return
    }

    [pscustomobject]@{
      Handle = $handle
      ClassName = $className
      Text = $text
      Rect = $rect
      Area = $rect.Width * $rect.Height
      DistanceFromRight = $clientRect.Width - $rect.Right
      DistanceFromBottom = $clientRect.Height - $rect.Bottom
    }
  })
}

function Test-TargetDialog {
  param([System.IntPtr]$Handle)

  if ($Handle -eq [System.IntPtr]::Zero) {
    return $false
  }

  if (-not [ExtendTextWin32]::IsWindowVisible($Handle)) {
    return $false
  }

  $className = Get-ClassNameValue $Handle
  if ($className -ne '#32770') {
    return $false
  }

  $title = Get-WindowTextValue $Handle
  $children = Get-DialogChildrenInfo $Handle
  if (-not $children) {
    return $false
  }

  $hasEdit = $children | Where-Object { $multilineEditClasses -contains $_.ClassName } | Select-Object -First 1
  if (-not $hasEdit) {
    return $false
  }

  if ($dialogTitles -contains $title) {
    return $true
  }

  return $title -match 'Text|Script|Comment'
}

function Get-EditorWindows {
  $handles = New-Object System.Collections.Generic.List[System.IntPtr]
  $callback = [ExtendTextWin32+EnumWindowsProc]{
    param($hWnd, $lParam)
    if (-not [ExtendTextWin32]::IsWindowVisible($hWnd)) {
      return $true
    }

    $title = Get-WindowTextValue $hWnd
    if ($title -match 'RPG Maker XP') {
      $null = $handles.Add($hWnd)
    }
    return $true
  }

  [void][ExtendTextWin32]::EnumWindows($callback, [System.IntPtr]::Zero)
  return @($handles)
}

function Get-TargetDialogs {
  $handles = New-Object System.Collections.Generic.List[System.IntPtr]
  $knownHandles = New-Object 'System.Collections.Generic.HashSet[string]'
  $foreground = [ExtendTextWin32]::GetForegroundWindow()
  if (Test-TargetDialog $foreground) {
    $null = $knownHandles.Add($foreground.ToInt64().ToString())
    $null = $handles.Add($foreground)
  }

  $callback = [ExtendTextWin32+EnumWindowsProc]{
    param($hWnd, $lParam)
    if (Test-TargetDialog $hWnd) {
      $key = $hWnd.ToInt64().ToString()
      if ($knownHandles.Add($key)) {
        $null = $handles.Add($hWnd)
      }
    }
    return $true
  }

  [void][ExtendTextWin32]::EnumWindows($callback, [System.IntPtr]::Zero)
  return @($handles)
}

function Find-MainEditControl {
  param([System.IntPtr]$DialogHandle)

  return Get-DialogChildrenInfo $DialogHandle |
    Where-Object { $multilineEditClasses -contains $_.ClassName } |
    Sort-Object Area -Descending |
    Select-Object -First 1
}

function Expand-Dialog {
  param([System.IntPtr]$DialogHandle)

  $dialogRect = Get-WindowRectValue $DialogHandle
  $clientRect = Get-ClientRectValue $DialogHandle
  $children = Get-DialogChildrenInfo $DialogHandle
  $mainEdit = Find-MainEditControl $DialogHandle
  if (-not $dialogRect -or -not $clientRect -or -not $mainEdit) {
    throw 'Unable to inspect the target dialog.'
  }

  $extraWidth = [Math]::Max(0, $TargetEditWidth - $mainEdit.Rect.Width)
  $extraHeight = [Math]::Max(0, $TargetEditHeight - $mainEdit.Rect.Height)

  if ($extraWidth -le 0 -and $extraHeight -le 0) {
    return [pscustomobject]@{
      DialogTitle = Get-WindowTextValue $DialogHandle
      ExtraWidth = 0
      ExtraHeight = 0
      Changed = $false
    }
  }

  [void][ExtendTextWin32]::MoveWindow(
    $DialogHandle,
    $dialogRect.Left,
    $dialogRect.Top,
    $dialogRect.Width + $extraWidth,
    $dialogRect.Height + $extraHeight,
    $true
  )

  $editBottom = $mainEdit.Rect.Bottom
  foreach ($child in $children) {
    $newX = $child.Rect.Left
    $newY = $child.Rect.Top
    $newWidth = $child.Rect.Width
    $newHeight = $child.Rect.Height

    if ($child.Handle -eq $mainEdit.Handle) {
      $newWidth += $extraWidth
      $newHeight += $extraHeight
    } else {
      if ($child.Rect.Top -ge ($editBottom - 4)) {
        $newY += $extraHeight
      }

      if ($child.DistanceFromRight -le 24) {
        $newX += $extraWidth
      }
    }

    [void][ExtendTextWin32]::MoveWindow(
      $child.Handle,
      $newX,
      $newY,
      $newWidth,
      $newHeight,
      $true
    )
  }

  return [pscustomobject]@{
    DialogTitle = Get-WindowTextValue $DialogHandle
    ExtraWidth = $extraWidth
    ExtraHeight = $extraHeight
    Changed = $true
  }
}

function Show-Info {
  param([string]$Message)

  if ($Silent) {
    Write-Output $Message
    return
  }

  [void][System.Windows.Forms.MessageBox]::Show(
    $Message,
    'ExtendText Replacement',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  )
}

try {
  $createdNew = $false
  $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
  if (-not $createdNew) {
    exit 0
  }

  if ((Get-EditorWindows).Count -eq 0) {
    throw 'RPG Maker XP was not found. Start the editor first, then run the tool.'
  }

  while ((Get-EditorWindows).Count -gt 0) {
    foreach ($dialog in Get-TargetDialogs) {
      $result = Expand-Dialog $dialog
      if ($result.Changed -and -not $Silent) {
        Show-Info("Extended '$($result.DialogTitle)' by $($result.ExtraWidth) px horizontally and $($result.ExtraHeight) px vertically.")
      }
    }

    Start-Sleep -Milliseconds ([Math]::Max(50, $PollIntervalMs))
  }

  exit 0
} catch {
  $message = $_.Exception.Message
  if ($Silent) {
    Write-Error $message
    exit 1
  }

  [void][System.Windows.Forms.MessageBox]::Show(
    $message,
    'ExtendText Replacement',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error
  )
  exit 1
} finally {
  if ($mutex) {
    try {
      $mutex.ReleaseMutex() | Out-Null
    } catch {
    }
    $mutex.Dispose()
  }
}
