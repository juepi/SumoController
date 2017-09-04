################################# SUMO Controller Configuration ###################################
### Author: jpichlbauer
### Info: Configuration will be loaded by "Startup.ps1"
###       Synchronized Collections are used to be able to adopt SumoSettings
###       at runtime by Startup.ps1 (in this case by using MQTT Topics configured with FHEM)
###################################################################################################

#SUMO Controller User Settings
$SumoSettings = [HashTable]::Synchronized(@{})
# Force Weekend or Workday (forced Workday overrules forced weekend)
$SumoSettings.ForceWeekend = [bool]$false
$SumoSettings.ForceWorkday = [bool]$false

# Temperature Thresholds
$SumoSettings.DayStartHour = [Int]'15'
$SumoSettings.DayEndHour = [Int]'21'
$SumoSettings.WeekendDayStartHour = [Int]'7'
$SumoSettings.WeekendDayEndHour = [Int]'21'
$SumoSettings.MinNightTemp = [Single]'18'
$SumoSettings.MaxNightTemp = [Single]'21'
$SumoSettings.MinDayTemp = [Single]'20.8'
$SumoSettings.MaxDayTemp = [Single]'22.5'


# SumoController System settings
$SumoController = [HashTable]::Synchronized(@{})
$SumoController.State = 'Stopped'
$SumoController.Request = 'Run'
$SumoController.SumoState = [int]'0'
$SumoController.BaseDir = $PSScriptRoot
$SumoController.PSLog = "$($SumoController.BaseDir)\logs\SUMO-Controller.log"
$SumoController.WZCsv = "$($SumoController.BaseDir)\data\TempWZ-Sumo.csv"
$SumoController.HolidaysICS = "$($SumoController.BaseDir)\data\Feiertage-AT.ics"
$SumoController.SumoHost = "sumo.domain.tld"
$SumoController.SumoURL = ("http://" + $SumoController.SumoHost)
$SumoController.SumoON = ($SumoController.SumoURL + "/SUMO=ON")
$SumoController.SumoOFF = ($SumoController.SumoURL + "/SUMO=OFF")
$SumoController.SumoResponseOn = "SUMO state is now: On"
$SumoController.SumoResponseOff = "SUMO state is now: Off"
# ATTENTION: Simulate must be set to $false to actually set SUMO actions!
$SumoController.Simulate = $false
# Timeout Value for Invoke-Webrequest calls (seconds)
$SumoController.WebReqTimeout = [int]'15'
# Minimum Runtime for SUMO in Hours
$SumoController.MinRuntime = [single]'1.5'
#Maximum Age for Sensor Values in Minutes
$SumoController.SensMaxAge = [int]'30'
#Ignore SUMO state change requests for X times (i.e. while venting room)
# Note: Main lop runs every 5 minutes, so state change will be ignored fox X * 5min
$SumoController.IgnoreStateChangeReq = [int]'2'
#Send Info Mails on oven status change
$SumoController.SendInfoMail = $false


#region Mail Settings
$Mail = [HashTable]::Synchronized(@{})
$Mail.Source="sender@domain.tld"
$Mail.Dest="recipient@domain.tld"
$Mail.Subject="Sumo-Controller "
$Mail.Text="SUMO Controller meldet:`n`n"
$Mail.Srv="smtp.server.tld"
$Mail.Port="25"
$Mail.User="mailuser"
$Mail.Pass = "mailpass"
#endregion


#region MQTT Settings
$MQTT = [HashTable]::Synchronized(@{})
$MQTT.MosqSub = "$($env:MOSQUITTO_DIR)\mosquitto_sub.exe"
$MQTT.MosqPub = "$($env:MOSQUITTO_DIR)\mosquitto_pub.exe"
$MQTT.Broker = 'broker.hostname.tld'
$MQTT.Port = [int]'1883'
$MQTT.ClientID = 'SumoController'
$MQTT.Topic_Test = 'HB7/SumoController/Test'
$MQTT.Topic_WZ_Temp = 'HB7/Indoor/WZ/Temp'
$MQTT.Topic_WZ_RH = 'HB7/Indoor/WZ/RH'
$MQTT.Topic_WZ_Sumo = 'HB7/Indoor/WZ/Sumo'
$MQTT.Topic_WZ_Status = 'HB7/Indoor/WZ/Status'
$MQTT.VAL_StatusSensorDead = 'SensorDead'
$MQTT.FhemIntToOnOff = @("off","on")
$MQTT.T_FHEM_SumoState = 'HB7/fhem/Sumo/State'
$MQTT.T_FHEM_ForceWorkday = 'HB7/fhem/Sumo/ForceWD'
$MQTT.T_FHEM_ForceWeekend = 'HB7/fhem/Sumo/ForceWE'
$MQTT.T_FHEM_MinDayTemp = 'HB7/fhem/Sumo/MinDayTemp'
$MQTT.T_FHEM_MinNightTemp = 'HB7/fhem/Sumo/MinNightTemp'
$MQTT.T_FHEM_MaxDayTemp = 'HB7/fhem/Sumo/MaxDayTemp'
$MQTT.T_FHEM_MaxNightTemp = 'HB7/fhem/Sumo/MaxNightTemp'
$MQTT.T_FHEM_DayStartHour = 'HB7/fhem/Sumo/DayStartHour'
$MQTT.T_FHEM_DayEndHour = 'HB7/fhem/Sumo/DayEndHour'
$MQTT.T_FHEM_WeekendDayStartHour = 'HB7/fhem/Sumo/WeDayStartHour'
$MQTT.T_FHEM_WeekendDayEndHour = 'HB7/fhem/Sumo/WeDayEndHour'
#endregion


#region Plausible Sensor Ranges
$SensorRange = [HashTable]::Synchronized(@{})
$SensorRange.WZTempMin = [int]'10'
$SensorRange.WZTempMax = [int]'40'
$SensorRange.WZRelHumMin = [int]'0'
$SensorRange.WZRelHumMax = [int]'100'
#endregion


#region Settings for Syncing Web Frontend changes (FHEM / MQTT) to backend
# Local hashtable only used by startup.ps1
$Startup = [HashTable] @{}
# min/max Temperatures for plausibility checks
$Startup.MinTemp = [single]'15'
$Startup.MaxTemp = [single]'26'
$Startup.HourValues = @('DayStartHour','DayEndHour','WeekendDayStartHour','WeekendDayEndHour')
$Startup.TempValues = @('MinNightTemp','MaxNightTemp','MinDayTemp','MaxDayTemp')
$Startup.BoolValues = @('ForceWorkday','ForceWeekend')
