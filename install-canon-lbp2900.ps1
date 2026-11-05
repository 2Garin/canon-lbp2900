# Canon LBP2900 — установка сетевого принтера через NAS
# Запускать в Windows PowerShell от имени администратора

$printerName = "Canon LBP2900 (NAS)"
$driverName  = "Microsoft PS Class Driver"
$portName    = "Canon_LBP2900_NAS_LPR"
$serverIP    = "192.168.23.10"
$serverPort  = 1515
$queueName   = "Canon_LBP2900"

$ErrorActionPreference = "Stop"

# 1. Проверяем доступность сервера
Write-Host "Проверка доступности сервера..."

if (-not (Test-NetConnection $serverIP -Port $serverPort -InformationLevel Quiet)) {
    throw "Сервер $serverIP недоступен на TCP-порту $serverPort"
}

# 2. Включаем поддержку LPR
Write-Host "Проверка поддержки LPR..."

$feature = Get-WindowsOptionalFeature `
    -Online `
    -FeatureName Printing-Foundation-LPRPortMonitor

if ($feature.State -ne "Enabled") {
    $result = Enable-WindowsOptionalFeature `
        -Online `
        -FeatureName Printing-Foundation-LPRPortMonitor `
        -All `
        -NoRestart

    if ($result.RestartNeeded) {
        throw "Необходимо перезагрузить Windows и повторить запуск скрипта."
    }
}

# 3. Проверяем наличие PostScript-драйвера
Write-Host "Проверка драйвера..."

$driver = Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue

if (-not $driver) {
    Write-Host "Драйвер '$driverName' отсутствует. Пробуем установить..."
    try {
        Add-PrinterDriver -Name $driverName -ErrorAction Stop
    } catch {
        throw "Не удалось установить драйвер '$driverName': $($_.Exception.Message). Установите драйвер вручную и повторите запуск."
    }

    $driver = Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue
    if (-not $driver) {
        throw "После установки драйвер '$driverName' не обнаружен."
    }
    Write-Host "Драйвер '$driverName' установлен."
}

# 4. Создаём LPR-порт
Write-Host "Настройка LPR-порта..."

$port = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue

if (-not $port) {
    Add-PrinterPort `
        -Name $portName `
        -LprHostAddress $serverIP `
        -LprQueueName $queueName `
        -LprByteCounting
} else {
    if ($port.Protocol -ne "LPR" -or
        $port.PrinterHostAddress -ne $serverIP -or
        $port.LprQueueName -ne $queueName) {
        throw "Порт '$portName' уже существует, но его параметры отличаются."
    }
}

# 5. Изменяем TCP-порт с 515 на 1515
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports\$portName"

$currentPort = (Get-ItemProperty -Path $regPath).PortNumber

if ($currentPort -ne $serverPort) {
    Set-ItemProperty `
        -Path $regPath `
        -Name "PortNumber" `
        -Value $serverPort

    Restart-Service Spooler
}

# 6. Создаём принтер
Write-Host "Добавление принтера..."

$printer = Get-Printer -Name $printerName -ErrorAction SilentlyContinue

if (-not $printer) {
    Add-Printer `
        -Name $printerName `
        -DriverName $driverName `
        -PortName $portName
} else {
    if ($printer.DriverName -ne $driverName -or
        $printer.PortName -ne $portName) {
        throw "Принтер '$printerName' уже существует с другими параметрами."
    }
}

# 7. Проверяем результат
Write-Host ""
Write-Host "Принтер настроен:" -ForegroundColor Green

Get-Printer -Name $printerName |
    Format-List Name, DriverName, PortName, PrinterStatus

Get-PrinterPort -Name $portName |
    Format-List Name, Protocol, PrinterHostAddress, PortNumber, LprQueueName

