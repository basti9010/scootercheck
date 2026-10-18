import {
  motion,
  useReducedMotion,
  useScroll,
  useTransform,
} from "framer-motion";
import { useRef, useState } from "react";
import { useMediaQuery } from "../hooks/useMediaQuery";
import { RadarCanvas } from "./RadarCanvas";
import { ScooterVisual } from "./ScooterVisual";
import "./HeroSection.css";

export function HeroSection() {
  const ref = useRef<HTMLElement>(null);
  const reduced = useReducedMotion();
  const isTouch = useMediaQuery("(hover: none)");
  const [parallax, setParallax] = useState({ x: 0, y: 0 });

  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start start", "end start"],
  });

  const copyOpacity = useTransform(scrollYProgress, [0, 0.45], [1, 0]);
  const copyY = useTransform(scrollYProgress, [0, 0.5], [0, -40]);
  const stageScale = useTransform(scrollYProgress, [0, 0.7], [1, 0.88]);
  const stageY = useTransform(scrollYProgress, [0, 0.7], [0, 60]);
  const radarFade = useTransform(scrollYProgress, [0, 0.55], [1, 0.15]);
  const glowOpacity = useTransform(scrollYProgress, [0, 0.5], [1, 0.2]);

  const onMove = (e: React.PointerEvent) => {
    if (isTouch || reduced) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const nx = ((e.clientX - rect.left) / rect.width - 0.5) * 20;
    const ny = ((e.clientY - rect.top) / rect.height - 0.5) * 14;
    setParallax({
      x: Math.max(-10, Math.min(10, nx)),
      y: Math.max(-8, Math.min(8, ny)),
    });
  };

  return (
    <section
      ref={ref}
      id="top"
      className="hero"
      aria-labelledby="hero-title"
      onPointerMove={onMove}
    >
      <div className="hero__atmosphere" aria-hidden="true" />
      <motion.div
        className="hero__glow"
        style={{ opacity: glowOpacity }}
        aria-hidden="true"
      />

      <div className="hero__layout container">
        <motion.div
          className="hero__copy"
          style={reduced ? undefined : { opacity: copyOpacity, y: copyY }}
        >
          <motion.p
            className="hero__brand"
            initial={reduced ? false : { opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.85, ease: [0.22, 1, 0.36, 1] }}
          >
            <span>Scooter</span>Check
          </motion.p>
          <motion.h1
            id="hero-title"
            initial={reduced ? false : { opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.75, delay: 1.05, ease: [0.22, 1, 0.36, 1] }}
          >
            Technologie erkennen.
            <br />
            Manipulationen sichtbar machen.
          </motion.h1>
          <motion.p
            className="hero__lede"
            initial={reduced ? false : { opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 1.25, ease: [0.22, 1, 0.36, 1] }}
          >
            Intelligente Bluetooth-Diagnose für E-Scooter. Technische
            Auffälligkeiten erkennen, Daten analysieren und Ergebnisse
            nachvollziehbar dokumentieren.
          </motion.p>
          <motion.div
            className="hero__cta"
            initial={reduced ? false : { opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.65, delay: 1.45, ease: [0.22, 1, 0.36, 1] }}
          >
            <a className="btn btn--primary" href="#technologie">
              ScooterCheck entdecken
              <span className="btn__arrow" aria-hidden="true">
                →
              </span>
            </a>
            <a className="btn btn--ghost" href="#ablauf">
              So funktioniert&apos;s
            </a>
          </motion.div>
        </motion.div>

        <motion.div
          className="hero__stage"
          style={reduced ? undefined : { scale: stageScale, y: stageY }}
        >
          <motion.div className="hero__radar-wrap" style={{ opacity: radarFade }}>
            <RadarCanvas intensity={1} interactive={!isTouch && !reduced} />
          </motion.div>
          <ScooterVisual
            parallax={
              isTouch || reduced
                ? undefined
                : { x: parallax.x * 0.55, y: parallax.y * 0.55 }
            }
          />
        </motion.div>
      </div>
    </section>
  );
}
