import { motion, useScroll } from "framer-motion";
import "./ScrollProgress.css";

export function ScrollProgress() {
  const { scrollYProgress } = useScroll();
  return (
    <motion.div
      className="scroll-progress"
      style={{ scaleX: scrollYProgress }}
      aria-hidden="true"
    />
  );
}
