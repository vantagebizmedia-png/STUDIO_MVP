# SCENE_BUILDER_DIAGNOSIS

## Diagnóstico resumido

El builder actual **no usa el guion como fuente primaria de cantidad de escenas**.

La secuencia observada en 	ools/apply_scene_builder_v03.ps1 es:

1. leer udio_clips
2. calcular 	otalAudioMs
3. calcular desiredScenes con Get-DynamicSceneCount
4. construir/forzar scenes_v03 con Ensure-Scenes
5. repartir duraciones sintéticas con New-Durations
6. recién después distribuir el texto del guion con Build-SceneTexts

Esto implica que hoy el sistema está orientado a:
- segmentación temporal determinista
- no a segmentación guiada primariamente por guion

## Evidencia clave

### Parámetros por defecto
0001: param(
0002:   [Parameter(Mandatory=$false)][string]$WorkspaceRoot,
0003:   [Parameter(Mandatory=$false)][string]$PackDir,
0004: 
0005:   [int]$MinScenes = 8,
0006:   [int]$MaxScenes = 40,
0007:   [int]$TargetSceneSec = 6,
0008: 
0009:   [int]$MinSceneSec = 4,
0010:   [int]$MaxSceneSec = 8,
0011: 
0012:   [int]$Seed = 123,
0013:   [switch]$Force,
0014: 
0015:   [switch]$SkipPixabay,
0016:   [switch]$SkipEnrich

### Cálculo de cantidad dinámica de escenas
0218: function Get-DynamicSceneCount {
0219:   param(
0220:     [int]$TotalAudioMs,
0221:     [int]$ConfiguredMinScenes,
0222:     [int]$ConfiguredMaxScenes,
0223:     [int]$SceneTargetSec,
0224:     [int]$SceneMinSec,
0225:     [int]$SceneMaxSec
0226:   )
0227: 
0228:   $targetMs   = [Math]::Max(1000, ($SceneTargetSec * 1000))
0229:   $minSceneMs = [Math]::Max(1000, ($SceneMinSec * 1000))
0230:   $maxSceneMs = [Math]::Max($minSceneMs, ($SceneMaxSec * 1000))
0231: 
0232:   $targetCount      = [int][Math]::Round($TotalAudioMs / [double]$targetMs)
0233:   $minByMaxDuration = [int][Math]::Ceiling($TotalAudioMs / [double]$maxSceneMs)
0234:   $maxByMinDuration = [int][Math]::Floor($TotalAudioMs / [double]$minSceneMs)
0235: 
0236:   if ($targetCount -lt 1) { $targetCount = 1 }
0237:   if ($minByMaxDuration -lt 1) { $minByMaxDuration = 1 }
0238:   if ($maxByMinDuration -lt 1) { $maxByMinDuration = 1 }
0239: 
0240:   $n = $targetCount
0241:   if ($n -lt $ConfiguredMinScenes) { $n = $ConfiguredMinScenes }
0242:   if ($n -lt $minByMaxDuration)    { $n = $minByMaxDuration }
0243:   if ($n -gt $ConfiguredMaxScenes) { $n = $ConfiguredMaxScenes }
0244:   if ($n -gt $maxByMinDuration)    { $n = $maxByMinDuration }
0245:   if ($n -lt 1) { $n = 1 }
0246: 
0247:   return $n

### Reparto sintético de duraciones
0250: function New-Durations {
0251:   param(
0252:     [int]$SceneCount,
0253:     [int]$TotalAudioMs,
0254:     [int]$SceneMinSec,
0255:     [int]$SceneMaxSec,
0256:     [int]$SeedValue
0257:   )
0258: 
0259:   $minMs = $SceneMinSec * 1000
0260:   $maxMs = $SceneMaxSec * 1000
0261: 
0262:   if ($SceneCount -lt 1) { return @() }
0263: 
0264:   $weights = @()
0265:   for ($i = 1; $i -le $SceneCount; $i++) {
0266:     $w = 100
0267: 
0268:     if ($i -eq 1) {
0269:       $w = 75
0270:     }
0271:     elseif ($i -eq $SceneCount) {
0272:       $w = 115
0273:     }
0274:     else {
0275:       $w = 90 + ((($SeedValue + $i) % 7) * 6)
0276:     }
0277: 
0278:     $weights += $w
0279:   }
0280: 
0281:   $weightSum = (@($weights) | Measure-Object -Sum).Sum
0282:   if (-not $weightSum -or $weightSum -le 0) {
0283:     throw "weightSum inválido en New-Durations"
0284:   }
0285: 
0286:   $durations = @()
0287:   $assigned = 0
0288: 
0289:   for ($i = 0; $i -lt $SceneCount; $i++) {
0290:     if ($i -lt ($SceneCount - 1)) {
0291:       $dur = [int][Math]::Floor(($TotalAudioMs * $weights[$i]) / $weightSum)
0292:       if ($dur -lt $minMs) { $dur = $minMs }
0293:       if ($dur -gt $maxMs) { $dur = $maxMs }
0294:       $durations += $dur
0295:       $assigned += $dur
0296:     }
0297:     else {
0298:       $dur = $TotalAudioMs - $assigned
0299:       if ($dur -lt $minMs) { $dur = $minMs }
0300:       if ($dur -gt $maxMs) { $dur = $maxMs }
0301:       $durations += $dur
0302:     }
0303:   }
0304: 
0305:   $sumDur = (@($durations) | Measure-Object -Sum).Sum
0306:   $guard = 0
0307: 
0308:   while ($sumDur -ne $TotalAudioMs -and $guard -lt 10000) {
0309:     $delta = $TotalAudioMs - $sumDur
0310: 
0311:     if ($delta -gt 0) {
0312:       for ($i = 0; $i -lt $SceneCount -and $delta -gt 0; $i++) {
0313:         if ($durations[$i] -lt $maxMs) {
0314:           $durations[$i]++
0315:           $delta--
0316:         }
0317:       }
0318:     }
0319:     else {
0320:       for ($i = $SceneCount - 1; $i -ge 0 -and $delta -lt 0; $i--) {
0321:         if ($durations[$i] -gt $minMs) {
0322:           $durations[$i]--
0323:           $delta++
0324:         }
0325:       }
0326:     }
0327: 
0328:     $sumDur = (@($durations) | Measure-Object -Sum).Sum
0329:     $guard++
0330:   }
0331: 
0332:   if ((@($durations) | Measure-Object -Sum).Sum -ne $TotalAudioMs) {
0333:     throw "No se pudo ajustar durations exactamente al total"
0334:   }
0335: 
0336:   return @($durations)

### Construcción y asignación de start_ms / end_ms
0339: function Ensure-Scenes {
0340:   param(
0341:     $ManifestObj,
0342:     [int]$SceneCount,
0343:     [int]$TotalAudioMs,
0344:     [int]$SceneMinSec,
0345:     [int]$SceneMaxSec,
0346:     [int]$SeedValue
0347:   )
0348: 
0349:   $sc = @()
0350:   if ($ManifestObj.scenes_v03) { $sc = @($ManifestObj.scenes_v03) }
0351: 
0352:   if (@($sc).Count -gt $SceneCount) {
0353:     $sc = @($sc[0..($SceneCount - 1)])
0354:   }
0355: 
0356:   if (@($sc).Count -lt $SceneCount) {
0357:     for ($i = @($sc).Count; $i -lt $SceneCount; $i++) {
0358:       $obj = [pscustomobject]@{
0359:         id       = ("scene_{0:000}" -f ($i + 1))
0360:         start_ms = 0
0361:         end_ms   = 0
0362:         text     = ""
0363:         assets   = [pscustomobject]@{
0364:           audio_clip = ""
0365:           image      = @([pscustomobject]@{ path = "" })
0366:         }
0367:       }
0368:       $sc += $obj
0369:     }
0370:   }
0371: 
0372:   $durations = @(New-Durations -SceneCount $SceneCount -TotalAudioMs $TotalAudioMs -SceneMinSec $SceneMinSec -SceneMaxSec $SceneMaxSec -SeedValue $SeedValue)
0373:   $cur = 0
0374: 
0375:   for ($i = 0; $i -lt $SceneCount; $i++) {
0376:     $sceneObj = $sc[$i]
0377: 
0378:     $st = $cur
0379:     $en = $cur + [int]$durations[$i]
0380:     if ($i -eq ($SceneCount - 1)) { $en = $TotalAudioMs }
0381:     $cur = $en
0382: 
0383:     if (-not ($sceneObj.PSObject.Properties.Name -contains "id")) {
0384:       $sceneObj | Add-Member -Force -NotePropertyName id -NotePropertyValue ("scene_{0:000}" -f ($i + 1))
0385:     }
0386:     elseif ([string]::IsNullOrWhiteSpace([string]$sceneObj.id)) {
0387:       $sceneObj.id = ("scene_{0:000}" -f ($i + 1))
0388:     }
0389: 
0390:     if (-not ($sceneObj.PSObject.Properties.Name -contains "text")) {
0391:       $sceneObj | Add-Member -Force -NotePropertyName text -NotePropertyValue ""
0392:     }
0393: 
0394:     if (-not ($sceneObj.PSObject.Properties.Name -contains "assets") -or -not $sceneObj.assets) {
0395:       $sceneObj | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{
0396:         audio_clip = ""
0397:         image      = @([pscustomobject]@{ path = "" })
0398:       })
0399:     }
0400: 
0401:     if (-not ($sceneObj.assets.PSObject.Properties.Name -contains "audio_clip")) {
0402:       $sceneObj.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue ""
0403:     }
0404: 
0405:     if (-not ($sceneObj.assets.PSObject.Properties.Name -contains "image") -or -not $sceneObj.assets.image) {
0406:       $sceneObj.assets | Add-Member -Force -NotePropertyName image -NotePropertyValue @([pscustomobject]@{ path = "" })
0407:     }
0408:     elseif ($sceneObj.assets.image -is [string]) {
0409:       $sceneObj.assets.image = @([pscustomobject]@{ path = [string]$sceneObj.assets.image })
0410:     }
0411: 
0412:     $sceneObj.start_ms = [int]$st
0413:     $sceneObj.end_ms   = [int]$en
0414:     $sceneObj.assets.audio_clip = ("artifacts/audio_s{0:d2}.wav" -f ($i + 1))
0415:   }
0416: 
0417:   $ManifestObj.scenes_v03 = @($sc)

### Lectura de totalAudioMs y cálculo de desiredScenes
0556: }
0557: catch {
0558:   throw "manifest sin artifacts.audio (base audio requerido): $manifest"
0559: }
0560: 
0561: $totalAudioMs = Get-TotalAudioMs -AudioClips $m.audio_clips
0562: 
0563: $scriptText = ""
0564: try {
0565:   if ($m.script) { $scriptText = [string]$m.script }
0566:   elseif ($m.text -and $m.text.script) { $scriptText = [string]$m.text.script }
0567: }
0568: catch {
0569:   $scriptText = ""
0570: }
0571: 
0572: $scriptParts = @(Split-ScriptSentences -Text $scriptText)
0573: 
0574: $desiredScenes = Get-DynamicSceneCount `
0575:   -TotalAudioMs $totalAudioMs `
0576:   -ConfiguredMinScenes $MinScenes `
0577:   -ConfiguredMaxScenes $MaxScenes `
0578:   -SceneTargetSec $TargetSceneSec `
0579:   -SceneMinSec $MinSceneSec `
0580:   -SceneMaxSec $MaxSceneSec

### Aplicación de escenas y reparto posterior del texto del guion
0603: Ensure-Scenes `
0604:   -ManifestObj $m `
0605:   -SceneCount $desiredScenes `
0606:   -TotalAudioMs $totalAudioMs `
0607:   -SceneMinSec $MinSceneSec `
0608:   -SceneMaxSec $MaxSceneSec `
0609:   -SeedValue $Seed
0610: 
0611: if (@($scriptParts).Count -gt 0) {
0612:   $sceneTexts = @(Build-SceneTexts -Parts $scriptParts -SceneCount @($m.scenes_v03).Count)
0613: 
0614:   for ($i = 0; $i -lt @($m.scenes_v03).Count; $i++) {
0615:     $txt = ""
0616:     if ($i -lt @($sceneTexts).Count) { $txt = [string]$sceneTexts[$i] }
0617:     $m.scenes_v03[$i].text = $txt.Trim()
0618:   }

## Conclusión operativa

Con los valores actuales:
- TargetSceneSec = 6
- MinSceneSec = 4
- MaxSceneSec = 8

y con 	otalAudioMs = 180000, el sistema tenderá a producir cerca de:
- 180000 / 6000 = 30 escenas

Por eso el smoke terminó en 30 escenas, aunque la intención funcional del producto sea que:
- el guion defina las escenas
- la duración por escena sea flexible
- la duración total del video dependa del contenido

## Próximo cambio recomendado

No tocar todavía render/handoff.

Próxima intervención:
- reemplazar la política de desiredScenes
- hacer que primero se derive una estructura base desde el guion
- usar la duración total solo para ajustar tiempos, no para decidir primariamente cuántas escenas existen