import { howSteps } from "../data/content";
import { Reveal } from "./Reveal";
import "./HowItWorksSection.css";

export function HowItWorksSection() {
  return (
    <section className="section how" id="ablauf" aria-labelledby="how-title">
      <div className="container">
        <Reveal>
          <p className="section__eyebrow">So funktioniert&apos;s</p>
          <h2 id="how-title" className="section__title">
            Fünf Schritte zur Dokumentation.
          </h2>
          <p className="section__lede">
            Vom BLE-Scan bis zum Protokoll — innerhalb der tatsächlichen
            Funktionsgrenzen der App.
          </p>
        </Reveal>

        <ol className="how__list">
          {howSteps.map((step, i) => (
            <Reveal key={step.title} delay={0.05 * i}>
              <li>
                <span className="how__num">{String(i + 1).padStart(2, "0")}</span>
                <div>
                  <h3>{step.title}</h3>
                  <p>{step.text}</p>
                </div>
              </li>
            </Reveal>
          ))}
        </ol>
      </div>
    </section>
  );
}
