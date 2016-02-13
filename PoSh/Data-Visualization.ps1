########## Data Visualization stuff ###########
#### dot-sourced in SUMO-Controller.ps1 #######

# Create Queues
$DatumQ = New-Object System.Collections.Queue
$TempWZQ = New-Object System.Collections.Queue
$RhWZQ = New-Object System.Collections.Queue
$SumoStateQ = New-Object System.Collections.Queue
# Queue length (288 = 1 day)
[int]$QueueSize = (288 * 2)
# Y Axis Min/Max
$ChartTempMin = 18
$ChartTempMax = 26
$ChartRhMin = 10
$ChartRhMax = 90
# Maximum Resolution for X Axis grid
$XAxisGridCount = 24

[void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[Void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms.Datavisualization")


$chart = New-Object System.Windows.Forms.Datavisualization.charting.chart
$chart.width = 1920
$chart.Height = 1080

[Void]$chart.Titles.Add("Temperatur Wohnzimmer")
$chart.Titles[0].Font = "Arial,14pt"
$chart.Titles[0].Alignment = "topCenter"
$chart.BackColor = [System.Drawing.Color]::White


$TempArea = New-Object System.windows.Forms.Datavisualization.charting.chartArea


$TempArea.Name = "Temp"
$TempArea.AxisX.Title = "Datum"
$TempArea.AxisY.Title = "Temperatur WZ [°C]"
$TempArea.AxisY2.Title = "rel. Luftfeuchtigkeit [%]"
$TempArea.AxisX.TitleFont = "Arial,13pt"
$TempArea.AxisY.TitleFont = "Arial,13pt"
$TempArea.AxisY.TitleForeColor = [System.Drawing.Color]::Red
$TempArea.AxisY.LabelStyle.ForeColor = [System.Drawing.Color]::Red
$TempArea.AxisY2.TitleFont = "Arial,13pt"
$TempArea.AxisY2.TitleForeColor = [System.Drawing.Color]::Blue
$TempArea.AxisY2.Enabled = [System.Windows.Forms.DataVisualization.Charting.AxisEnabled]::True
$TempArea.AxisY2.LabelStyle.Enabled = $true
$TempArea.AxisY2.LabelStyle.ForeColor = [System.Drawing.Color]::Blue
$TempArea.AxisY2.MajorGrid.Enabled = $false
$TempArea.AxisY.Minimum = $ChartTempMin
$TempArea.AxisY.Maximum = $ChartTempMax
$TempArea.AxisY2.Minimum = $ChartRhMin
$TempArea.AxisY2.Maximum = $ChartRhMax
$TempArea.AxisY.Interval = 1
$TempArea.AxisY2.Interval = 10
$TempArea.AxisX.Interval = [Int]($QueueSize / $XAxisGridCount)
$chart.chartAreas.Add($TempArea)

#Legend
$legend = New-Object system.Windows.Forms.DataVisualization.Charting.Legend
$legend.name = "Legende"
$chart.Legends.Add($legend)


# data series  
[void]$chart.Series.Add("Temperatur")  
$chart.Series["Temperatur"].ChartType = "Line"  
$chart.Series["Temperatur"].BorderWidth = 3
$chart.Series["Temperatur"].IsVisibleInLegend = $true  
$chart.Series["Temperatur"].chartarea = "Temp"  
$chart.Series["Temperatur"].Legend = "Legende"  
$chart.Series["Temperatur"].color = [System.Drawing.Color]::Red

[void]$chart.Series.Add("SUMO Status")
$chart.Series["SUMO Status"].ChartType = "Line"  
$chart.Series["SUMO Status"].BorderWidth = 2
$chart.Series["SUMO Status"].IsVisibleInLegend = $true  
$chart.Series["SUMO Status"].chartarea = "Temp"  
$chart.Series["SUMO Status"].Legend = "Legende"  
$chart.Series["SUMO Status"].color = [System.Drawing.Color]::Green

[void]$chart.Series.Add("RH")
$chart.Series["RH"].ChartType = "Line"  
$chart.Series["RH"].BorderWidth = 3
$chart.Series["RH"].IsVisibleInLegend = $true  
$chart.Series["RH"].chartarea = "Temp"  
$chart.Series["RH"].Legend = "Legende"  
$chart.Series["RH"].color = [System.Drawing.Color]::Blue
$chart.Series["RH"].YAxisType = [System.Windows.Forms.DataVisualization.Charting.AxisType]::Secondary
