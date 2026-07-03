# working-on-board.ps1
# Builds "What Was I Working On" - a standing HTML board of real Claude CLI work sessions.
# Reads timestamps INSIDE session files (file dates get stomped and cannot be trusted).
# Filters out headless/scheduled/automation sessions and folds duplicate retry fragments.
# Output: an HTML page on the Desktop with first ask, last message, and click-to-copy resume commands.
# PowerShell 5.1 compatible. ASCII only.

param(
    [int]$Days = 90,
    [string]$OutPath = "$env:USERPROFILE\Desktop\What-Was-I-Working-On.html",
    [switch]$NoOpen,
    [int]$MinKB = 20
)

$ErrorActionPreference = 'SilentlyContinue'
$projRoot = "$env:USERPROFILE\.claude\projects"
$cutoff = (Get-Date).AddDays(-$Days)

# Lines that are not a real typed message from the user
$skipLinePattern = 'system-reminder|command-name|local-command|task-notification|tool_result|dangerously-skip-permissions|Caveat: The messages below'
# First-message patterns that mark a whole session as automation, not human work
$junkSessionPattern = '^(HEADLESS|Analyze these source file|CONTEXT:|This is an automated run|<scheduled-task|No files found|Session Summary)'

function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
}

function CleanMsg([string]$raw) {
    $m = $raw -replace '\\n', ' ' -replace '\\t', ' ' -replace '\\"', '"' -replace '\\\\', '\'
    $m = $m -replace '\s+', ' '
    return $m.Trim()
}

$contentRegex = [regex]'"content"\s*:\s*"((?:[^"\\]|\\.){15,400})'
$textRegex    = [regex]'"text"\s*:\s*"((?:[^"\\]|\\.){15,400})'
$tsRegex      = [regex]'"timestamp"\s*:\s*"([^"]+)"'
$cwdRegex     = [regex]'"cwd"\s*:\s*"((?:[^"\\]|\\.)+)"'
$fpRegex      = [regex]'"file_path"\s*:\s*"((?:[^"\\]|\\.){5,300})'
$skillRegex   = [regex]'"skill"\s*:\s*"([^"]{2,60})"'
$cmdRegex     = [regex]'"command"\s*:\s*"((?:[^"\\]|\\.){5,300})'
$titleRegex   = [regex]'"title"\s*:\s*"((?:[^"\\]|\\.){5,200})'

Write-Host "Scanning sessions (internal timestamps, last $Days days)..."

$sessions = @()
$files = Get-ChildItem $projRoot -Recurse -Filter *.jsonl -File | Where-Object {
    $_.Name -notlike 'agent-*' -and $_.Length -gt ($MinKB * 1KB)
}

