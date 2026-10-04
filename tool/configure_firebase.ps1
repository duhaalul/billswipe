param([Parameter(Mandatory=$true)][string]$GoogleServicesPath)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$data=Get-Content -LiteralPath $GoogleServicesPath -Raw | ConvertFrom-Json
$client=@($data.client | Where-Object { $_.client_info.android_client_info.package_name -eq 'com.billswipe.billswipe' })[0]
if($null -eq $client) { throw 'File bukan untuk package com.billswipe.billswipe' }
$configPath=Join-Path $projectRoot 'config.local.json'
$config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
$config['FIREBASE_API_KEY']=$client.api_key[0].current_key
$config['FIREBASE_APP_ID']=$client.client_info.mobilesdk_app_id
$config['FIREBASE_SENDER_ID']=[string]$data.project_info.project_number
$config['FIREBASE_PROJECT_ID']=$data.project_info.project_id
$config | ConvertTo-Json | Set-Content -LiteralPath $configPath
$values=@{google_app_id=$config.FIREBASE_APP_ID; gcm_defaultSenderId=$config.FIREBASE_SENDER_ID; google_api_key=$config.FIREBASE_API_KEY; project_id=$config.FIREBASE_PROJECT_ID}
if($data.project_info.storage_bucket) { $values['google_storage_bucket']=$data.project_info.storage_bucket }
$xml='<resources>' + (($values.GetEnumerator() | ForEach-Object { '<string name="'+$_.Key+'" translatable="false">'+[System.Security.SecurityElement]::Escape([string]$_.Value)+'</string>' }) -join "`n") + '</resources>'
Set-Content -LiteralPath (Join-Path $projectRoot 'android/app/src/main/res/values/firebase.xml') -Value $xml
Write-Output 'Konfigurasi Firebase client dan resource Android berhasil dibuat. Build ulang aplikasi.'
