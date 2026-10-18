import { motion } from "framer-motion";
import { diagnosticsItems } from "../data/content";
import { Reveal } from "./Reveal";
import "./DiagnosticsSection.css";

export function DiagnosticsSection() {
  return (
    <section className="section diag" id="funktionen" aria-labelledby="diag-title">
      <div className="container">
        <Reveal>
          <p className="section__eyebrow">Diagnose</p>
          <h2 id="diag-title" className="section__title">
            Mehr als nur eine Verbindung.
          </h2>
          <p className="section__lede">
            Technische Analysefunktionen der App — dargestellt als eine
            zusammenhängende Diagnosevisualisierung statt isolierter Karten.
          </p>
        </Reveal>

        <div className="diag__rail" role="list">
          <div className="diag__track" aria-hidden="true" />
          {diagnosticsItems.map((item, i) => (
            <motion.article
              key={item.title}
              className="diag__item"
              role="listitem"
              initial={{ opacity: 0, y: 18 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, amount: 0.45 }}
              transition={{ delay: 0.06 * i, duration: 0.55, ease: [0.22, 1, 0.36, 1] }}
            >
              <span className="diag__index">{String(i + 1).padStart(2, "0")}</span>
              <div>
                <h3>{item.title}</h3>
                <p>{item.text}</p>
              </div>
            </motion.article>
          ))}
        </div>
      </div>
    </section>
  );
}
