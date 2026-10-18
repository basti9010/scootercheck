import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useState } from "react";
import { useMediaQuery } from "../hooks/useMediaQuery";
import "./ScooterVisual.css";

type Props = {
  className?: string;
  parallax?: { x: number; y: number };
};

export function ScooterVisual({ className = "", parallax }: Props) {
  const reduced = useReducedMotion();
  const isTouch = useMediaQuery("(hover: none)");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const id = requestAnimationFrame(() => setReady(true));
    return () => cancelAnimationFrame(id);
  }, []);

  const px = !isTouch && parallax && !reduced ? parallax.x : 0;
  const py = !isTouch && parallax && !reduced ? parallax.y : 0;

  return (
    <div className={`scooter-visual ${className}`}>
      <motion.div
        className="scooter-visual__float"
        animate={
          reduced
            ? { y: 0 }
            : { y: [0, -6, 0] }
        }
        transition={
          reduced
            ? { duration: 0 }
            : { duration: 6.5, repeat: Infinity, ease: "easeInOut" }
        }
        style={{
          transform: `translate3d(${px}px, ${py}px, 0)`,
        }}
      >
        <motion.img
          className="scooter-visual__img"
          src="/assets/scooter-cutout.webp"
          srcSet="/assets/scooter-cutout.webp 1x, /assets/scooter-cutout.png 2x"
          alt="Schwarzer E-Scooter — ScooterCheck Produktvisual"
          width={1024}
          height={1024}
          decoding="async"
          initial={reduced ? false : { opacity: 0, y: 24, scale: 0.97 }}
          animate={
            ready
              ? { opacity: 1, y: 0, scale: 1 }
              : { opacity: 0, y: 24, scale: 0.97 }
          }
          transition={{ duration: 1.1, delay: 0.35, ease: [0.22, 1, 0.36, 1] }}
        />
        <div className="scooter-visual__sheen" aria-hidden="true" />
      </motion.div>
    </div>
  );
}