foreach ($f in $files) {
    # Cheap pre-check: last internal timestamp from the tail. Skip old sessions without a full read.
    $lastTs = $null
    foreach ($t in (Get-Content $f.FullName -Tail 12)) {
        $m = $tsRegex.Match($t)
        if ($m.Success) { $lastTs = $m.Groups[1].Value }
    }
    if (-not $lastTs) { continue }
    $lastDt = $null
    try { $lastDt = [datetime]::Parse($lastTs).ToLocalTime() } catch { continue }
    if ($lastDt -lt $cutoff) { continue }

    # Full streaming pass: first timestamp, cwd, first and last real user messages, ask count
    $firstTs = $null; $cwd = $null; $firstMsg = $null; $lastMsg = $null; $askCount = 0; $tagBlob = ''; $extraBlob = ''; $queueOps = 0; $lineCount = 0
    $reader = New-Object System.IO.StreamReader($f.FullName)
    try {
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            $lineCount++
            if (-not $firstTs) {
                $m = $tsRegex.Match($line)
                if ($m.Success) { $firstTs = $m.Groups[1].Value }
            }
            if (-not $cwd) {
                $m = $cwdRegex.Match($line)
                if ($m.Success) { $cwd = $m.Groups[1].Value -replace '\\\\', '\' }
            }
            if ($line.IndexOf('"type":"user"') -lt 0) {
                if ($line.IndexOf('"type":"queue-operation"') -ge 0) { $queueOps++ }
                # Assistant lines feed the tag blobs only: prose names the client even when the user's
                # typed text doesn't, and file paths / skill names / commands are the strongest signal.
                # Match on role, not outer type: queue-stub fragments store replies as type "message".
                if ($line.IndexOf('"role":"assistant"') -ge 0) {
                    if ($tagBlob.Length -lt 12000) {
                        $m = $textRegex.Match($line)
                        if ($m.Success) { $tagBlob += ' ' + $m.Groups[1].Value }
                    }
                    if ($extraBlob.Length -lt 20000) {
                        foreach ($m in $fpRegex.Matches($line)) { $extraBlob += ' ' + $m.Groups[1].Value }
                        $m = $skillRegex.Match($line)
                        if ($m.Success) { $extraBlob += ' ' + $m.Groups[1].Value }
                        $m = $cmdRegex.Match($line)
                        if ($m.Success) { $extraBlob += ' ' + $m.Groups[1].Value }
                    }
                }
                elseif ($extraBlob.Length -lt 20000 -and $line -match '"type":"(queue-operation|ai-title|summary)"') {
                    # Stub fragments: queued messages, generated titles, and summaries name the work
                    $m = $contentRegex.Match($line)
                    if (-not $m.Success) { $m = $textRegex.Match($line) }
                    if (-not $m.Success) { $m = $titleRegex.Match($line) }
                    if ($m.Success) { $extraBlob += ' ' + $m.Groups[1].Value }
                }
                continue
            }
            if ($line -match $skipLinePattern) {
                # Tool results (files read, pages fetched) carry client signal for tagging, never for display
                if ($extraBlob.Length -lt 20000 -and $line.IndexOf('tool_result') -ge 0) {
                    $m = $contentRegex.Match($line)
                    if (-not $m.Success) { $m = $textRegex.Match($line) }
                    if ($m.Success) { $extraBlob += ' ' + $m.Groups[1].Value }
                }
                continue
            }
            $m = $contentRegex.Match($line)
            if (-not $m.Success) { $m = $textRegex.Match($line) }
            if ($m.Success) {
                $msg = CleanMsg $m.Groups[1].Value
                if ($msg.Length -lt 15) { continue }
                if (-not $firstMsg) { $firstMsg = $msg }
                $lastMsg = $msg
                $askCount++
                if ($tagBlob.Length -lt 8000) { $tagBlob += ' ' + $msg }
            }
        }
    } finally { $reader.Close() }

    if (-not $firstMsg) { continue }
    if ($firstMsg -match $junkSessionPattern) { continue }
    # Queue-stub remnants: a whole FILE of just a few lines around one queued message. The message
    # was delivered into a parent session that has its own row. Real sessions have hundreds of lines
    # even when message capture is thin, so the line-count guard protects them.
    if ($queueOps -gt 0 -and $askCount -le 1 -and $lineCount -le 20) { continue }

    $firstDt = $null
    try { if ($firstTs) { $firstDt = [datetime]::Parse($firstTs).ToLocalTime() } } catch { }
    if (-not $firstDt) { $firstDt = $lastDt }
    if (-not $cwd) { $cwd = 'C:\Windows\System32' }

    $sessions += New-Object PSObject -Property @{
        Id       = $f.BaseName
        First    = $firstDt
        Last     = $lastDt
        KB       = [math]::Round($f.Length / 1KB)
        Asks     = $askCount
        FirstMsg  = $firstMsg
        LastMsg   = $lastMsg
        Cwd       = $cwd
        TagBlob   = $tagBlob
        ExtraBlob = $extraBlob
    }
}

# Fold retry fragments: sessions sharing the same opening message keep only the largest copy
$folded = 0
$byKey = $sessions | Group-Object { $k = $_.FirstMsg.ToLower(); $k.Substring(0, [math]::Min(60, $k.Length)) }
$kept = @()
foreach ($g in $byKey) {
    $main = $g.Group | Sort-Object KB -Descending | Select-Object -First 1
    $extra = $g.Count - 1
    if ($extra -gt 0) { $folded += $extra }
    $main | Add-Member -NotePropertyName Retries -NotePropertyValue $extra -Force
    $kept += $main
}
$kept = $kept | Sort-Object Last -Descending

