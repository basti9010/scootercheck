import { useEffect, useRef } from "react";
import { usePrefersReducedMotion } from "../hooks/usePrefersReducedMotion";
import "./RadarCanvas.css";

type Blip = { angle: number; radius: number; size: number };

const BLIPS: Blip[] = [
  { angle: 0.35, radius: 0.42, size: 3.2 },
  { angle: 1.1, radius: 0.68, size: 2.6 },
  { angle: 2.05, radius: 0.52, size: 3.5 },
  { angle: 2.85, radius: 0.78, size: 2.4 },
  { angle: 3.7, radius: 0.38, size: 2.8 },
  { angle: 4.55, radius: 0.62, size: 3.1 },
  { angle: 5.4, radius: 0.74, size: 2.5 },
];

type Props = {
  className?: string;
  intensity?: number;
  interactive?: boolean;
};

export function RadarCanvas({
  className = "",
  intensity = 1,
  interactive = true,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const reduced = usePrefersReducedMotion();
  const pointer = useRef({ x: 0, y: 0 });

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let raf = 0;
    let running = true;
    const start = performance.now();
    const period = 8500;
    const glow = new Float32Array(BLIPS.length);

    const resize = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const rect = canvas.getBoundingClientRect();
      canvas.width = Math.max(1, Math.floor(rect.width * dpr));
      canvas.height = Math.max(1, Math.floor(rect.height * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    const draw = (now: number) => {
      if (!running) return;
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      const cx = w / 2 + (interactive ? pointer.current.x : 0);
      const cy = h / 2 + (interactive ? pointer.current.y : 0);
      const maxR = Math.min(w, h) * 0.46;
      const t = reduced ? 0.15 : ((now - start) % period) / period;
      const sweep = t * Math.PI * 2 - Math.PI / 2;

      ctx.clearRect(0, 0, w, h);

      const alpha = 0.55 * intensity;
      ctx.strokeStyle = `rgba(107, 219, 194, ${0.12 * intensity})`;
      ctx.lineWidth = 1;
      for (let i = 1; i <= 4; i++) {
        ctx.beginPath();
        ctx.arc(cx, cy, (maxR * i) / 4, 0, Math.PI * 2);
        ctx.stroke();
      }

      ctx.beginPath();
      ctx.moveTo(cx - maxR, cy);
      ctx.lineTo(cx + maxR, cy);
      ctx.moveTo(cx, cy - maxR);
      ctx.lineTo(cx, cy + maxR);
      ctx.strokeStyle = `rgba(107, 219, 194, ${0.08 * intensity})`;
      ctx.stroke();

      if (!reduced) {
        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(sweep);
        const wedge = ctx.createLinearGradient(0, 0, maxR, 0);
        wedge.addColorStop(0, `rgba(107, 219, 194, ${0.28 * alpha})`);
        wedge.addColorStop(1, "rgba(107, 219, 194, 0)");
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.arc(0, 0, maxR, -0.55, 0.05);
        ctx.closePath();
        ctx.fillStyle = wedge;
        ctx.fill();
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(maxR, 0);
        ctx.strokeStyle = `rgba(107, 219, 194, ${0.55 * intensity})`;
        ctx.lineWidth = 1.5;
        ctx.stroke();
        ctx.restore();
      }

      BLIPS.forEach((blip, i) => {
        const ang = blip.angle - Math.PI / 2;
        let delta = Math.abs(((sweep - ang + Math.PI) % (Math.PI * 2)) - Math.PI);
        if (reduced) {
          glow[i] = 0.35;
        } else if (delta < 0.22) {
          glow[i] = Math.min(1, glow[i] + 0.18);
        } else {
          glow[i] = Math.max(0, glow[i] - 0.008);
        }
        const r = blip.radius * maxR;
        const x = cx + Math.cos(ang) * r;
        const y = cy + Math.sin(ang) * r;
        const g = glow[i];
        if (g <= 0.01) return;
        ctx.beginPath();
        ctx.arc(x, y, blip.size + g * 2.5, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(107, 219, 194, ${0.15 * g * intensity})`;
        ctx.fill();
        ctx.beginPath();
        ctx.arc(x, y, blip.size * (0.55 + g * 0.45), 0, Math.PI * 2);
        ctx.fillStyle = `rgba(107, 219, 194, ${0.35 + 0.55 * g})`;
        ctx.fill();
      });

      raf = requestAnimationFrame(draw);
    };

    raf = requestAnimationFrame(draw);

    return () => {
      running = false;
      cancelAnimationFrame(raf);
      ro.disconnect();
    };
  }, [intensity, interactive, reduced]);

  useEffect(() => {
    if (!interactive || reduced) return;
    const onMove = (e: PointerEvent) => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const rect = canvas.getBoundingClientRect();
      const nx = ((e.clientX - rect.left) / rect.width - 0.5) * 16;
      const ny = ((e.clientY - rect.top) / rect.height - 0.5) * 12;
      pointer.current.x = Math.max(-10, Math.min(10, nx));
      pointer.current.y = Math.max(-8, Math.min(8, ny));
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    return () => window.removeEventListener("pointermove", onMove);
  }, [interactive, reduced]);

  return (
    <canvas
      ref={canvasRef}
      className={`radar-canvas ${className}`}
      aria-hidden="true"
    />
  );
}
