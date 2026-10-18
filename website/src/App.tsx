import { useEffect } from "react";
import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import { ScrollProgress } from "./components/ScrollProgress";
import { SiteFooter } from "./components/SiteFooter";
import { SiteHeader } from "./components/SiteHeader";
import { HomePage } from "./pages/HomePage";
import { ImprintPage } from "./pages/ImprintPage";
import { PrivacyPage } from "./pages/PrivacyPage";

function ScrollToHash() {
  const { pathname, hash } = useLocation();

  useEffect(() => {
    if (pathname !== "/") {
      window.scrollTo(0, 0);
      return;
    }
    if (!hash) return;
    const id = hash.replace("#", "");
    const t = window.setTimeout(() => {
      document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 40);
    return () => window.clearTimeout(t);
  }, [pathname, hash]);

  return null;
}

export default function App() {
  return (
    <>
      <a className="skip-link" href="#inhalt">
        Zum Inhalt
      </a>
      <ScrollProgress />
      <SiteHeader />
      <ScrollToHash />
      <main id="inhalt">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/datenschutz" element={<PrivacyPage />} />
          <Route path="/impressum" element={<ImprintPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
      <SiteFooter />
    </>
  );
}
