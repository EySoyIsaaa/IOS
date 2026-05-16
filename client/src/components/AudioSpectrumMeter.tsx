import { useEffect, useRef } from "react";

interface AudioSpectrumMeterProps {
  active: boolean;
  getAnalyserNode: () => AnalyserNode | null;
  className?: string;
}

const BAR_COUNT = 28;

export function AudioSpectrumMeter({
  active,
  getAnalyserNode,
  className = "",
}: AudioSpectrumMeterProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !active || document.visibilityState === "hidden") return;

    const analyser = getAnalyserNode();
    if (!analyser) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animationFrame = 0;
    const data = new Uint8Array(analyser.frequencyBinCount);

    const resizeCanvas = () => {
      const dpr = window.devicePixelRatio || 1;
      const rect = canvas.getBoundingClientRect();
      canvas.width = Math.max(1, Math.floor(rect.width * dpr));
      canvas.height = Math.max(1, Math.floor(rect.height * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    const draw = () => {
      if (document.visibilityState === "hidden") return;

      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = "rgba(0, 0, 0, 0.2)";
      ctx.fillRect(0, 0, width, height);

      analyser.getByteFrequencyData(data);
      const barGap = 2;
      const barWidth = Math.max(2, (width - barGap * (BAR_COUNT - 1)) / BAR_COUNT);
      const lowBandBoost = active ? 1.18 : 0.65;

      for (let index = 0; index < BAR_COUNT; index += 1) {
        const sourceIndex = Math.min(
          data.length - 1,
          Math.floor((index / BAR_COUNT) * data.length * 0.58),
        );
        const energy = data[sourceIndex] / 255;
        const shaped = Math.pow(energy, 0.72) * lowBandBoost;
        const barHeight = Math.max(3, Math.min(height - 4, shaped * (height - 5)));
        const x = index * (barWidth + barGap);
        const y = height - barHeight;
        const gradient = ctx.createLinearGradient(0, y, 0, height);
        gradient.addColorStop(0, "#ff6675");
        gradient.addColorStop(0.4, "#ff102a");
        gradient.addColorStop(1, "#5b000b");
        ctx.fillStyle = gradient;
        ctx.shadowBlur = active ? 8 : 0;
        ctx.shadowColor = "rgba(255, 16, 42, 0.45)";
        ctx.fillRect(x, y, barWidth, barHeight);
      }

      ctx.shadowBlur = 0;
      animationFrame = window.requestAnimationFrame(draw);
    };

    const onVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        window.cancelAnimationFrame(animationFrame);
      } else if (active) {
        resizeCanvas();
        animationFrame = window.requestAnimationFrame(draw);
      }
    };

    resizeCanvas();
    animationFrame = window.requestAnimationFrame(draw);
    window.addEventListener("resize", resizeCanvas);
    document.addEventListener("visibilitychange", onVisibilityChange);

    return () => {
      window.cancelAnimationFrame(animationFrame);
      window.removeEventListener("resize", resizeCanvas);
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, [active, getAnalyserNode]);

  return (
    <canvas
      ref={canvasRef}
      className={`h-10 w-full rounded-xl border border-[var(--ep-border)] bg-black ${className}`}
      aria-label="Epicenter realtime audio spectrum"
    />
  );
}

export default AudioSpectrumMeter;
