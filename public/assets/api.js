/* Kleiner Fetch-Helfer für die ScoutMatch-API.
   Wichtig: Diese Client-seitigen Weiterleitungen (requireRole) sind reiner
   UX-Komfort. Die eigentliche Zugriffskontrolle passiert serverseitig in
   jeder Route (siehe role_required-Decorator im Backend) – ein Nutzer, der
   das JS deaktiviert oder umgeht, bekommt trotzdem 401/403 vom Server. */
window.ScoutMatchAPI = (function () {
  var csrfToken = null;

  function getCsrfToken() {
    if (csrfToken) return Promise.resolve(csrfToken);
    return fetch('/api/auth/csrf-token', { credentials: 'same-origin' })
      .then(function (r) { return r.json(); })
      .then(function (d) { csrfToken = d.csrf_token; return csrfToken; });
  }

  function request(method, url, body) {
    var isWrite = ['POST', 'PUT', 'PATCH', 'DELETE'].indexOf(method) !== -1;
    return (isWrite ? getCsrfToken() : Promise.resolve(null)).then(function (token) {
      var opts = { method: method, credentials: 'same-origin', headers: {} };
      if (token) opts.headers['X-CSRF-Token'] = token;
      if (body !== undefined) {
        opts.headers['Content-Type'] = 'application/json';
        opts.body = JSON.stringify(body);
      }
      return fetch(url, opts);
    }).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) {
        return { ok: res.ok, status: res.status, data: data };
      });
    });
  }

  function me() {
    return fetch('/api/auth/me', { credentials: 'same-origin' }).then(function (r) { return r.json(); });
  }

  function requireRole(roles) {
    return me().then(function (info) {
      if (!info.authenticated) {
        location.href = 'login.html';
        return null;
      }
      if (roles && roles.indexOf(info.role) === -1) {
        location.href = 'login.html';
        return null;
      }
      return info;
    });
  }

  return {
    get: function (url) { return request('GET', url); },
    post: function (url, body) { return request('POST', url, body); },
    put: function (url, body) { return request('PUT', url, body); },
    del: function (url) { return request('DELETE', url); },
    me: me,
    requireRole: requireRole
  };
})();
