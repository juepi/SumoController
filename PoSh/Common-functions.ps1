########## Common Functions for SUMO-Controller #############
##### requires global Variables from Controller script! #####
##### Dot-Sourcing is required! #########


function VerifySensorVal([Single]$Val,[Single]$Min,[Single]$Max)
{
    # Verify if Sensor Value is between min and max
    if ( ($Val -ge $Min) -and ($Val -le $Max) )
    {
        return $true
    }
    else
    {
        return $false
    }
}

function Get-MqttTopic ([String]$Topic)
{
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $MQTT.MosqPub
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($MQTT.Topic_Test) -m ok -r")
    $pubproc = New-Object System.Diagnostics.Process
    $pubproc.StartInfo = $pinfo
    # Make sure broker is reachable by publishing to test topic
    $pubproc.Start() | Out-Null
    $pubproc.WaitForExit()
    if ( $pubproc.ExitCode -ne 0 )
    {
        # Broker not reachable
        return "ErrNoBroker"
    }
    # Subscribe to MQTT Topic and get most recent (retained) value
    $pinfo.FileName = $MQTT.MosqSub
    $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($Topic) -C 1")
    $subproc = New-Object System.Diagnostics.Process
    $subproc.StartInfo = $pinfo
    $subproc.Start() | Out-Null
    # wait 1 sec for a result
    if ( ! $subproc.WaitForExit(1000) ) 
    {
        # topic / value probably doesn't exit
        try { $subproc.kill() } catch {}
        return "nan"
    }
    return ($subproc.StandardOutput.ReadToEnd()).Trim()
}


function Set-MqttTopic ([String]$Topic,[String]$Value,[switch]$Retain)
{
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $MQTT.MosqPub
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($MQTT.Topic_Test) -m ok -r")
    $pubproc = New-Object System.Diagnostics.Process
    $pubproc.StartInfo = $pinfo
    # Make sure broker is reachable by publishing to test topic
    $pubproc.Start() | Out-Null
    $pubproc.WaitForExit()
    if ( $pubproc.ExitCode -ne 0 )
    {
        # Broker not reachable
        return $false
    }

    # Publish to MQTT Topic
    if ($Retain)
    {
        $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($Topic) -m `"$($Value.ToString())`" -r")
    }
    else
    {
        $pinfo.Arguments = ("-h $($MQTT.Broker) -p $($MQTT.Port) -i $($MQTT.ClientID) -t $($Topic) -m `"$($Value.ToString())`"")
    }
    $pubproc.StartInfo = $pinfo
    $pubproc.Start() | Out-Null
    $pubproc.WaitForExit()    
    if ( $pubproc.ExitCode -ne 0 )
    {
        # Broker not reachable
        return $false
    }
    return $true
}


function Get-SumoState ()
{
    #check if SUMO is reachable first.
    $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
    if ($PingSumo.count -lt 2)
    {
        # wait some seconds and retry - just to be sure
        Start-Sleep -Seconds 3
        $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
        if ($PingSumo.count -lt 2)
        {
            #SUMO is unreachable
            return 2
        }
    }
    try { $SumoResponse = Invoke-WebRequest -URI $SumoController.SumoURL -TimeoutSec $SumoController.WebReqTimeout }
    catch { return 2 }
    $CurrentState = ($SumoResponse.AllElements.innerText[1])
    if ($CurrentState -match $SumoController.SumoResponseOn) { return 1 }
    elseif ($CurrentState -match $SumoController.SumoResponseOff) { return 0 }
    return 2
}


function Set-SumoState([int]$State)
{
    #check if SUMO is reachable first.
    $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
    if ($PingSumo.count -lt 2)
    {
        # wait some seconds and retry - just to be sure
        Start-Sleep -Seconds 3
        $PingSumo = Test-Connection -ComputerName $SumoController.SumoHost -Count 2 -ErrorAction SilentlyContinue
        if ($PingSumo.count -lt 2)
        {
            #SUMO is unreachable
            return $false
        }
    }
    switch ($State)
        {
            1
            {
                try { Invoke-WebRequest -URI $SumoController.SumoON -TimeoutSec $SumoController.WebReqTimeout | Out-Null }
                catch
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: Invoke-WebRequest failed to Set SUMO State 1; Exception Message: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) | Out-File -append -filepath $SumoController.PSLog
                    #return $false
                }
                Start-Sleep -Milliseconds 500
                [int]$tempState = Get-SumoState
                if ($tempState -ne "1")
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: failed to set State to 1, Get-SumoState returned " + $tempState) | Out-File -append -filepath $SumoController.PSLog
                    return $false
                }
            }
            0
            {
                try { Invoke-WebRequest -URI $SumoController.SumoOFF -TimeoutSec $SumoController.WebReqTimeout | Out-Null }
                catch
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: Invoke-WebRequest failed to Set SUMO State 0; Exception Message: " + ($_.Exception.Message.ToString() -replace "`t|`n|`r"," ")) | Out-File -append -filepath $SumoController.PSLog
                    #return $false
                }
                Start-Sleep -Milliseconds 500
                [int]$tempState = Get-SumoState
                if ($tempState -ne "0")
                {
                    # Log errors
                    write-output ((get-date).ToString() + ":: Set-SumoState: failed to set State to 1, Get-SumoState returned " + $tempState) | Out-File -append -filepath $SumoController.PSLog
                    return $false
                }
            }
            default
            {
                return $false
            }
        }
    return $true
}


