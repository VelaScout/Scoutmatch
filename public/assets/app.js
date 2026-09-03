document.addEventListener('DOMContentLoaded', function () {
  var toggle = document.querySelector('.mobile-toggle');
  var nav = document.querySelector('.site-nav');
  if (!toggle || !nav) return;

  function setOpen(open) {
    nav.classList.toggle('open', open);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    toggle.setAttribute('aria-label', open ? 'Menü schließen' : 'Menü öffnen');
    if ('inert' in HTMLElement.prototype) {
      var isMobile = window.matchMedia('(max-width: 900px)').matches;
      nav.inert = isMobile && !open;
    }
  }

  toggle.addEventListener('click', function () {
    setOpen(!nav.classList.contains('open'));
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && nav.classList.contains('open')) {
      setOpen(false);
      toggle.focus();
    }
  });

  document.addEventListener('click', function (e) {
    if (nav.classList.contains('open') && !nav.contains(e.target) && e.target !== toggle) {
      setOpen(false);
    }
  });

  window.addEventListener('resize', function () {
    if (window.matchMedia('(min-width: 901px)').matches && nav.classList.contains('open')) {
      setOpen(false);
    }
  });
});

/* Scroll-Reveal: Text-/Karten-Blöcke sliden beim Laden bzw. beim Scrollen sanft rein.
   Der Footer ist bewusst ausgenommen (bleibt statisch). Elemente mit class="reveal"
   werden beobachtet; Geschwister innerhalb eines class="reveal-stagger"-Containers
   bekommen automatisch eine kleine, aufsteigende Verzögerung für eine Kaskade. */
function scoutMatchInitReveal(root) {
  var scope = root || document;

  var groups = scope.querySelectorAll('.reveal-stagger');
  groups.forEach(function (group) {
    var children = group.querySelectorAll(':scope > .reveal');
    children.forEach(function (el, i) {
      if (!el.style.transitionDelay) el.style.transitionDelay = (i * 0.08) + 's';
    });
  });

  var items = scope.querySelectorAll('.reveal:not(.in-view)');
  if (!items.length) return;

  if (!('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('in-view'); });
    return;
  }

  if (!window.__scoutMatchRevealObserver) {
    window.__scoutMatchRevealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in-view');
          window.__scoutMatchRevealObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -60px 0px' });
  }

  items.forEach(function (el) { window.__scoutMatchRevealObserver.observe(el); });
}
window.scoutMatchInitReveal = scoutMatchInitReveal;

document.addEventListener('DOMContentLoaded', function () {
  scoutMatchInitReveal();
});

/* Nav an Login-Status anpassen: auf öffentlichen Seiten (Start, Für Spieler,
   Für Vereine, Preise, …) zeigt die Navigation sonst immer "Einloggen" /
   "Registrieren" – auch wenn man bereits eingeloggt ist. Das sieht dann so
   aus, als sei man ausgeloggt, obwohl die Session serverseitig weiterhin
   gültig ist. Ersetzt die beiden Links stattdessen durch "Mein Bereich" /
   "Ausloggen" und blendet die für die eigene Rolle irrelevante
   Marketing-Seite aus. Auf Dashboard-Seiten (eigene Nav ohne diese Links)
   passiert dadurch nichts – die Selektoren finden dort einfach nichts.*/
function scoutMatchSyncNav() {
  var nav = document.getElementById('siteNav');
  if (!nav) return;

  fetch('/api/auth/me', { credentials: 'same-origin' })
    .then(function (r) { return r.json(); })
    .then(function (info) {
      if (!info.authenticated) return;

      var dashboardHref = {
        player: 'spieler-dashboard.html',
        club: 'vereins-dashboard.html',
        admin: 'admin.html'
      }[info.role] || 'index.html';

      var loginLink = nav.querySelector('a[href="login.html"]');
      if (loginLink) {
        loginLink.textContent = 'Mein Bereich';
        loginLink.setAttribute('href', dashboardHref);
        loginLink.classList.remove('active');
      }

      var registerLink = nav.querySelector('a.cta');
      if (registerLink) {
        registerLink.textContent = 'Ausloggen';
        registerLink.removeAttribute('href');
        registerLink.setAttribute('role', 'button');
        registerLink.style.cursor = 'pointer';
        registerLink.addEventListener('click', function (e) {
          e.preventDefault();
          fetch('/api/auth/csrf-token', { credentials: 'same-origin' })
            .then(function (r) { return r.json(); })
            .then(function (d) {
              return fetch('/api/auth/logout', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'X-CSRF-Token': d.csrf_token }
              });
            })
            .then(function () { location.href = 'index.html'; });
        });
      }

      var hideLinks = { player: ['fuer-vereine.html'], club: ['fuer-spieler.html'], admin: ['fuer-spieler.html', 'fuer-vereine.html'] };
      (hideLinks[info.role] || []).forEach(function (href) {
        var el = nav.querySelector('a[href="' + href + '"]');
        if (el) el.style.display = 'none';
      });
    })
    .catch(function () {});
}
document.addEventListener('DOMContentLoaded', scoutMatchSyncNav);

/* Passwort-Felder: kein Leerzeichen zulassen (site-weit, verhindert
   versehentliche Leerzeichen am Anfang/Ende oder mittendrin). */
document.addEventListener('keydown', function (e) {
  if (e.key === ' ' && e.target && e.target.matches && e.target.matches('input[type="password"]')) {
    e.preventDefault();
  }
});

/* Passwort-Stärkeanzeige: auf jedem <input type="password"
   data-password-strength> wird automatisch ein Balken mit Einschätzung
   ergänzt. Nur auf Feldern für NEUE Passwörter einsetzen (Registrierung,
   Passwort ändern/zurücksetzen) – nicht beim reinen Login. */
function scoutMatchPasswordScore(pw) {
  if (!pw) return 0;
  var score = 0;
  if (pw.length >= 8) score++;
  if (pw.length >= 12) score++;
  if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) score++;
  if (/[0-9]/.test(pw)) score++;
  if (/[^A-Za-z0-9]/.test(pw)) score++;
  return score;
}

function scoutMatchInitPasswordStrength(root) {
  var scope = root || document;
  var LEVELS = [
    { label: '', color: 'transparent', width: '4%' },
    { label: 'Sehr schwach', color: '#c0392b', width: '20%' },
    { label: 'Schwach', color: '#e67e22', width: '40%' },
    { label: 'Okay', color: '#d4ac0d', width: '60%' },
    { label: 'Stark', color: '#27ae60', width: '80%' },
    { label: 'Sehr stark', color: '#1b8a5a', width: '100%' }
  ];

  scope.querySelectorAll('input[data-password-strength]').forEach(function (input) {
    if (input.dataset.strengthWired) return;
    input.dataset.strengthWired = '1';

    var wrap = document.createElement('div');
    wrap.className = 'pw-strength';
    wrap.innerHTML = '<div class="pw-strength-track"><div class="pw-strength-fill"></div></div><span class="pw-strength-label"></span>';
    var anchor = input.closest('.password-field') || input;
    anchor.insertAdjacentElement('afterend', wrap);

    var fill = wrap.querySelector('.pw-strength-fill');
    var label = wrap.querySelector('.pw-strength-label');

    input.addEventListener('input', function () {
      var level = LEVELS[scoutMatchPasswordScore(input.value)];
      fill.style.width = input.value ? level.width : '0%';
      fill.style.background = level.color;
      label.textContent = input.value ? level.label : '';
      label.style.color = level.color;
    });
  });
}
document.addEventListener('DOMContentLoaded', function () {
  scoutMatchInitPasswordStrength();
});
