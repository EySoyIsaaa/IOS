/**
 * EpicenterDSP 7.0 - Metallic hardware knob control
 * Canvas keeps the brushed-metal/ring drawing isolated from React rendering.
 */

import React, { useCallback, useEffect, useRef, useState } from "react";

interface KnobControlProps {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  unit?: string;
  onChange: (value: number) => void;
  disabled?: boolean;
  size?: number;
  featured?: boolean;
}

export const KnobControl: React.FC<KnobControlProps> = React.memo(
  ({
    label,
    value,
    min,
    max,
    step,
    unit = "",
    onChange,
    disabled = false,
    size = 86,
    featured = false,
  }) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const [isDragging, setIsDragging] = useState(false);
    const startY = useRef(0);
    const startValue = useRef(0);

    const radius = size * 0.39;
    const ringRadius = size * 0.43;
    const lineWidth = featured ? 5 : 3.5;

    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;

      const ctx = canvas.getContext("2d");
      if (!ctx) return;

      const dpr = window.devicePixelRatio || 1;
      canvas.width = size * dpr;
      canvas.height = size * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const centerX = size / 2;
      const centerY = size / 2;
      const startAngle = (135 * Math.PI) / 180;
      const endAngle = (405 * Math.PI) / 180;
      const normalizedValue = Math.max(0, Math.min(1, (value - min) / (max - min)));
      const progressAngle = startAngle + normalizedValue * (endAngle - startAngle);

      ctx.clearRect(0, 0, size, size);

      if (!disabled) {
        ctx.beginPath();
        ctx.arc(centerX, centerY, ringRadius + 2, 0, Math.PI * 2);
        ctx.shadowBlur = featured ? 24 : 13;
        ctx.shadowColor = featured ? "rgba(255, 16, 42, 0.48)" : "rgba(255, 16, 42, 0.28)";
        ctx.strokeStyle = "rgba(143, 0, 18, 0.34)";
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.shadowBlur = 0;
      }

      // Segmented outer arc background.
      const segments = 34;
      for (let i = 0; i < segments; i += 1) {
        const segmentStart = startAngle + (i / segments) * (endAngle - startAngle);
        const segmentEnd = segmentStart + ((endAngle - startAngle) / segments) * 0.56;
        ctx.beginPath();
        ctx.arc(centerX, centerY, ringRadius, segmentStart, segmentEnd);
        ctx.strokeStyle = i / segments <= normalizedValue && !disabled ? "#ff102a" : "#2f2f2f";
        ctx.lineWidth = lineWidth;
        ctx.lineCap = "round";
        ctx.stroke();
      }

      // Beveled outer body.
      const bevel = ctx.createRadialGradient(centerX - radius * 0.32, centerY - radius * 0.45, 2, centerX, centerY, radius + 7);
      bevel.addColorStop(0, "#5a5a5a");
      bevel.addColorStop(0.18, "#2a2a2a");
      bevel.addColorStop(0.58, "#121212");
      bevel.addColorStop(0.82, "#303030");
      bevel.addColorStop(1, "#070707");
      ctx.beginPath();
      ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
      ctx.fillStyle = bevel;
      ctx.fill();

      // Brushed metal grooves.
      for (let i = 0; i < 30; i += 1) {
        ctx.beginPath();
        ctx.arc(centerX, centerY, radius - 4 - i * 0.42, 0, Math.PI * 2);
        ctx.strokeStyle = i % 2 === 0 ? "rgba(255,255,255,0.025)" : "rgba(0,0,0,0.12)";
        ctx.lineWidth = 0.6;
        ctx.stroke();
      }

      // Inner face and highlight.
      const face = ctx.createLinearGradient(centerX - radius, centerY - radius, centerX + radius, centerY + radius);
      face.addColorStop(0, "rgba(255,255,255,0.12)");
      face.addColorStop(0.34, "rgba(255,255,255,0.02)");
      face.addColorStop(0.7, "rgba(0,0,0,0.28)");
      face.addColorStop(1, "rgba(255,255,255,0.06)");
      ctx.beginPath();
      ctx.arc(centerX, centerY, radius - 8, 0, Math.PI * 2);
      ctx.fillStyle = face;
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.06)";
      ctx.lineWidth = 1;
      ctx.stroke();

      // Red pointer line.
      const innerRadius = radius * 0.22;
      const outerRadius = radius - 12;
      ctx.beginPath();
      ctx.moveTo(centerX + Math.cos(progressAngle) * innerRadius, centerY + Math.sin(progressAngle) * innerRadius);
      ctx.lineTo(centerX + Math.cos(progressAngle) * outerRadius, centerY + Math.sin(progressAngle) * outerRadius);
      ctx.strokeStyle = disabled ? "#52525b" : "#ff102a";
      ctx.lineWidth = featured ? 4 : 2.6;
      ctx.lineCap = "round";
      ctx.shadowBlur = disabled ? 0 : 10;
      ctx.shadowColor = "rgba(255, 16, 42, 0.75)";
      ctx.stroke();
      ctx.shadowBlur = 0;

      ctx.beginPath();
      ctx.arc(centerX, centerY, featured ? 5.5 : 4.2, 0, Math.PI * 2);
      ctx.fillStyle = "#111111";
      ctx.fill();
      ctx.strokeStyle = "#3d3d3d";
      ctx.stroke();
    }, [disabled, featured, lineWidth, max, min, radius, ringRadius, size, value]);

    const handleStart = useCallback(
      (clientY: number) => {
        if (disabled) return;
        setIsDragging(true);
        startY.current = clientY;
        startValue.current = value;
      },
      [disabled, value],
    );

    const handleMove = useCallback(
      (clientY: number) => {
        if (!isDragging) return;
        const deltaY = startY.current - clientY;
        const sensitivity = (max - min) / 150;
        let newValue = startValue.current + deltaY * sensitivity;
        newValue = Math.round(newValue / step) * step;
        onChange(Math.max(min, Math.min(max, newValue)));
      },
      [isDragging, max, min, onChange, step],
    );

    const handleEnd = useCallback(() => setIsDragging(false), []);

    useEffect(() => {
      if (!isDragging) return;

      const originalOverflow = document.body.style.overflow;
      const originalTouchAction = document.body.style.touchAction;
      document.body.style.overflow = "hidden";
      document.body.style.touchAction = "none";

      const onMouseMove = (event: MouseEvent) => handleMove(event.clientY);
      const onTouchMove = (event: TouchEvent) => {
        event.preventDefault();
        if (event.touches[0]) handleMove(event.touches[0].clientY);
      };

      document.addEventListener("mousemove", onMouseMove);
      document.addEventListener("mouseup", handleEnd);
      document.addEventListener("touchmove", onTouchMove, { passive: false });
      document.addEventListener("touchend", handleEnd);

      return () => {
        document.body.style.overflow = originalOverflow;
        document.body.style.touchAction = originalTouchAction;
        document.removeEventListener("mousemove", onMouseMove);
        document.removeEventListener("mouseup", handleEnd);
        document.removeEventListener("touchmove", onTouchMove);
        document.removeEventListener("touchend", handleEnd);
      };
    }, [handleEnd, handleMove, isDragging]);

    return (
      <div className={`flex flex-col items-center gap-2 ${featured ? "premium-knob-featured" : ""}`}>
        {featured && (
          <p className="text-3xl font-black tabular-nums text-white tracking-tight dsp-numeric">
            {value.toFixed(0)}{unit}
          </p>
        )}
        <canvas
          ref={canvasRef}
          width={size}
          height={size}
          style={{ width: size, height: size, touchAction: "none", overscrollBehavior: "contain" }}
          onMouseDown={(event) => handleStart(event.clientY)}
          onTouchStart={(event) => {
            event.preventDefault();
            handleStart(event.touches[0].clientY);
          }}
          onTouchMove={(event) => {
            event.preventDefault();
            handleMove(event.touches[0].clientY);
          }}
          onTouchEnd={handleEnd}
          className={`transition-opacity ${disabled ? "cursor-not-allowed opacity-40" : "cursor-ns-resize"}`}
          data-testid={`knob-${label.toLowerCase()}`}
        />
        <div className="text-center">
          <p className="text-[10px] font-black tracking-[0.2em] uppercase text-[var(--ep-text-muted)]">
            {label}
          </p>
          {!featured && (
            <p className="text-sm font-bold text-white tabular-nums dsp-numeric">
              {value.toFixed(0)}{unit}
            </p>
          )}
        </div>
      </div>
    );
  },
);

KnobControl.displayName = "KnobControl";
