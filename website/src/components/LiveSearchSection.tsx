import { Reveal } from "./Reveal";
import { RadarCanvas } from "./RadarCanvas";
import "./LiveSearchSection.css";

export function LiveSearchSection() {
  return (
    <section className="section live" id="suche" aria-labelledby="live-title">
      <div className="container live__grid">
        <Reveal>
          <p className="section__eyebrow">Live-Suche</p>
          <h2 id="live-title" className="section__title">
            Finden. Verbinden. Analysieren.
          </h2>
          <p className="section__lede">
            Eine animierte Radaroberfläche zeigt Gerätepositionen als Punkte.
            Bluetooth-Signalstärken liefern Hinweise auf die Nähe — keine
            exakte Position und keine Garantie für Ortungsgenauigkeit.
          </p>
        </Reveal>

        <Reveal delay={0.1} className="live__panel">
          <div className="live__radar">
            <RadarCanvas intensity={0.95} interactive={false} />
            <div className="live__caption">
              Demonstration · stabile Beispielpunkte · kein Live-Tracking
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
