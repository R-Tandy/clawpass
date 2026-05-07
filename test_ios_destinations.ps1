$destinations = @('platform=iOS Simulator,name=iPhone 14,OS=16.0','platform=iOS Simulator,name=iPhone 13,OS=16.0','platform=iOS Simulator,name=iPhone 12,OS=16.0');
foreach ($dest in $destinations) {
  Write-Host "Trying $dest";
  (Get-Content .github/workflows/ci.yml) -replace "-destination '.*'", "-destination '$dest'" | Set-Content .github/workflows/ci.yml;
  git add .github/workflows/ci.yml;
  git commit -m "Try $dest";
  git push origin master;
  $maxAttempts = 30;
  for ($a=0;$a -lt $maxAttempts;$a++) {
    Start-Sleep -Seconds 10;
    $runsJson = Invoke-WebRequest -Uri "https://api.github.com/repos/R-Tandy/clawpass/actions/runs?branch=master" -Headers @{"Accept"="application/vnd.github+json"} -UseBasicParsing | ConvertFrom-Json
    $run = ($runsJson | ConvertFrom-Json).workflow_runs | Where-Object {$_.name -eq "CI Build"} | Sort-Object created_at -Descending | Select-Object -First 1;
    if ($run -and $run.status -eq "completed") {
      if ($run.conclusion -eq "success") {
        $artifactsJson = Invoke-WebRequest -Uri "https://api.github.com/repos/R-Tandy/clawpass/actions/runs/$($run.id)/artifacts" -Headers @{"Accept"="application/vnd.github+json"} -UseBasicParsing | ConvertFrom-Json
        $cnt = ($artifactsJson | ConvertFrom-Json).total_count;
        if ($cnt -gt 0) {
          Write-Host "SUCCESS with $dest";
          exit 0;
        }
      }
    }
  }
}
Write-Host "ALL FAILED"; exit 1;