# ============================================================================
# PERSONALIZE THESE BUCKETS - this is the only part of the script that is yours
#
# Sessions are tagged by SCORING every bucket against all the session's evidence
# (typed messages, assistant prose, file paths, skill names, commands, tool results).
# Highest hit count wins; ties go to the earlier (more specific) bucket.
#
# Phase 1 = identity terms: names, org names, project codenames, voice-skill names,
#           folder names. Precise words that identify WHO the work is for.
# Phase 2 = lane vocabulary: subject words, used only when nobody is named at all.
#
# Write patterns as lowercase regex. Use \b word boundaries for short words that
# hide inside longer ones ('\bcis\b', '\bbob\b').
# ============================================================================
function TagOf($s) {
    $human = ($s.TagBlob + ' ' + $s.FirstMsg + ' ' + $s.LastMsg).ToLower()
    $all = ($human + ' ' + $s.ExtraBlob + ' ' + $s.Cwd).ToLower()
    # Phase 1: WHO is named. Identity terms only - precise, so a client session full
    # of generic industry words still lands with the client it names.
    $idBuckets = @(
        @{ Name = 'CLIENT A';    Pattern = 'alice|acme|acme-corp|alice-voice' },
        @{ Name = 'CLIENT B';    Pattern = '\bbob\b|globex|bob_g_smith' },
        @{ Name = 'MY BUSINESS'; Pattern = 'my business|my newsletter|my keynote|your-name-here|your-company-here' }
    )
    $best = ''; $bestScore = 0
    foreach ($b in $idBuckets) {
        $c = [regex]::Matches($all, $b.Pattern).Count
        if ($c -gt $bestScore) { $bestScore = $c; $best = $b.Name }
    }
    if ($bestScore -gt 0) { return $best }
    # Phase 2: nobody named - classify by lane/topic vocabulary instead.
    # Add a lane entry per client whose subject vocabulary is distinctive, e.g.
    #   @{ Name = 'CLIENT A'; Scope = $all; Pattern = 'supply chain|logistics|freight' },
    # SYSTEM + TOOLING must score on $human only; its vocabulary (session, hook,
    # memory, claude, skill) appears in the raw JSON of every session and would
    # otherwise swallow the whole board.
    $topicBuckets = @(
        @{ Name = 'MY BUSINESS';      Scope = $all;   Pattern = 'positioning|keynote|podcast|newsletter|speaking|bookkeeping|accounting' },
        @{ Name = 'VIDEO + MEDIA';    Scope = $all;   Pattern = 'video|clip|ffmpeg|handbrake|watermark|speaker|transcri|whisper|footage|headshot|recording|\bmp4\b|\bsrt\b' },
        @{ Name = 'SYSTEM + TOOLING'; Scope = $human; Pattern = 'session|dashboard|hook|notion|memory|claude|terminal|\bcli\b|skill|agent|schedule|automation|\bmcp\b' }
    )
    # Zero signal anywhere = a conversation about the work itself, not a client's work.
    # Those belong with the system sessions - there is no "everything else" bucket.
    $best = 'SYSTEM + TOOLING'; $bestScore = 0
    foreach ($b in $topicBuckets) {
        $c = [regex]::Matches($b.Scope, $b.Pattern).Count
        if ($c -gt $bestScore) { $bestScore = $c; $best = $b.Name }
    }
    return $best
}

foreach ($s in $kept) { $s | Add-Member -NotePropertyName Tag -NotePropertyValue (TagOf $s) -Force }
$hotCutoff = (Get-Date).AddHours(-48)

# Sections ordered by freshest activity; rows inside each section newest first
$groups = $kept | Group-Object Tag | Sort-Object { ($_.Group | Measure-Object -Property Last -Maximum).Maximum } -Descending

