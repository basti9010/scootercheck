import { AppCTA } from "../components/AppCTA";
import { DiagnosticsSection } from "../components/DiagnosticsSection";
import { FAQSection } from "../components/FAQSection";
import { HeroSection } from "../components/HeroSection";
import { HowItWorksSection } from "../components/HowItWorksSection";
import { LiveSearchSection } from "../components/LiveSearchSection";
import { ResultsSection } from "../components/ResultsSection";
import { TechnologySection } from "../components/TechnologySection";

export function HomePage() {
  return (
    <>
      <HeroSection />
      <TechnologySection />
      <LiveSearchSection />
      <DiagnosticsSection />
      <ResultsSection />
      <HowItWorksSection />
      <FAQSection />
      <AppCTA />
    </>
  );
}
