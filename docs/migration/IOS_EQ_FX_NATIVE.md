# iOS EQ + FX nativos

## Estado de la fase

Esta fase conecta el ecualizador gráfico de 31 bandas y los efectos espaciales actuales a la ruta nativa iOS. No se restauró WebAudio, AudioWorklet ni `HTMLAudioElement`.

## Orden del grafo

```text
AVAudioSourceNode / archivo local importado
→ etapa Epicenter nativa existente / playback nativo iOS
→ AVAudioUnitEQ de 31 bandas
→ AVAudioUnitReverb (Reverb)
→ AVAudioUnitReverb (Concert Hall)
→ AVAudioEngine.mainMixerNode
→ salida de hardware / sesión de background audio
```

La cadena de FX es serial y segura: si Reverb y Concert Hall están activos al mismo tiempo, la señal pasa primero por Reverb y después por Concert Hall. Cada unidad usa `wetDryMix` limitado para evitar mezclas excesivas.

## EQ 31 bandas

Implementación: `AVAudioUnitEQ(numberOfBands: 31)` dentro de `NativeAudioEngine`.

Frecuencias configuradas:

```text
20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
200, 250, 315, 400, 500, 630, 800, 1k, 1.25k, 1.6k,
2k, 2.5k, 3.15k, 4k, 5k, 6.3k, 8k, 10k, 12.5k, 16k, 20k
```

Cada banda usa filtro paramétrico con ancho de 1/3 de octava. El rango se mantiene en el rango de UI existente, `-8 dB` a `+8 dB`; los valores entrantes se clampéan en nativo.

## FX nativos

- Reverb: `AVAudioUnitReverb` con preset `.mediumRoom`.
- Concert Hall: `AVAudioUnitReverb` con preset `.largeHall`.
- `amount` llega desde la UI como `0–100` y se convierte a `wetDryMix` máximo seguro:
  - Reverb: máximo `55%`.
  - Concert Hall: máximo `45%`.

Activar/desactivar durante reproducción solo cambia bypass/wet mix de unidades ya adjuntas al grafo, por lo que no requiere reconstruir el motor ni reprogramar la canción.

## Headroom y clipping

La protección se aplica en dos puntos:

1. `eqNode.globalGain` baja automáticamente cuando hay boosts positivos en el EQ.
2. `mainMixerNode.outputVolume` aplica trim adicional cuando EQ y/o FX están activos.

El trim máximo total es `10 dB`. La fórmula prioriza el boost máximo, la densidad de bandas positivas y el amount de Reverb/Concert Hall. Esto evita clipping obvio con boosts moderados sin ampliar el rango de la UI.

## API soportada

Métodos nuevos o completados en `EpicenterNative`:

- `setEqEnabled({ enabled })`
- `setEqBand({ index, gain })`
- `setEqBands({ gains })`
- `setEqPreset({ name, gains })`
- `resetEq()`
- `setReverbEnabled({ enabled })`
- `setReverbAmount({ amount })`
- `setConcertHallEnabled({ enabled })`
- `setConcertHallAmount({ amount })`

`getPlaybackState()` incluye estado `eq` y `fx` para sincronizar la UI al arrancar.

## Frontend

`useIosNativeAudioProcessor` expone las 31 bandas al visualizador existente y manda cambios al plugin nativo en tiempo real. La vista de FX conserva los controles actuales y ahora envía enable/amount de Reverb y Concert Hall al plugin.

## Limitaciones conocidas

- Reverb y Concert Hall usan unidades nativas AVFoundation. Si se necesita emulación exacta de un hardware concreto, una fase posterior podría portar un DSP propio.
- La validación auditiva final debe hacerse en iPhone físico con canciones importadas, background playback y lock screen controls.

## Prueba en iPhone

1. `pnpm build`
2. `npx cap sync ios`
3. Abrir `ios/App/App.xcworkspace` en Xcode.
4. Instalar en iPhone físico.
5. Importar/reproducir una canción.
6. Activar EQ, mover bandas y probar reset/presets automáticos.
7. Activar Reverb y Concert Hall, mover amount y validar ausencia de crashes al hacer seek/cambiar canción/bloquear pantalla.