# Build rows and the anchor-link tag bar
$sb = New-Object System.Text.StringBuilder
$chips = New-Object System.Text.StringBuilder
foreach ($g in $groups) {
    $rows = @($g.Group | Sort-Object Last -Descending)
    $newest = ($rows | Select-Object -First 1).Last
    $secId = 'sec-' + (($g.Name -replace '[^A-Za-z]', '').ToLower())
    [void]$chips.Append('<a class="chip" href="#' + $secId + '">' + (Esc $g.Name) + ' <span class="n">' + $rows.Count + '</span></a>')
    [void]$sb.AppendLine('<div class="section" id="' + $secId + '">')
    [void]$sb.AppendLine('  <div class="sechead" onclick="toggleSec(this)"><span class="arrow">&#9660;</span> ' + (Esc $g.Name) + ' <span class="seccount">' + $rows.Count + ' sessions &middot; newest ' + ('{0:MMM dd}' -f $newest) + '</span></div>')
    [void]$sb.AppendLine('  <div class="secrows">')
    foreach ($s in $rows) {
        $range = '{0:MMM dd HH:mm} to {1:MMM dd HH:mm}' -f $s.First, $s.Last
        $meta = '{0} &middot; {1} KB &middot; {2} messages' -f $range, $s.KB, $s.Asks
        if ($s.Retries -gt 0) { $meta += ' &middot; +' + $s.Retries + ' retry fragments folded' }
        $cmd = 'cd "' + $s.Cwd + '"; claude --resume ' + $s.Id
        $searchBlob = Esc(($s.FirstMsg + ' ' + $s.LastMsg + ' ' + $s.Id + ' ' + $range + ' ' + $g.Name).ToLower())
        $firstShow = Esc($s.FirstMsg.Substring(0, [math]::Min(280, $s.FirstMsg.Length)))
        $lastShow = Esc($s.LastMsg.Substring(0, [math]::Min(280, $s.LastMsg.Length)))
        $hotClass = ''
        if ($s.Last -gt $hotCutoff) { $hotClass = ' hot' }
        [void]$sb.AppendLine('<div class="row' + $hotClass + '" data-search="' + $searchBlob + '">')
        [void]$sb.AppendLine('  <div class="meta">' + $meta + '</div>')
        [void]$sb.AppendLine('  <div class="first"><span class="lbl">STARTED WITH:</span> ' + $firstShow + '</div>')
        if ($s.LastMsg -ne $s.FirstMsg) {
            [void]$sb.AppendLine('  <div class="last"><span class="lbl">LEFT OFF AT:</span> ' + $lastShow + '</div>')
        }
        [void]$sb.AppendLine('  <div class="cmd" onclick="copyCmd(this)" data-cmd="' + (Esc($cmd)) + '">' + (Esc($cmd)) + ' <span class="hint">click to copy</span></div>')
        [void]$sb.AppendLine('</div>')
    }
    [void]$sb.AppendLine('  </div>')
    [void]$sb.AppendLine('</div>')
}

$gen = Get-Date -Format 'yyyy-MM-dd HH:mm'
$shown = $kept.Count

