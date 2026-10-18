import { motion } from "framer-motion";
import { techPoints } from "../data/content";
import { Reveal } from "./Reveal";
import "./TechnologySection.css";

export function TechnologySection() {
  return (
    <section className="section tech" id="technologie" aria-labelledby="tech-title">
      <div className="container">
        <Reveal>
          <p className="section__eyebrow">Technologie</p>
          <h2 id="tech-title" className="section__title">
            Was im Scooter steckt, bleibt nicht länger verborgen.
          </h2>
          <p className="section__lede">
            ScooterCheck nutzt verfügbare Bluetooth-Daten, um technische
            Informationen auszulesen und Auffälligkeiten systematisch zu bewerten.
          </p>
        </Reveal>

        <div className="tech__stage">
          <div className="tech__scooter" aria-hidden="true">
            <img
              src="/assets/scooter-cutout.webp"
              alt=""
              width={640}
              height={640}
              loading="lazy"
              decoding="async"
            />
            <svg className="tech__lines" viewBox="0 0 400 400" fill="none">
              <path d="M200 210 L120 120" />
              <path d="M210 230 L300 140" />
              <path d="M190 250 L100 300" />
              <path d="M220 260 L310 310" />
            </svg>
          </div>

          <ul className="tech__points">
            {techPoints.map((point, i) => (
              <motion.li
                key={point.label}
                initial={{ opacity: 0, x: 16 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, amount: 0.6 }}
                transition={{ delay: 0.12 * i, duration: 0.55, ease: [0.22, 1, 0.36, 1] }}
              >
                <span className="tech__dot" aria-hidden="true" />
                <div>
                  <strong>{point.label}</strong>
                  <span>{point.detail}</span>
                </div>
              </motion.li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
