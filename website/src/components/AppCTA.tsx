import { Reveal } from "./Reveal";
import "./AppCTA.css";

export function AppCTA() {
  return (
    <section className="section app-cta" id="app" aria-labelledby="app-title">
      <div className="container">
        <Reveal className="app-cta__inner">
          <img
            className="app-cta__icon"
            src="/assets/app-icon.webp"
            alt=""
            width={88}
            height={88}
            loading="lazy"
            decoding="async"
          />
          <div>
            <p className="section__eyebrow">App entdecken</p>
            <h2 id="app-title">ScooterCheck auf dem iPhone</h2>
            <p>
              Native SwiftUI-App mit Core Bluetooth. Bundle-ID{" "}
              <code>com.scootercheck.app</code>. Nur lesen — nie ändern.
            </p>
            <div className="app-cta__actions">
              <a
                className="btn btn--primary"
                href="https://github.com/basti9010/scootercheck"
                rel="noopener noreferrer"
                target="_blank"
              >
                Projekt auf GitHub
                <span className="btn__arrow" aria-hidden="true">
                  →
                </span>
              </a>
              <a className="btn btn--ghost" href="#ablauf">
                Ablauf ansehen
              </a>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
