import { faqItems, models } from "../data/content";
import { Reveal } from "./Reveal";
import "./FAQSection.css";

export function FAQSection() {
  return (
    <section className="section faq" id="faq" aria-labelledby="faq-title">
      <div className="container faq__grid">
        <Reveal>
          <p className="section__eyebrow">FAQ</p>
          <h2 id="faq-title" className="section__title">
            Klar beantwortet.
          </h2>
          <p className="section__lede">
            Antworten auf Grundlage der tatsächlich umgesetzten
            Produkteigenschaften.
          </p>

          <div className="faq__models">
            <h3>Unterstützte Modelle</h3>
            <ul>
              {models.map((m) => (
                <li key={m}>{m}</li>
              ))}
            </ul>
          </div>
        </Reveal>

        <Reveal delay={0.08}>
          <div className="faq__accordion">
            {faqItems.map((item) => (
              <details key={item.q}>
                <summary>{item.q}</summary>
                <p>{item.a}</p>
              </details>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
