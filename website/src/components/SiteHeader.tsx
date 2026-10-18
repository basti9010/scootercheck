import { useEffect, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { navLinks } from "../data/content";
import { hashId, scrollToId } from "../utils/scrollToId";
import "./SiteHeader.css";

export function SiteHeader() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    setOpen(false);
  }, [location.pathname, location.hash]);

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  const goHash = (href: string) => (e: React.MouseEvent) => {
    e.preventDefault();
    setOpen(false);
    const id = hashId(href);
    if (location.pathname !== "/") {
      navigate(`/#${id}`);
      return;
    }
    scrollToId(id || "top");
  };

  return (
    <header className={`site-header ${scrolled ? "is-scrolled" : ""} ${open ? "is-open" : ""}`}>
      <div className="site-header__inner">
        <Link
          to="/"
          className="brand"
          aria-label="ScooterCheck Start"
          onClick={(e) => {
            if (location.pathname === "/") {
              e.preventDefault();
              scrollToId("top");
            }
          }}
        >
          <img src="/assets/logo.webp" alt="" width={32} height={32} className="brand__mark" />
          <span className="brand__word">
            <span>Scooter</span>Check
          </span>
        </Link>

        <nav className="site-nav" aria-label="Hauptnavigation">
          {navLinks.map((link) => (
            <a key={link.href} href={link.href} onClick={goHash(link.href)}>
              {link.label}
            </a>
          ))}
        </nav>

        <a className="btn btn--ghost site-header__cta" href="/#app" onClick={goHash("/#app")}>
          App entdecken
        </a>

        <button
          type="button"
          className="menu-toggle"
          aria-expanded={open}
          aria-controls="mobile-nav"
          aria-label={open ? "Menü schließen" : "Menü öffnen"}
          onClick={() => setOpen((v) => !v)}
        >
          <span />
          <span />
        </button>
      </div>

      <div id="mobile-nav" className={`mobile-nav ${open ? "is-open" : ""}`}>
        <nav aria-label="Mobiles Menü">
          {navLinks.map((link) => (
            <a key={link.href} href={link.href} onClick={goHash(link.href)}>
              {link.label}
            </a>
          ))}
        </nav>
      </div>
    </header>
  );
}
