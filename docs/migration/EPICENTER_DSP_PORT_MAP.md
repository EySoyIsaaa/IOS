# Epicenter DSP Port Map: AudioWorklet → iOS nativo

Fuente de referencia: `client/src/worklets/epicenter-worklet.ts` del baseline histórico `1c7b3af4fc0296c89f30212041e79cd30b772a8b`. En esta rama iOS-only el archivo ya no existe en el árbol actual, pero el port usa ese commit como fuente exacta del algoritmo.

Implementación nativa:

- Core C++ real-time: `plugins/epicenter-native-ios/ios/DSP/EpicenterDSPCore.hpp` y `plugins/epicenter-native-ios/ios/DSP/EpicenterDSPCore.cpp`.
- Bridge Objective-C++ para Swift: `plugins/epicenter-native-ios/ios/DSP/EpicenterDSPBridge.h` y `plugins/epicenter-native-ios/ios/DSP/EpicenterDSPBridge.mm`.
- Integración AVAudioEngine: `plugins/epicenter-native-ios/ios/NativeAudio/NativeAudioEngine.swift`.

## Tabla de mapeo 1:1

| TS/Worklet original | Propósito | Equivalente nativo iOS | Notas de fidelidad |
|---|---|---|---|
| `DENORMAL_FLOOR = 1e-24` | Elimina denormals y valores microscópicos. | `DENORMAL_FLOOR` + `denormalFloor()` en C++. | Igual valor; además protege NaN/Inf en nativo. |
| `TWO_PI` | Cálculo de coeficientes biquad. | `TWO_PI` en C++. | Igual fórmula. |
| `EPICENTER_INTENSITY_HEADROOM = 0.75` | Headroom de intensidad. | Constante C++ igual. | 1:1. |
| `EPICENTER_INTENSITY_MAX_SCALE = 0.65` | Escala máxima efectiva de intensidad. | Constante C++ igual. | 1:1. |
| `EPICENTER_VOLUME_MAX_SCALE = 0.75` | Escala máxima de volumen/output. | Constante C++ igual. | 1:1. |
| `EPICENTER_OUTPUT_TRIM = 0.95` | Trim final antes de clip/DC. | Constante C++ igual. | 1:1. |
| `DEEP_EXTENSION_AMOUNT = 0.18` | Capa adicional de extensión profunda. | Constante C++ igual. | 1:1. |
| `softClip(value)` | Saturación suave de protección. | `softClip(float)` en C++. | Misma ecuación `(x*(27+x²))/(27+9x²)`. |
| `SOFT_CLIP_09` | Normalización del soft clip final. | `SOFT_CLIP_09` en C++. | Igual cálculo. |
| `BiquadFilter` lowpass/highpass/bandpass | Filtros RBJ con estados `x1/x2/y1/y2`. | `epicenter::BiquadFilter`. | Mismos tipos, clamp de frecuencia 10 Hz–0.45×SR y Q 0.2–12. |
| `LowShelfFilter` | Shelf de grave posterior a mezcla. | `epicenter::LowShelfFilter`. | Mismo cookbook de low shelf, Q 0.707, gain 0–10.5 dB. |
| `EnvelopeFollower` | Seguidores attack/release. | `epicenter::EnvelopeFollower`. | Misma ecuación `x + coeff*(value-x)` y coeficientes ms→samples. |
| `parameterDescriptors.sweepFreq` | Sweep 27–63 Hz. | `setEpicenterParams({ sweepFreq })`. | Mismo rango y default 45 Hz. |
| `parameterDescriptors.width` | Width 0–100. | `setEpicenterParams({ width })`. | Mismo rango/default 50. |
| `parameterDescriptors.intensity` | Intensidad 0–100. | `setEpicenterParams({ intensity })`. | Mismo rango/default 100. |
| `parameterDescriptors.balance` | Balance/ruta bass program 0–100. | `setEpicenterParams({ balance })`. | Mismo rango/default 100. |
| `parameterDescriptors.volume` | Salida 0–100. | `setEpicenterParams({ volume })`; alias `output`. | Mismo rango/default 100. |
| `getDerivedFrequencies()` | Deriva detector, crossover, sub y extensión desde sweep/width. | `EpicenterDSPCore::getDerivedFrequencies()`. | Fórmulas copiadas: detector60/80/110, crossover, body, subTop, synth low/high y deepExtension. |
| `StereoChannelState` | Estado persistente por canal. | `ChannelState`. | Conserva filtros de voz, presencia, bass program, body/dip, sub LPF, shelf, DC HPF y voice envelope. |
| `MonoDetectorState` | Estado mono compartido. | `MonoState`. | Conserva bandas 60/80/110, mono LPF, diff HPF, synth HP/LP, deep extension, envelopes, `lastDetector`, `flipState`, `holdSamples`. |
| `computeGate()` | Gate musical contra voz/ausencia de bajo. | `EpicenterDSPCore::computeGate()`. | Misma actividad detector × music score. |
| Bypass `intensity <= 0.01` | Salida limpia. | Bypass cuando `enabled=false` o `intensity<=0.01`. | Añade switch explícito nativo; bypass solo sanea denormals/NaN. |
| Mono detector loop | Detecta bajo dominante L+R y diferencia estéreo. | Primer loop de `processChunk()`. | Mismo orden: mono/diff → bandas ponderadas → envelopes → flip → synth → gate/hold → subBuffer. |
| Deep extension loop | Genera capa subgrave baja protegida. | Segundo loop de `processChunk()`. | Mismo LPF, HPF subsonic 24 Hz, envelope sustain y soft clip. |
| Channel render loop | Recombinación por canal. | Tercer loop de `processChunk()`. | Mismo orden voz limpia → bass program/body/dip → generated sub → shelf → output trim → soft clip → DC blocker. |
| `subBuffer`/`deepExtensionBuffer` | Buffers internos reutilizables. | Vectores preasignados en `prepare()`. | Sin allocations en `process()`; bloques grandes se procesan en chunks. |
| `outputDcHighpass` 32 Hz | Bloqueo DC y subsonic final. | Biquad HPF 32 Hz por canal. | 1:1. |
| `deepExtensionSubsonicHighpass` 24 Hz | Protección subsónica de extensión. | Biquad HPF 24 Hz mono. | 1:1. |