function Send-Email ([String]$Type,[String]$Message,[String]$AttachChart='no',[String]$Priority='normal')
{
    $MailSubject = ($Mail.Subject + $Type)
    $MailCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Mail.User,(ConvertTo-SecureString $Mail.Pass -AsPlainText -Force)
    try
    {
        switch ($AttachChart)
        {
            no
            {
                Send-MailMessage -To $Mail.Dest -From $Mail.Source -Subject $MailSubject -Body ($Mail.Text + $Message) -Priority $Priority -SmtpServer $Mail.Srv -Port $Mail.Port -Encoding ([System.Text.Encoding]::UTF8) -Credential $MailCred
            }
            yes
            {
                Send-MailMessage -To $Mail.Dest -From $Mail.Source -Subject $MailSubject -Body ($Mail.Text + $Message) -Priority $Priority -Attachments $ChartFile -SmtpServer $Mail.Srv -Port $Mail.Port -Encoding ([System.Text.Encoding]::UTF8) -Credential $MailCred
            }
            default
            {
                return $false
            }
        }
    }
    catch
    {
        return $false
    }
    return $true
}


function WaitUntilFull5Minutes ()
{
    # Function will sleep until the next full 5 minutes (00:00,00:05,00:10,...)
    $gt = Get-Date -Second 0
    do {Start-Sleep -Seconds 1} until ((Get-Date) -ge ($gt.addminutes(5-($gt.minute % 5))))
    return $true
}


Function SendTo-LogStash ([string]$JsonString)
{ 
    if ($JsonString)
    {
        try
        {
            # Connect to local LogStash Service on TCP Port 5544 and send JSON string
            $Socket = New-Object System.Net.Sockets.TCPClient(127.0.0.1,5544)
            $Stream = $Socket.GetStream()
            $Writer = New-Object System.IO.StreamWriter($Stream)
            $Writer.WriteLine($JsonString)
            $Writer.Flush()
            $Stream.Close()
            $Socket.Close()
        }
        catch
        {
            return $false
        }
    }
    else
    {
        # No String parameter given
        return $false
    }
    return $true
}


function CreateStatusHtml ([string] $OutFile)
{
    if (! $OutFile)
    {
        return $false
    }
    # Create dynamic content
    # Backend Controller Script Status
    if ($SumoController.State -eq "Running")
    {
        $StatusColor = 'green'
    }
    else
    {
        $StatusColor = 'red'
    }
    # SUMO Status
    switch ($SumoController.SumoState)
    {
        0 { $SumoStatus = "<span style=`"color: red;`">OFF</span>" }
        1 { $SumoStatus = "<span style=`"color: green;`">ON</span>" }
        2 { $SumoStatus = "<span style=`"color: red;`">FAILURE</span>" }
        default { $SumoStatus = "<span style=`"color: red;`">UNKNOWN</span>" }
    }
    # get last 30min of Temp-WZ.mik Sensordata
    if (Test-Path $SumoController.WZCsv)
    {
        $SensData=(gc $SumoController.WZCsv)[0 .. -6] | ConvertFrom-Csv -Delimiter ";"
    }

    # get latest error Messages from PSLogfile
    $PSLogData = @()
    if (Test-Path $SumoController.PSLog)
    {
        $PSLogData = (Get-Content $SumoController.PSLog -Delimiter "`r`n" -Tail 10 -Encoding UTF8).Replace("`r`n","<br>`r`n")
    }

    # Convert SUMO Settings to HTML
    $SumoConfig = [PSCustomObject]$SumoSettings | ConvertTo-Html -As List -Fragment

    # Prepare HTML
    $IndexTitle = 'Sumo-Controller WebStatus'
    $IndexHeader = "<style>TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}TH{border-width: 1px;padding: 0px;border-style: solid;border-color: black;}TD{border-width: 1px;padding: 0px;border-style: solid;border-color: black;}</style>"
    $IndexPreTable = "<h2>Sumo Controller Status</h2>`n"
    $IndexPreTable += "<h4>Sumo Controller Backend State: <span style=`"color: $($StatusColor);`">$($SumoController.State)</span></h4>`n"
    $IndexPreTable += "<h4>SUMO Oven Status: $($SumoStatus)</h4>`n"
    if ($SumoController.State -eq 'Running')
    {
        $IndexPreTable += "<a href=`"/IndoorWZChart.png`"><img style=`"border: 2px solid ; width: 640px; height: 360px;`" alt=`"IndoorWZChart`" src=`"/IndoorWZChart.png`" align=`"center`"></a><br>`n"
    }
    $IndexPreTable += "<br><h4>Most recent Temp-WZ sensor data:</h4>`n"
    $IndexPostTable = "<br><br><h4>Current SUMO Controller config:</h4>`n"
    $IndexPostTable += $SumoConfig
    $IndexPostTable += "<br><a href=`"/config/`">Configure SUMO Controller settings</a>"
    $IndexPostTable += "<br><br><h4>Most recent Log messages:</h4>`n"
    $IndexPostTable += "<span style=`"font-family: Courier New,Courier,monospace;`">"
    $IndexPostTable += $PSLogData
    $IndexPostTable += "<br><br><small>Output generated on: $((Get-Date).ToString())</small></span>"

    # Create HTML
    try
    {
        if ($SensData)
        {
            $SensData | ConvertTo-Html -Head $IndexHeader -Title $IndexTitle -PreContent $IndexPreTable -PostContent $IndexPostTable | Out-File -Force -FilePath $OutFile
        }
        else
        {
            Write-Output " " | ConvertTo-Html -Head $IndexHeader -Title $IndexTitle -PreContent $IndexPreTable -PostContent $IndexPostTable | Out-File -Force -FilePath $OutFile
        }
    }
    catch
    {
        # something went wrong
        return $false
    }
    return $true
}
