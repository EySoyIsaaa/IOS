# iOS Audio Graph

## Grafo actual

```text
Archivo local importado / AVAudioFile
→ AVAudioPlayerNode
→ etapa Epicenter nativa existente en la ruta iOS
→ AVAudioUnitEQ de 31 bandas
→ AVAudioUnitReverb (Reverb)
→ AVAudioUnitReverb (Concert Hall)
→ AVAudioEngine.mainMixerNode
→ hardware output / background audio session
```

Esta rama sigue siendo iOS-only. No usa WebAudio, AudioWorklet ni `HTMLAudioElement`.

## Integración EQ/FX

`NativeAudioEngine` adjunta las unidades una sola vez al inicializar el motor:

1. `AVAudioPlayerNode` para reproducir archivos locales importados.
2. `AVAudioUnitEQ(numberOfBands: 31)` para el EQ gráfico.
3. `AVAudioUnitReverb` con preset `.mediumRoom` para Reverb.
4. `AVAudioUnitReverb` con preset `.largeHall` para Concert Hall.
5. `mainMixerNode` como salida final.

Los cambios de EQ/FX no reconstruyen el grafo; solo actualizan bypass, gain, `globalGain`, `wetDryMix` y trim de salida.

## Bandas EQ

El EQ usa 31 bandas ISO-style: 20 Hz a 20 kHz. Las bandas se configuran como filtros paramétricos de 1/3 de octava y respetan el rango de UI `-12 dB` a `+12 dB`.

## FX

Reverb y Concert Hall pueden activarse juntos. El comportamiento elegido es serial controlado:

```text
EQ → Reverb → Concert Hall → mainMixer
```

Para evitar mezclas agresivas, los amounts `0–100` se mapean a wet/dry máximos limitados (`55%` y `45%`).

## Headroom

El motor calcula headroom cuando hay boosts positivos y/o FX activos:

- `eqNode.globalGain` compensa boosts del EQ.
- `mainMixerNode.outputVolume` aplica trim final compartido.
- El trim total se limita a `12 dB`.

## Funciones preservadas

- Importación manual nativa.
- Biblioteca local iOS.
- Queue/play/pause/seek/stop/next/previous.
- Background playback.
- Now Playing / lock screen / Control Center.
- UI actual de Player, Biblioteca, DSP, EQ, FX y Settings.