## Orden exacto de procesamiento portado

1. Leer parámetros atómicos una vez por bloque.
2. Si `enabled=false` o `intensity<=0.01`, bypass seguro.
3. Actualizar coeficientes derivados si cambió `sweepFreq` o `width`.
4. Calcular normalizaciones del Worklet: `intensityRawNorm`, `intensityScaledNorm`, `intensityNorm`, `balanceNorm`, `widthNorm`, `volumeGain`.
5. Loop mono detector: mono/diff, bandas ponderadas, detector envelope, gate, flip de media frecuencia y `subBuffer`.
6. Loop deep extension: lowpass profundo, highpass subsónico, sustain envelope y soft clip hacia `deepExtensionBuffer`.
7. Loop por canal: voz limpia/protegida, programa de bajo, sub generado, shelf de graves, trim, soft clip final y DC blocker.
8. Clamp final nativo a `[-1, 1]` como protección de salida iOS.

## Diferencias conocidas

- La ruta iOS usa `enabled` explícito además del bypass por intensidad. El Worklet no tenía ese parámetro porque la UI desconectaba/bypasseaba el nodo.
- El core nativo clampa NaN/Inf y salida final a `[-1,1]`; esto es protección de plataforma y no cambia la intención sonora.
- El AudioWorklet podía recibir buffers arbitrarios y redimensionar `Float32Array`; el core nativo preasigna `8192` frames y procesa chunks para mantener cero allocations en el render.
- El grafo iOS usa `AVAudioSourceNode` con audio decodificado en memoria para poder insertar DSP in-place en tiempo real sin reintroducir WebAudio. La arquitectura está documentada en `IOS_AUDIO_GRAPH.md`.

## Calibración de profundidad subgrave (fase posterior al primer port)

El primer port nativo fue deliberadamente conservador. En escucha comparativa con la ruta WebAudio/Worklet, iOS recuperaba el carácter del efecto pero con menor sensación de subgrave profundo. Esta fase agrega un modo interno de calibración `subDepth` sin exponer UI nueva y sin convertir el algoritmo en un bass boost genérico.