$html = @'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="120">
<title>What Was I Working On</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; background: #16181d; color: #e6e6e6; margin: 0; }
  .head { position: sticky; top: 0; background: #1e2128; padding: 16px 24px; border-bottom: 1px solid #333; }
  .head h1 { margin: 0 0 4px 0; font-size: 20px; }
  .head .sub { color: #9aa0a8; font-size: 13px; margin-bottom: 10px; }
  #q { width: 100%; max-width: 640px; padding: 10px 12px; font-size: 15px; background: #121419;
       color: #e6e6e6; border: 1px solid #444; border-radius: 6px; box-sizing: border-box; }
  .rows { padding: 12px 24px 48px 24px; }
  .row { background: #1e2128; border: 1px solid #2c2f36; border-radius: 8px; padding: 12px 16px; margin: 10px 0; }
  .meta { color: #9aa0a8; font-size: 12px; margin-bottom: 6px; }
  .lbl { color: #7fb1e8; font-size: 11px; font-weight: 600; letter-spacing: 0.4px; }
  .first { font-size: 14px; margin-bottom: 4px; }
  .last { font-size: 13px; color: #c4c9d0; margin-bottom: 4px; }
  .cmd { font-family: Consolas, monospace; font-size: 12px; color: #8fd48f; background: #121419;
         padding: 6px 10px; border-radius: 5px; margin-top: 6px; cursor: pointer; word-break: break-all; }
  .cmd:hover { background: #0e1013; }
  .cmd.copied { outline: 1px solid #8fd48f; }
  .hint { color: #666; font-size: 11px; }
  .howto { color: #9aa0a8; font-size: 12px; margin-top: 8px; }
  .chips { margin-top: 10px; }
  .chip { display: inline-block; background: #242832; border: 1px solid #3a3f4a; border-radius: 14px;
          padding: 4px 12px; margin: 2px 6px 2px 0; color: #e6e6e6; text-decoration: none; font-size: 12px; }
  .chip:hover { background: #2c313d; border-color: #7fb1e8; }
  .chip .n { color: #9aa0a8; margin-left: 4px; }
  .section { scroll-margin-top: 185px; }
  html { scroll-behavior: smooth; }
  .sechead { font-size: 15px; font-weight: 600; color: #e6e6e6; padding: 18px 4px 2px 4px; cursor: pointer;
             letter-spacing: 0.5px; user-select: none; }
  .sechead .arrow { color: #7fb1e8; font-size: 11px; }
  .seccount { color: #9aa0a8; font-weight: 400; font-size: 12px; margin-left: 8px; }
  .row.hot { border-left: 3px solid #8fd48f; }
  .secrows.folded { display: none; }
  body.searching .secrows { display: block !important; }
</style>
</head>
<body>
<div class="head">
  <h1>What Was I Working On</h1>
  <div class="sub">{{SHOWN}} real work sessions from the last {{DAYS}} days &middot; grouped by client, freshest first &middot; green edge = active in last 48h &middot; click a section title to fold it &middot; <span style="color:#8fd48f">rebuilt every 4 hours, at logon, and when any session ends</span> &middot; updated {{GEN}}</div>
  <input id="q" type="text" placeholder="Type to filter: a client name, a project, any keyword...">
  <div class="chips">{{CHIPS}}</div>
  <div class="howto">To pick a session back up: click its green command (copies), open a NEW terminal, paste, Enter. Add --fork-session to leave the original untouched.</div>
</div>
<div class="rows" id="rows">
{{ROWS}}
</div>
<script>
function copyCmd(el) {
  var c = el.getAttribute('data-cmd');
  navigator.clipboard.writeText(c).then(function () {
    el.classList.add('copied');
    setTimeout(function () { el.classList.remove('copied'); }, 900);
  });
}
function toggleSec(head) {
  var sec = head.parentNode;
  var rows = sec.querySelector('.secrows');
  var folded = rows.classList.toggle('folded');
  head.querySelector('.arrow').textContent = String.fromCharCode(folded ? 9654 : 9660);
  var list = [];
  try { list = JSON.parse(localStorage.getItem('wiwoFolded') || '[]'); } catch (e) {}
  if (folded) { if (list.indexOf(sec.id) < 0) { list.push(sec.id); } }
  else { list = list.filter(function (x) { return x !== sec.id; }); }
  try { localStorage.setItem('wiwoFolded', JSON.stringify(list)); } catch (e) {}
}
try {
  var fl = JSON.parse(localStorage.getItem('wiwoFolded') || '[]');
  for (var i = 0; i < fl.length; i++) {
    var sec = document.getElementById(fl[i]);
    if (sec) {
      sec.querySelector('.secrows').classList.add('folded');
      sec.querySelector('.arrow').textContent = String.fromCharCode(9654);
    }
  }
} catch (e) {}
function unfoldById(id) {
  var sec = document.getElementById(id);
  if (!sec) { return; }
  sec.querySelector('.secrows').classList.remove('folded');
  sec.querySelector('.arrow').textContent = String.fromCharCode(9660);
  var list = [];
  try { list = JSON.parse(localStorage.getItem('wiwoFolded') || '[]'); } catch (e) {}
  list = list.filter(function (x) { return x !== id; });
  try { localStorage.setItem('wiwoFolded', JSON.stringify(list)); } catch (e) {}
}
var chips = document.querySelectorAll('.chip');
for (var c = 0; c < chips.length; c++) {
  chips[c].addEventListener('click', function () {
    unfoldById(this.getAttribute('href').substring(1));
  });
}
var q = document.getElementById('q');
function applyFilter() {
  var v = q.value.toLowerCase();
  document.body.classList.toggle('searching', v.length > 0);
  var secs = document.querySelectorAll('.section');
  for (var j = 0; j < secs.length; j++) {
    var rows = secs[j].querySelectorAll('.row');
    var any = false;
    for (var i = 0; i < rows.length; i++) {
      var hit = rows[i].getAttribute('data-search').indexOf(v) >= 0;
      rows[i].style.display = hit ? '' : 'none';
      if (hit) { any = true; }
    }
    secs[j].style.display = any ? '' : 'none';
  }
}
q.addEventListener('input', function () {
  try { localStorage.setItem('wiwoFilter', q.value); } catch (e) {}
  applyFilter();
});
try { var saved = localStorage.getItem('wiwoFilter'); if (saved) { q.value = saved; } } catch (e) {}
applyFilter();
window.addEventListener('beforeunload', function () {
  try { localStorage.setItem('wiwoScroll', String(window.scrollY)); } catch (e) {}
});
try { var sy = localStorage.getItem('wiwoScroll'); if (sy) { window.scrollTo(0, parseInt(sy, 10)); } } catch (e) {}
</script>
</body>
</html>
'@

$html = $html.Replace('{{ROWS}}', $sb.ToString()).Replace('{{CHIPS}}', $chips.ToString()).Replace('{{GEN}}', $gen).Replace('{{DAYS}}', "$Days").Replace('{{SHOWN}}', "$shown")
$html | Out-File -FilePath $OutPath -Encoding UTF8

Write-Host "Wrote $shown sessions ($folded fragments folded) to: $OutPath"
foreach ($g in $groups) { Write-Host ('  {0}: {1}' -f $g.Name, $g.Group.Count) }
if (-not $NoOpen) { Start-Process $OutPath }
