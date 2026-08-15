import { useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const accounts = [
  { name: 'Personal', quota: 79, kind: 'person' },
  { name: 'Work', quota: 54, kind: 'briefcase' },
  { name: 'Research', quota: 92, kind: 'flask' },
  { name: 'Client', quota: 31, kind: 'building' },
]

function ArrowIcon() {
  return (
    <svg className="arrow-icon" viewBox="0 0 18 18" aria-hidden="true">
      <path d="M3 9h11M9.5 3.5 15 9l-5.5 5.5" />
    </svg>
  )
}

function MenuIcon({ open }) {
  return (
    <svg className="menu-icon" viewBox="0 0 20 20" aria-hidden="true">
      {open ? <path d="m4 4 12 12M16 4 4 16" /> : <path d="M3 5h14M3 10h14M3 15h14" />}
    </svg>
  )
}

function FeatureIcon({ kind }) {
  const common = { viewBox: '0 0 34 34', className: 'feature-icon', 'aria-hidden': true }

  if (kind === 'accounts') {
    return (
      <svg {...common}>
        <circle cx="17" cy="10" r="4.5" />
        <path d="M8.5 27c.5-5 3.3-8 8.5-8s8 3 8.5 8" />
        <path d="M5.5 16.5c1.4-1.7 3-2.5 5-2.5M28.5 16.5c-1.4-1.7-3-2.5-5-2.5" />
      </svg>
    )
  }

  if (kind === 'quota') {
    return (
      <svg {...common}>
        <path d="M7 27V18M14 27V11M21 27V6M28 27V14" />
        <path d="M5 27h25" />
      </svg>
    )
  }

  return (
    <svg {...common}>
      <path d="M17 4 27 8v7c0 6-4.2 10.2-10 13C7.2 25.2 3 21 3 15V8l14-4Z" />
      <path d="m10.5 17 4 4 8-8" />
    </svg>
  )
}

function AccountIcon({ kind }) {
  const common = { viewBox: '0 0 30 30', className: 'account-icon', 'aria-hidden': true }

  if (kind === 'person') {
    return (
      <svg {...common}>
        <circle cx="15" cy="9" r="4" />
        <path d="M7.5 24c.5-4.8 3.1-7 7.5-7s7 2.2 7.5 7" />
      </svg>
    )
  }

  if (kind === 'briefcase') {
    return (
      <svg {...common}>
        <rect x="5" y="9" width="20" height="15" rx="1.5" />
        <path d="M11 9V6h8v3M5 14h20M13 14v2h4v-2" />
      </svg>
    )
  }

  if (kind === 'flask') {
    return (
      <svg {...common}>
        <path d="M11 5h8M13 5v7l-6 11.5A1 1 0 0 0 8 25h14a1 1 0 0 0 1-1.5L17 12V5" />
        <path d="M9.5 20h11" />
      </svg>
    )
  }

  return (
    <svg {...common}>
      <rect x="6" y="5" width="18" height="20" rx="1.5" />
      <path d="M10 10h2M16 10h2M10 15h2M16 15h2M10 20h2M16 20h2" />
    </svg>
  )
}

function QuotaBar({ value, light = false }) {
  return (
    <span className={`quota-bar${light ? ' quota-bar-light' : ''}`} aria-hidden="true">
      <span style={{ width: `${value}%` }} />
    </span>
  )
}

function AccountRows({ selected, onSelect, compact = false }) {
  return (
    <div className={`account-rows${compact ? ' account-rows-compact' : ''}`}>
      {accounts.map((account) => {
        const active = account.name === selected
        return (
          <button
            className={`account-row${active ? ' account-row-selected' : ''}`}
            key={account.name}
            type="button"
            onClick={() => onSelect(account.name)}
            aria-pressed={active}
          >
            <span className="account-row-icon"><AccountIcon kind={account.kind} /></span>
            <span className="account-row-content">
              <span className="account-row-name">{account.name}</span>
              <QuotaBar value={account.quota} light />
            </span>
            <span className="account-row-quota">{account.quota}%</span>
            <ArrowIcon />
          </button>
        )
      })}
    </div>
  )
}

function ProductWindow({ selected, onSelect, compact = false }) {
  const selectedAccount = accounts.find((account) => account.name === selected) ?? accounts[0]

  return (
    <div className={`product-window${compact ? ' product-window-compact' : ''}`}>
      <div className="product-window-topbar">
        <span className="window-dots" aria-hidden="true"><i /><i /><i /></span>
        <span className="window-title">SwitchGPT</span>
        <span className="window-control" aria-hidden="true">⌘</span>
      </div>
      <div className="product-window-body">
        <div className="usage-summary">
          <span className="usage-summary-value">W&nbsp; {selectedAccount.quota}%</span>
          <span className="usage-summary-meta"><strong>Weekly usage</strong><span>Resets in 4 days</span></span>
          <span className="usage-summary-spark" aria-hidden="true"><i /><i /></span>
        </div>
        <div className="product-label-row"><span>All accounts</span><span>Direct quota</span></div>
        <AccountRows selected={selected} onSelect={onSelect} compact={compact} />
      </div>
    </div>
  )
}

function Header() {
  const [menuOpen, setMenuOpen] = useState(false)

  const closeMenu = () => setMenuOpen(false)

  return (
    <header className="site-header">
      <a className="wordmark" href="#top" onClick={closeMenu}>SwitchGPT</a>
      <nav className={`site-nav${menuOpen ? ' site-nav-open' : ''}`} aria-label="Main navigation">
        <a href="#product" onClick={closeMenu}>Product</a>
        <a href="#safety" onClick={closeMenu}>Safety</a>
        <a href="https://github.com/HuipengXu/SwitchGPT" target="_blank" rel="noreferrer" onClick={closeMenu}>GitHub</a>
      </nav>
      <a className="header-cta" href="https://github.com/HuipengXu/SwitchGPT" target="_blank" rel="noreferrer">
        <span>View on GitHub</span><ArrowIcon />
      </a>
      <button className="menu-button" type="button" aria-label={menuOpen ? 'Close menu' : 'Open menu'} aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>
        <MenuIcon open={menuOpen} />
      </button>
    </header>
  )
}

function Hero({ selected, onSelect }) {
  return (
    <section className="hero section-frame" id="top">
      <div className="hero-copy">
        <h1>See every account at a glance.</h1>
        <p>An open-source macOS alpha for exploring multi-account quota UI with safe mock data.</p>
        <div className="hero-links">
          <a className="text-link" href="#product">Explore the project <ArrowIcon /></a>
          <a className="text-link" href="#safety">Read the safety boundary <ArrowIcon /></a>
        </div>
      </div>
      <div className="hero-product">
        <ProductWindow selected={selected} onSelect={onSelect} />
      </div>
    </section>
  )
}

function ProductSection({ selected, onSelect }) {
  return (
    <section className="product-section section-frame" id="product">
      <div className="product-section-preview">
        <ProductWindow selected={selected} onSelect={onSelect} compact />
      </div>
      <div className="product-section-copy">
        <h2>Usage, without the guesswork.</h2>
        <p>The current alpha uses mock accounts and quota data. A read-only quota adapter is included for review but is not wired into the default app.</p>
        <div className="feature-list">
          <FeatureRow icon="accounts" title="Flexible accounts" copy="Preview any number of mock identities in one simple list." />
          <FeatureRow icon="quota" title="Quota-ready UI" copy="Review weekly usage and an optional five-hour window when data provides it." />
          <FeatureRow icon="safety" title="Safe alpha" copy="Real desktop switching is not included in this build." />
        </div>
      </div>
    </section>
  )
}

function FeatureRow({ icon, title, copy }) {
  return (
    <div className="feature-row">
      <FeatureIcon kind={icon} />
      <div><h3>{title}</h3><p>{copy}</p></div>
    </div>
  )
}

function SafetySection() {
  return (
    <section className="safety-section" id="safety">
      <div className="safety-inner section-frame">
        <div className="safety-copy">
          <h2>Every account,<br />one clear view.</h2>
          <div className="safety-notes">
            <p><span className="note-icon">◇</span>Real switching is not shipped.</p>
            <p><span className="note-icon">&lt;/&gt;</span>Open source. Mock and read-only first.</p>
          </div>
        </div>
        <div className="boundary-flow" aria-label="SwitchGPT safety boundary">
          <BoundaryStep title="Use safe mock data" kind="data" />
          <ArrowIcon />
          <BoundaryStep title="Display quota and status" kind="display" />
          <ArrowIcon />
          <BoundaryStep title="Not shipped" copy="Real switching remains experimental" kind="switch" disabled />
        </div>
      </div>
    </section>
  )
}

function BoundaryStep({ title, copy, kind, disabled = false }) {
  return (
    <div className={`boundary-step${disabled ? ' boundary-step-disabled' : ''}`}>
      {kind === 'switch' ? <span className="switch-illustration"><i /></span> : <BoundaryIcon kind={kind} />}
      <strong>{title}</strong>
      {copy && <span>{copy}</span>}
    </div>
  )
}

function BoundaryIcon({ kind }) {
  return (
    <svg className="boundary-icon" viewBox="0 0 48 48" aria-hidden="true">
      {kind === 'data' ? <><ellipse cx="24" cy="13" rx="14" ry="6" /><path d="M10 13v12c0 3.3 6.3 6 14 6s14-2.7 14-6V13M10 25v11c0 3.3 6.3 6 14 6s14-2.7 14-6V25" /></> : <><rect x="8" y="8" width="32" height="23" rx="1" /><path d="M17 39h14M24 31v8M15 15h18M15 21h10M15 26h5" /><circle cx="33" cy="24" r="4" /></>}
    </svg>
  )
}

function ProcessSection() {
  return (
    <section className="process-section section-frame" id="process">
      <h2>How it works</h2>
      <div className="process-list">
        <ProcessStep number="1" title="Explore" copy="Add mock accounts and evaluate the macOS experience." />
        <ArrowIcon />
        <ProcessStep number="2" title="Review" copy="See weekly quota and optional five-hour usage at a glance." />
        <ArrowIcon />
        <ProcessStep number="3" title="Contribute" copy="Inspect the safety boundaries and help improve the open-source alpha." />
      </div>
    </section>
  )
}

function ProcessStep({ number, title, copy }) {
  return (
    <div className="process-step">
      <span className="process-number">{number}</span>
      <div><h3>{title}</h3><p>{copy}</p></div>
    </div>
  )
}

function Footer() {
  return (
    <footer className="site-footer section-frame">
      <a className="wordmark" href="#top">SwitchGPT</a>
      <span>Built for macOS</span>
      <a href="https://github.com/HuipengXu/SwitchGPT" target="_blank" rel="noreferrer">MIT licensed</a>
    </footer>
  )
}

function App() {
  const [selected, setSelected] = useState('Personal')

  return (
    <>
      <Header />
      <main>
        <Hero selected={selected} onSelect={setSelected} />
        <ProductSection selected={selected} onSelect={setSelected} />
        <SafetySection />
        <ProcessSection />
      </main>
      <Footer />
    </>
  )
}

createRoot(document.getElementById('root')).render(<App />)
