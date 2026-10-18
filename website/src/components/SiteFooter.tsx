import { Link } from "react-router-dom";
import { navLinks } from "../data/content";
import "./SiteFooter.css";

export function SiteFooter() {
  const year = new Date().getFullYear();

  return (
    <footer className="site-footer">
      <div className="container site-footer__grid">
        <div>
          <Link to="/#top" className="brand">
            <img src="/assets/logo.webp" alt="" width={28} height={28} />
            <span className="brand__word">
              <span>Scooter</span>Check
            </span>
          </Link>
          <p className="site-footer__tag">
            Nur lesende E-Scooter-Diagnose für iOS.
          </p>
        </div>

        <nav aria-label="Footer Navigation">
          <p>Produkt</p>
          {navLinks.map((link) => (
            <a key={link.href} href={link.href}>
              {link.label}
            </a>
          ))}
        </nav>

        <nav aria-label="Rechtliches">
          <p>Rechtliches</p>
          <Link to="/datenschutz">Datenschutz</Link>
          <Link to="/impressum">Impressum</Link>
          <span className="site-footer__todo">Kontakt · TODO</span>
        </nav>
      </div>
      <div className="container site-footer__bottom">
        <span>© {year} ScooterCheck</span>
        <span>Beispieldaten auf dieser Website sind gekennzeichnet.</span>
      </div>
    </footer>
  );
}