Cambios aplicados en el core C++:

| Área | Valor primer port | Valor calibrado | Motivo | Protección mantenida |
|---|---:|---:|---|---|
| `DEEP_EXTENSION_AMOUNT` | `0.18` | `0.30` | Recupera más energía 30–40 Hz desde la capa derivada, no desde EQ. | La capa sigue pasando por soft clip, envelope sustain y HPF subsónico. |
| `SYNTH_DEPTH_GAIN` | N/A | `1.12` | Eleva `synthAmount` un 12%, dentro del rango pedido de +8% a +15%. | Conserva gate, `protectedSynth` y soft clip. |
| Mezcla deep extension | `0.32 + voiceProtection * 0.42` | `0.42 + voiceProtection * 0.52` | Aumenta peso de la capa profunda sin inflar 50–80 Hz. | La mezcla depende de `voiceProtection`, por lo que voces/presencia siguen reduciendo riesgo de embarrar. |
| `computeGate()` | Piso musical `0.25` | Piso `0.38` + autoridad detector `0.18` cuando hay detector fuerte | El bajo profundo suele ser centrado/mono; el gate ya no depende tanto de `diffEnv / monoEnv` cuando `detectorEnv` es claro. | El gate sigue multiplicado por `detectorActivity`, por lo que no abre sin bajo detectado. |
| `outputDcHighpass` | `32 Hz` | `28 Hz` | Deja pasar algo más de profundidad audible. | Sigue bloqueando DC/infrasonido. |
| `deepExtensionSubsonicHighpass` | `24 Hz` | `23 Hz` | Ajuste leve para profundidad sin liberar infrasonido peligroso. | Mantiene HPF subsónico dedicado antes de la mezcla. |
| `deepExtensionHz` derivado | `34–39 Hz` | `30–40 Hz` | La extensión profunda trabaja más abajo, en la zona percibida como profundidad. | No sube agresivamente a 50–80 Hz, evitando carácter de bass boost. |
| `subTopHz` derivado | `58–68 Hz` | `56–64 Hz` | Mantiene la ruta sub principal enfocada y evita exceso de golpe medio. | La reconstrucción sigue filtrada por `subLowpass`. |

La salida con `enabled=false` permanece en bypass limpio: el core no aplica filtros, ganancia ni calibración tonal y solo sanea denormals/NaN por seguridad.

## Ajuste fino de profundidad — mayo 2026

Se reforzó el carácter Epicenter sin usar EQ ni bass boost genérico. Los cambios siguen dentro del core `EpicenterDSPCore`:

| Constante / curva | Valor previo | Valor nuevo | Motivo |
|---|---:|---:|---|
| `DEEP_EXTENSION_AMOUNT` | `0.30` | `0.36` | Más energía subgrave reconstruida desde la capa profunda, por debajo del rango de bass boost típico. |
| `SYNTH_DEPTH_GAIN` | `1.12` | `1.18` | Mayor presencia del sintetizador subgrave manteniendo soft clip. |
| `DEEP_EXTENSION_MIX_BASE` | `0.42` | `0.46` | Más profundidad base al activar Epicenter. |
| `DEEP_EXTENSION_MIX_VOICE` | `0.52` | `0.58` | Más aporte profundo cuando la protección de voz permite espacio. |
| `GATE_DETECTOR_FLOOR` | `0.38` | `0.40` | Más autoridad con bajo centrado/mono real. |
| `GATE_DETECTOR_AUTHORITY` | `0.18` | `0.22` | Sostiene mejor detector fuerte sin abrirse con ruido sin bajo. |
| `OUTPUT_DC_HIGHPASS_HZ` | `28 Hz` | `27 Hz` | Un poco más de extensión manteniendo filtro subsónico seguro. |
| Curva de intensidad | lineal | `pow(intensity, 0.85)` | El efecto aparece antes en medio recorrido sin concentrarse solo en 90–100%. |

La extensión profunda mantiene HPF dedicado a 23 Hz, soft clip y trim de salida. Seek, stop y cambio de canción siguen reseteando el estado DSP desde el motor nativo.
