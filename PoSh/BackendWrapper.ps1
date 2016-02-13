# Sumo-Controller Backend wrapper
$PSLogFile = "C:\scripts\SUMO-Controller\logs\SUMO-Controller.log" 

write-output ((get-date).ToString() + ":: BackendWrapper: Starting..") | Out-File -append -filepath $PSLogFile

try
{
    write-output ((get-date).ToString() + ":: BackendWrapper: Launching SUMO-Controller-MQTT.ps1..") | Out-File -append -filepath $PSLogFile
    &  C:\scripts\SUMO-Controller\SUMO-Controller-MQTT.ps1
}
catch
{
    # Caught exception in main script, starting failsafe mode
    # write exception to log
    write-output ((get-date).ToString() + ":: BackendWrapper: SUMO-Controller-MQTT.ps1 Exception thrown: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) | Out-File -append -filepath $PSLogFile
    try
    {
        write-output ((get-date).ToString() + ":: BackendWrapper: Launching SUMO-Failsafe.ps1..") | Out-File -append -filepath $PSLogFile
        & C:\Scripts\SUMO-Controller\SUMO-Failsafe.ps1
    }
    catch
    {
        write-output ((get-date).ToString() + ":: BackendWrapper: SUMO-Failsafe.ps1 Exception thrown: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) | Out-File -append -filepath $PSLogFile
        if ($SumoController) { $SumoController.State = 'FAILED' }
    }
}
