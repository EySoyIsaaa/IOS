# iOS Audio Graph

## Grafo actual de esta fase

```text
Decoded local file (Float32, non-interleaved, prepared outside render)
→ AVAudioSourceNode render block
→ EpicenterDSPBridge.processLeft/right
→ EpicenterDSPCore C++ sample-by-sample
→ AVAudioEngine mainMixerNode
→ hardware output / background audio session
```

## Por qué no se dejó `AVAudioPlayerNode → effect → mainMixer`

`AVAudioPlayerNode` programa buffers/archivos hacia el motor, pero AVFoundation no ofrece un callback de efecto in-place simple entre un `AVAudioPlayerNode` y el mixer sin crear un Audio Unit custom completo. Para esta fase se priorizó:

- fidelidad del algoritmo Epicenter Worklet,
- procesamiento sample-by-sample en C++,
- cero allocations dentro del callback DSP,
- cambios de parámetros en reproducción,
- no reintroducir WebAudio/AudioWorklet ni HTMLAudioElement.

Por eso se usa `AVAudioSourceNode`: el archivo se decodifica a `AVAudioPCMBuffer` fuera del callback y el render block solo copia frames al buffer de salida, llama al bridge y avanza el cursor.

## Reglas de tiempo real

- No hay SQLite en el render block.
- No hay logs por muestra/buffer en el render block.
- El core C++ preasigna `subBuffer` y `deepExtensionBuffer` en `prepare()`.
- Los parámetros del core se leen desde atómicos al inicio del bloque.
- El callback solo accede al buffer PCM ya cargado y al bridge DSP.

## Reset de estado DSP

`NativeAudioEngine.load(track:)` prepara el core con sample rate/channel count del archivo y llama `reset()`. Seek mantiene parámetros y reposiciona el cursor; carga de track/next/previous resetea filtros y envelopes para evitar colas del track anterior.

## Pendiente para fases futuras

No se agregó EQ nativo, Reverb ni Concert Hall en esta fase. Si se implementan después, deben insertarse después del Epicenter o en un pipeline explícito documentado sin modificar el carácter de este port.

## Calibración de profundidad y logging

La calibración de profundidad vive dentro de `EpicenterDSPCore` y no cambia el grafo de audio. El render block sigue siendo:

```text
AVAudioSourceNode render block
→ copia de frames PCM ya decodificados
→ EpicenterDSPBridge.processLeft/right
→ EpicenterDSPCore.process()
→ mainMixerNode
```

Se agregó un log fuera del callback de audio al preparar el nodo:

```text
[iOS Epicenter DSP] depth calibration constants ...
```

Ese log se emite en `configureSourceNode(format:)`, no dentro del loop de render ni por buffer. Los cambios de profundidad mantienen las mismas restricciones de tiempo real: no SQLite, no I/O, no allocations DSP en `process()` y sin logs dentro del callback.

La protección anti-rumble se mantiene con dos etapas: HPF subsónico dedicado en la deep extension a 23 Hz y DC/high-pass final por canal a 28 Hz. Seek, stop y cambio de canción siguen reseteando el estado DSP para evitar que envelopes o filtros de un fragmento anterior dejen rumble residual.
