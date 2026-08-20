import { useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const releaseUrl = 'https://github.com/HuipengXu/SwitchGPT/releases/tag/v0.1.0-alpha.2'
const downloadUrl = 'https://github.com/HuipengXu/SwitchGPT/releases/download/v0.1.0-alpha.2/SwitchGPT-0.1.0-macOS-arm64.zip'
const appIcon = '/switchgpt-icon.png'
const menuBarScreenshot = '/screenshots/statusbar-real.png'
const dashboardScreenshot = '/screenshots/dashboard-real.jpeg'
const confirmationScreenshot = '/screenshots/switch-confirmation-real.jpeg'

function ArrowIcon() {
  return <svg className="arrow-icon" viewBox="0 0 18 18" aria-hidden="true"><path d="M3 9h11M9.5 3.5 15 9l-5.5 5.5" /></svg>
}

function BrandMark({ small = false }) {
  return <img className={'brand-mark' + (small ? ' brand-mark-small' : '')} src={appIcon} alt="" aria-hidden="true" />
}

function MenuIcon({ open }) {
  return <svg className="menu-icon" viewBox="0 0 20 20" aria-hidden="true">{open ? <path d="m4 4 12 12M16 4 4 16" /> : <path d="M3 5h14M3 10h14M3 15h14" />}</svg>
}

function RealScreenshot({ src, alt, caption, className = '' }) {
  const figureClassName = className ? 'real-screenshot ' + className : 'real-screenshot'
  return (
    <figure className={figureClassName}>
      <img src={src} alt={alt} loading="lazy" />
      <figcaption>{caption}</figcaption>
    </figure>
  )
}

function ScreenshotCard({ number, title, copy, src, alt }) {
  return (
    <article className="screenshot-card">
      <div className="visual-card-caption">
        <span className="visual-index">{number}</span>
        <div><h3>{title}</h3><p>{copy}</p></div>
      </div>
      <RealScreenshot src={src} alt={alt} caption="Actual macOS app window · title bar included · sample accounts shown" />
    </article>
  )
}

function Header() {
  const [menuOpen, setMenuOpen] = useState(false)
  const closeMenu = () => setMenuOpen(false)
  const navClassName = menuOpen ? 'site-nav site-nav-open' : 'site-nav'
  return (
    <header className="site-header">
      <a className="wordmark" href="#top" onClick={closeMenu}><BrandMark /><span>SwitchGPT</span></a>
      <nav className={navClassName} aria-label="Main navigation">
        <a href="#product" onClick={closeMenu}>Product</a><a href="#safety" onClick={closeMenu}>Safety</a><a href="#install" onClick={closeMenu}>Install</a><a href="https://github.com/HuipengXu/SwitchGPT" target="_blank" rel="noreferrer" onClick={closeMenu}>GitHub</a>
      </nav>
      <a className="header-cta" href={downloadUrl}><span>Download alpha</span><ArrowIcon /></a>
      <button className="menu-button" type="button" aria-label={menuOpen ? 'Close menu' : 'Open menu'} aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}><MenuIcon open={menuOpen} /></button>
    </header>
  )
}

function Hero() {
  return (
    <section className="hero section-frame" id="top">
      <div className="hero-copy">
        <div className="eyebrow"><BrandMark small /><span>Public macOS alpha · 0.1.0</span></div>
        <h1>Your ChatGPT accounts, in one small app.</h1>
        <p>See Work/Codex usage across your local accounts, add another account through official sign-in, then click the account you want in the menu bar to switch in one simple step.</p>
        <div className="hero-actions"><a className="button button-primary" href={downloadUrl}>Download for Apple silicon <ArrowIcon /></a><a className="text-link" href="#install">How to install <ArrowIcon /></a></div>
        <div className="hero-meta"><span>macOS 14+</span><span>Apple silicon</span><span>Notarized</span></div>
      </div>
      <div className="hero-product">
        <div className="hero-dashboard-panel">
          <div className="hero-visual-heading">
            <span className="eyebrow">Dashboard</span>
            <span className="hero-visual-index">Usage overview</span>
          </div>
          <RealScreenshot
            className="hero-screenshot"
            src={dashboardScreenshot}
            alt="SwitchGPT native macOS Dashboard showing three local accounts and Work / Codex usage"
            caption="Actual SwitchGPT app window · title bar included · sample accounts shown for privacy"
          />
        </div>
        <aside className="hero-switch-panel" aria-label="Quick account switching">
          <div className="hero-switch-copy">
            <span className="eyebrow">Quick switch</span>
            <p>Click an account in the menu bar to switch in one simple step.</p>
          </div>
          <RealScreenshot
            className="hero-statusbar-screenshot"
            src={menuBarScreenshot}
            alt="Actual SwitchGPT macOS menu bar status popover with sample accounts"
            caption="Actual status popover · sample accounts shown"
          />
        </aside>
      </div>
    </section>
  )
}

