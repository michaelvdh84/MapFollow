# Project-local toolchain. This script never changes the Windows user PATH.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskTools = Join-Path $taskRoot '.tools'
$env:PUB_CACHE = Join-Path $taskTools 'pub-cache'
$env:GRADLE_USER_HOME = Join-Path $taskTools 'gradle'
if (Test-Path (Join-Path $taskTools 'jdk')) { $env:JAVA_HOME = Join-Path $taskTools 'jdk' }
if (Test-Path (Join-Path $taskTools 'android-sdk')) {
    $env:ANDROID_HOME = Join-Path $taskTools 'android-sdk'
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
}
$taskFlutter = Join-Path $taskTools 'flutter\bin\flutter.bat'
if (!(Test-Path $taskFlutter)) {
    $taskInstalled = Get-Command flutter -ErrorAction SilentlyContinue
    if (!$taskInstalled) { throw 'Flutter absent. Consultez docs/android.md pour installer les prérequis.' }
    $taskFlutter = $taskInstalled.Source
}
if ($args.Count -gt 0 -and $args[0] -in @('build', 'run')) {
    $taskDebugKey = Join-Path $taskTools 'debug.keystore'
    if (!(Test-Path -LiteralPath $taskDebugKey)) {
        $taskKeytool = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' } else { $null }
        if (!$taskKeytool -or !(Test-Path -LiteralPath $taskKeytool)) {
            $taskKeytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
            if ($taskKeytoolCommand) { $taskKeytool = $taskKeytoolCommand.Source }
        }
        if (!$taskKeytool -or !(Test-Path -LiteralPath $taskKeytool)) {
            throw 'Java keytool absent. Configurez JAVA_HOME vers le JDK 17 ou le JBR Android Studio (voir docs/android.md).'
        }
        New-Item -ItemType Directory -Force -Path $taskTools | Out-Null
        # Standard public Android development credentials; never a release key.
        & $taskKeytool -genkeypair -keystore $taskDebugKey -storepass android -keypass android -alias androiddebugkey -dname 'CN=Android Debug,O=Android,C=BE' -keyalg RSA -keysize 2048 -validity 10000 *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Impossible de générer la clé Android de développement locale.' }
    }
}
Push-Location $taskRoot
try { & $taskFlutter @args; exit $LASTEXITCODE } finally { Pop-Location }
