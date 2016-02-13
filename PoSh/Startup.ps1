# SUMO Controller Web Frontend
# Will also start Controller script to allow Configuration changes in the frontend

# Use invariant Culture to avoid problems with comma seperator
[System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture;


#region Shared Variables
# These settings can be changed by the Frontend and will be used instantly by the Backend (SUMO-Controller.ps1)
#SUMO Controller Settings
$SumoSettings = [HashTable]::Synchronized(@{})
$SumoSettings.DayStartHour = [Int]'14'
$SumoSettings.DayEndHour = [Int]'21'
$SumoSettings.WeekendDayStartHour = [Int]'7'
$SumoSettings.WeekendDayEndHour = [Int]'22'
$SumoSettings.MinNightTemp = [Single]'19'
$SumoSettings.MaxNightTemp = [Single]'21'
$SumoSettings.MinDayTemp = [Single]'21'
$SumoSettings.MaxDayTemp = [Single]'23'

# This hashtable contains all common settings for the Backend
$SumoController = [HashTable]::Synchronized(@{})
$SumoController.State = 'Stopped'
$SumoController.Request = 'Run'
$SumoController.SumoState = [int]'0'
$SumoController.BaseDir = $PSScriptRoot
$SumoController.PSLog = "$($PSScriptRoot)\logs\SUMO-Controller.log"
$SumoController.WZCsv = "$($SumoController.BaseDir)\data\TempWZ-Sumo.csv"
$SumoController.WWWroot = "C:\inetpub\wwwroot"
$SumoController.StatHTML = "$($SumoController.WWWroot)\index.html"
$SumoController.SumoHost = "sumo-pj.mik"
$SumoController.SumoURL = ("http://" + $SumoController.SumoHost)
$SumoController.SumoON = ($SumoController.SumoURL + "/SUMO=ON")
$SumoController.SumoOFF = ($SumoController.SumoURL + "/SUMO=OFF")
$SumoController.SumoResponseOn = "SUMO state is now: On"
$SumoController.SumoResponseOff = "SUMO state is now: Off"
# Timeout Value for Invoke-Webrequest calls (seconds)
$SumoController.WebReqTimeout = [int]'15'
# Minimum Runtime for SUMO in Hours
$SumoController.MinRuntime = [single]'1.5'
#endregion


$Runspace = [Runspacefactory]::CreateRunspace()
$Runspace.Open()
$Runspace.SessionStateProxy.SetVariable('SumoSettings',$SumoSettings)
$Runspace.SessionStateProxy.SetVariable('SumoController',$SumoController)

$SumoControllerTask = [PowerShell]::Create()
$SumoControllerTask.Runspace = $Runspace

$SumoControllerTask.AddScript(
{
    # Hardcoded Path needed here - for whatever reason
    & C:\scripts\SUMO-Controller\BackendWrapper.ps1
}) | Out-Null

$Handle = $SumoControllerTask.BeginInvoke()
write-output ((get-date).ToString() + ":: Startup.ps1: SumoControllerTask has been started.") | Out-File -append -filepath $SumoController.PSLog

while ($Handle.IsCompleted -eq $false)
{
    Start-Sleep -Seconds 30
}

write-output ((get-date).ToString() + ":: Startup.ps1: SumoControllerTask has ended. Program stopped.") | Out-File -append -filepath $SumoController.PSLog
