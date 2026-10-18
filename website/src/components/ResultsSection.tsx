import { demoVerdicts } from "../data/content";
import { Reveal } from "./Reveal";
import "./ResultsSection.css";

export function ResultsSection() {
  return (
    <section className="section results" id="ergebnisse" aria-labelledby="results-title">
      <div className="container">
        <Reveal>
          <p className="section__eyebrow">Ergebnisse</p>
          <h2 id="results-title" className="section__title">
            Daten statt Vermutungen.
          </h2>
          <p className="section__lede">
            Beispielhafte Statusanzeigen aus einem technischen Prüfbericht.
            Beispieldaten — keine Aussage über einen konkreten Scooter.
          </p>
        </Reveal>

        <Reveal delay={0.08}>
          <div className="results__sheet" aria-label="Beispiel-Prüfbericht">
            <header className="results__meta">
              <span>ScooterCheck Protokoll</span>
              <span>Demo · Beispieldaten</span>
            </header>
            <ul className="results__list">
              {demoVerdicts.map((v) => (
                <li key={v.label} data-tone={v.tone}>
                  <span className="results__dot" aria-hidden="true" />
                  <div>
                    <strong>{v.label}</strong>
                    <span>{v.hint}</span>
                  </div>
                </li>
              ))}
            </ul>
            <p className="results__note">
              Die App weist fehlende oder nicht bewertbare Werte als „nicht
              feststellbar“ aus. Eine pauschale Aussage „sicher manipuliert“ oder
              „unverändert“ wird nicht getroffen, wenn die Daten das nicht tragen.
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