function ProductSection() {
  return (
    <section className="product-section section-frame" id="product">
      <div className="product-section-heading"><span className="eyebrow">BUILT AROUND THE REAL APP</span><h2>See the app you will actually use.</h2><p>Click an account in the menu bar to switch in one simple step. The native macOS captures below show the status popover, usage Dashboard, and confirmation sheet.</p></div>
      <div className="feature-grid">
        <FeatureCard number="01" title="See every account" copy="Keep weekly Work/Codex usage, plan, credits, and the current desktop identity in one view." />
        <FeatureCard number="02" title="Sign in the normal way" copy="Add accounts through the official OpenAI sign-in flow. No API keys, folder pickers, or custom credential forms." />
        <FeatureCard number="03" title="Switch deliberately" copy="Click the account you want in the menu bar to switch in one simple step. The experimental flow stays explicit and default-off." />
      </div>
      <div className="visual-gallery">
        <ScreenshotCard number="02" title="The Dashboard" copy="The real app window keeps accounts, Work/Codex limits, credits, and the active identity together." src={dashboardScreenshot} alt="Actual SwitchGPT Dashboard window" />
        <ScreenshotCard number="03" title="The confirmation sheet" copy="The native confirmation flow makes the scope visible before a preview or experimental switch begins." src={confirmationScreenshot} alt="Actual SwitchGPT account switch confirmation sheet" />
      </div>
    </section>
  )
}

function FeatureCard({ number, title, copy }) {
  return <article className="feature-card"><span className="feature-number">{number}</span><h3>{title}</h3><p>{copy}</p></article>
}

function SafetySection() {
  return (
    <section className="safety-section" id="safety">
      <div className="safety-inner section-frame">
        <div className="safety-copy"><span className="eyebrow eyebrow-light">SAFETY BOUNDARY</span><h2>Look first.<br />Switch only when you mean it.</h2><p>Quota viewing and account sign-in stay separate from the experimental desktop switch. Credentials stay local; the app does not run a background rotation or silently restart ChatGPT.</p></div>
        <div className="boundary-grid"><BoundaryItem label="Local only" copy="Account profiles live in private macOS storage." icon="lock" /><BoundaryItem label="Explicit" copy="No automatic rotation or background switching." icon="hand" /><BoundaryItem label="Recoverable" copy="A failed attempt uses one bounded recovery path." icon="restore" /></div>
      </div>
    </section>
  )
}

function BoundaryItem({ label, copy, icon }) {
  return <div className="boundary-item"><span className={'boundary-item-icon boundary-item-icon-' + icon}>{icon === 'lock' ? '⌑' : icon === 'hand' ? '◌' : '↶'}</span><strong>{label}</strong><span>{copy}</span></div>
}

function InstallSection() {
  return (
    <section className="install-section section-frame" id="install">
      <div className="install-copy"><span className="eyebrow">START IN A FEW MINUTES</span><h2>Download, open, add an account.</h2><p>The first account is read from your current local session. Adding another account opens the official sign-in flow and keeps the account profile on this Mac.</p><a className="button button-primary" href={downloadUrl}>Get SwitchGPT alpha <ArrowIcon /></a><a className="release-link" href={releaseUrl} target="_blank" rel="noreferrer">View release notes and checksum <ArrowIcon /></a></div>
      <ol className="install-steps"><li><span className="step-number">1</span><div><strong>Download the ZIP</strong><p>Use the arm64 release for Apple silicon Macs and verify the SHA-256 sidecar if you want an extra check.</p></div></li><li><span className="step-number">2</span><div><strong>Move SwitchGPT to Applications</strong><p>Unzip it, drag <code>SwitchGPT.app</code> to <code>/Applications</code>, then open it normally.</p></div></li><li><span className="step-number">3</span><div><strong>Add the accounts you use</strong><p>Choose Add account, finish OpenAI sign-in in your browser, and return to the usage dashboard.</p></div></li></ol>
    </section>
  )
}

function Footer() {
  return <footer className="site-footer section-frame"><a className="wordmark" href="#top"><BrandMark /><span>SwitchGPT</span></a><span>Built for macOS · Public alpha</span><a href="https://github.com/HuipengXu/SwitchGPT" target="_blank" rel="noreferrer">Source on GitHub</a></footer>
}

function App() {
  return <><Header /><main><Hero /><ProductSection /><SafetySection /><InstallSection /></main><Footer /></>
}

createRoot(document.getElementById('root')).render(<App />)
