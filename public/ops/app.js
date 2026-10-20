(function () {
  "use strict";

  const firebaseConfig = {
    apiKey: "AIzaSyCDNwTxbqD_6llHQ2bGSOEBXY1cy2x3pbA",
    authDomain: "memoirai-7db06.firebaseapp.com",
    projectId: "memoirai-7db06",
    storageBucket: "memoirai-7db06.firebasestorage.app",
    messagingSenderId: "171451774395"
  };

  firebase.initializeApp(firebaseConfig);
  const auth = firebase.auth();
  const functions = firebase.app().functions("us-central1");
  const listOrdersFn = functions.httpsCallable("adminListPrintOrders");
  const fulfillFn = functions.httpsCallable("fulfillOrder");
  const syncLuluFn = functions.httpsCallable("adminSyncOrderFromLulu");
  const listUsersFn = functions.httpsCallable("adminListUsers");
  const listMemoriesFn = functions.httpsCallable("adminListUserMemories");
  const listBooksFn = functions.httpsCallable("adminListUserBooks");
  const verifyPdfsFn = functions.httpsCallable("adminVerifyOrderPdfs");

  let state = { orders: [], stats: null, autoFulfill: false, userCount: 0 };

  const $ = (id) => document.getElementById(id);

  function toast(msg, type) {
    const el = document.createElement("div");
    el.className = "toast" + (type ? " " + type : "");
    el.textContent = msg;
    $("toasts").appendChild(el);
    setTimeout(() => el.remove(), 4500);
  }

  function money(cents, currency) {
    if (cents == null || Number.isNaN(cents)) return "—";
    return new Intl.NumberFormat("en-US", { style: "currency", currency: currency || "usd" }).format(cents / 100);
  }

  function formatAddress(a) {
    if (!a || !a.street1) return "—";
    return [
      a.name,
      a.street1 + (a.street2 ? ", " + a.street2 : ""),
      [a.city, a.stateCode, a.postcode].filter(Boolean).join(", "),
      a.countryCode
    ].filter(Boolean).join(" · ");
  }

  function chipClass(status) {
    const s = (status || "").replace(/\s/g, "_");
    const known = ["paid", "lulu_failed", "submitted_to_printer", "printing", "shipped", "delivered", "pending_fulfillment"];
    return known.includes(s) ? "chip-" + s : "chip-default";
  }

  function chipHtml(status) {
    return '<span class="chip ' + chipClass(status) + '">' + (status || "unknown") + "</span>";
  }

  function flagBadgesHtml(o) {
    const badges = [];
    if (o.disputeStatus === "disputed") {
      badges.push('<span class="badge-fail" title="Stripe dispute opened">DISPUTED</span>');
    }
    if (o.refundStatus === "refunded") {
      badges.push('<span class="badge-fail" title="Fully refunded">REFUNDED</span>');
    } else if (o.refundStatus === "partially_refunded") {
      badges.push('<span class="badge-warn" title="Partially refunded">PARTIAL REFUND</span>');
    }
    if (o.fulfillmentHold) {
      badges.push('<span class="badge-warn" title="Do not print — refund/dispute hold">HOLD</span>');
    }
    if (o.isFulfillmentIncident) {
      badges.push('<span class="badge-fail" title="Paid checkout requires manual remediation">INCIDENT</span>');
    }
    return badges.length ? " " + badges.join(" ") : "";
  }

  function stripeLink(pi) {
    return pi ? "https://dashboard.stripe.com/payments/" + encodeURIComponent(pi) : null;
  }

  function firestoreOrderLink(userId, orderId) {
    return "https://console.firebase.google.com/project/memoirai-7db06/firestore/databases/-default-/data/~2Fusers~2F" +
      encodeURIComponent(userId) + "~2Forders~2F" + encodeURIComponent(orderId);
  }

  function firestoreIncidentLink(incidentId) {
    return "https://console.firebase.google.com/project/memoirai-7db06/firestore/databases/-default-/data/~2FfulfillmentIncidents~2F" +
      encodeURIComponent(incidentId);
  }

  function luluJobsLink() {
    return "https://developers.lulu.com";
  }

  function esc(s) {
    if (s == null) return "";
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;");
  }

  function formatDate(iso) {
    if (!iso) return "—";
    try {
      const date = new Date(iso);
      return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString();
    } catch (_) {
      return iso;
    }
  }

  async function loadOrders() {
    const res = await listOrdersFn({ limit: 250 });
    const data = res.data || {};
    state.orders = data.all || [];
    state.stats = data.stats || {};
    state.autoFulfill = Boolean(data.autoFulfillEnabled);
    state.userCount = data.userCount || 0;
    state.pendingCount = data.pendingCount || 0;
    state.fulfillmentIncidentCount = data.stats?.fulfillmentIncidents || 0;
    return data;
  }

  let _lastProfitCents = null;

  function renderStats(pulseProfit) {
    const s = state.stats || {};
    const rev = money(s.totalRevenueCents, "usd");
    const profit = money(s.totalProfitCents, "usd");
    $("stats-row").innerHTML =
      statCard("Total orders", s.totalOrders, "") +
      statCard("Needs print", s.needsPrint, "accent") +
      statCard("Paid holds", s.fulfillmentIncidents || 0, "") +
      statCard("Revenue", rev, "ok") +
      statCard("Firebase users", state.userCount, "") +
      statCard("Total profit", profit, "profit");
    if (pulseProfit || (_lastProfitCents != null && s.totalProfitCents !== _lastProfitCents)) {
      const cards = $("stats-row").querySelectorAll(".stat-card.profit");
      cards.forEach((c) => {
        c.classList.remove("pulse");
        c.offsetHeight;
        c.classList.add("pulse");
      });
    }
    _lastProfitCents = s.totalProfitCents;
    const flag = $("auto-flag");
    if (state.autoFulfill) {
      flag.textContent = "Auto-print ON";
      flag.className = "flag warn";
    } else {
      flag.textContent = "Manual approval";
      flag.className = "flag";
    }
    const badge = $("nav-queue-badge");
    const n = s.needsPrint || 0;
    if (n > 0) {
      badge.hidden = false;
      badge.textContent = String(n);
    } else {
      badge.hidden = true;
    }
    $("last-updated").textContent = "Updated " + new Date().toLocaleString();
    $("orders-count-label").textContent = (state.orders.length) + " orders loaded";
  }

  function statCard(label, value, mod) {
    return '<div class="stat-card ' + (mod || "") + '"><div class="label">' + esc(label) +
      '</div><div class="value">' + esc(String(value ?? "—")) + "</div></div>";
  }

  function orderCardHtml(o, { showActions }) {
    const title = o.printTitle || o.bookDisplayName || "Untitled";
    const cover = o.coverURL
      ? '<img src="' + esc(o.coverURL) + '" alt="" />'
      : "No cover";
    const stripe = stripeLink(o.stripePaymentIntentId);
    let actions = "";
    if (showActions && o.needsPrintAction) {
      actions =
        '<button type="button" class="btn btn-cta print-btn" data-oid="' + esc(o.orderId) +
        '" data-uid="' + esc(o.userId) + '">Print → Lulu</button>';
    } else if (o.luluPrintJobId) {
      actions =
        '<button type="button" class="btn btn-ghost btn-sm sync-btn" data-oid="' + esc(o.orderId) +
        '" data-uid="' + esc(o.userId) + '">Sync Lulu status</button>' +
        '<p class="meta-line">Job ' + esc(o.luluPrintJobId) + "</p>";
    }
    return (
      '<article class="order-card" data-order-id="' + esc(o.orderId) + '">' +
        '<div class="cover-lg">' + cover + "</div>" +
        '<div>' +
          "<h4>" + esc(title) + "</h4>" +
          chipHtml(o.status) + flagBadgesHtml(o) +
          '<p class="meta-line">' + money(o.totalCents, o.currency) + " · " + esc(o.productTitle || "Print") +
          " · qty " + (o.quantity || 1) + " · " + esc(o.shippingLevel || "MAIL") + "</p>" +
          '<p class="meta-line">' + esc(o.customerEmail || "") + "</p>" +
          '<p class="meta-line">' + esc(formatAddress(o.shippingAddress)) + "</p>" +
          (o.luluError ? '<div class="alert">' + esc(o.luluError) + "</div>" : "") +
          '<div class="link-row">' +
            linkIf(o.pdfURL, "Interior PDF") +
            linkIf(o.coverURL, "Cover PDF") +
            linkIf(stripe, "Stripe") +
            '<a href="#" class="detail-link" data-oid="' + esc(o.orderId) + '">Details</a>' +
          "</div>" +
        "</div>" +
        '<div style="display:flex;flex-direction:column;gap:0.5rem;align-items:flex-end">' +
          actions +
        "</div>" +
      "</article>"
    );
  }

  function linkIf(href, label) {
    if (!href) return "";
    try {
      const url = new URL(href);
      if (!["https:", "http:"].includes(url.protocol)) return "";
      return '<a href="' + esc(url.href) + '" target="_blank" rel="noopener">' + esc(label) + "</a>";
    } catch (_) { return ""; }
  }

  function renderPendingLists() {
    const pending = state.orders.filter((o) => o.needsPrintAction);
    const dash = $("dash-pending");
    const queue = $("queue-list");
    const html = pending.length
      ? pending.map((o) => orderCardHtml(o, { showActions: true })).join("")
      : '<div class="empty-state">No orders waiting for Print.</div>';
    dash.innerHTML = html;
    queue.innerHTML = html;
    bindOrderActions(dash);
    bindOrderActions(queue);
  }

  function filteredOrders() {
    const q = ($("order-search").value || "").trim().toLowerCase();
    const st = $("order-filter").value;
    return state.orders.filter((o) => {
      if (st && o.status !== st) return false;
      if (!q) return true;
      const hay = [
        o.orderId, o.customerEmail, o.printTitle, o.bookDisplayName, o.userId, o.luluPrintJobId
      ].join(" ").toLowerCase();
      return hay.includes(q);
    });
  }

  function renderOrdersTable() {
    const rows = filteredOrders();
    const tbody = $("orders-tbody");
    if (!rows.length) {
      tbody.innerHTML = '<tr><td colspan="7" class="empty-state">No matching orders</td></tr>';
      return;
    }
    tbody.innerHTML = rows.map((o) => {
      const title = o.printTitle || o.bookDisplayName || "—";
      const thumb = o.coverURL
        ? '<img class="thumb" src="' + esc(o.coverURL) + '" alt="" />'
        : '<span class="thumb"></span>';
      const action = o.needsPrintAction
        ? '<button type="button" class="btn btn-cta btn-sm print-btn" data-oid="' + esc(o.orderId) +
          '" data-uid="' + esc(o.userId) + '">Print</button>'
        : (o.luluPrintJobId
          ? '<button type="button" class="btn btn-ghost btn-sm sync-btn" data-oid="' + esc(o.orderId) +
            '" data-uid="' + esc(o.userId) + '">Sync</button>'
          : "");
      return (
        "<tr class=\"clickable\" data-oid=\"" + esc(o.orderId) + "\">" +
          "<td>" + thumb + "</td>" +
          "<td><strong>" + esc(title) + "</strong><br><span style=\"color:var(--muted);font-size:0.75rem\">" +
            esc(o.orderId.slice(0, 24)) + "…</span></td>" +
          "<td>" + esc(o.customerEmail || "—") + "</td>" +
          "<td>" + chipHtml(o.status) + flagBadgesHtml(o) + "</td>" +
          "<td>" + money(o.totalCents, o.currency) + "</td>" +
          "<td>" + formatDate(o.createdAt) + "</td>" +
          "<td>" + action + "</td>" +
        "</tr>"
      );
    }).join("");
    bindOrderActions(tbody);
    tbody.querySelectorAll("tr.clickable").forEach((tr) => {
      tr.addEventListener("click", (e) => {
        if (e.target.closest("button, a")) return;
        const id = tr.getAttribute("data-oid");
        const o = state.orders.find((x) => x.orderId === id);
        if (o) openDrawer(o);
      });
    });
  }

  function openDrawer(o) {
    const stripe = stripeLink(o.stripePaymentIntentId);
    $("drawer-body").innerHTML =
      "<h3>" + esc(o.printTitle || o.bookDisplayName || "Order") + "</h3>" +
      chipHtml(o.status) + flagBadgesHtml(o) +
      "<p><strong>Order ID</strong><br><code style=\"font-size:0.8rem;word-break:break-all\">" + esc(o.orderId) + "</code></p>" +
      "<p><strong>User ID</strong><br><code style=\"font-size:0.8rem;word-break:break-all\">" + esc(o.userId) + "</code></p>" +
      "<p><strong>Customer</strong><br>" + esc(o.customerEmail || "—") + "</p>" +
      "<p><strong>Shipping</strong><br>" + esc(formatAddress(o.shippingAddress)) + "</p>" +
      "<p><strong>Product</strong><br>" + esc(o.productTitle || "—") + " · " + esc(o.bookVersionId || "") + "</p>" +
      "<p><strong>Total</strong><br>" + money(o.totalCents, o.currency) + "</p>" +
      (o.luluError ? '<div class="alert">' + esc(o.luluError) + "</div>" : "") +
      '<div class="link-row" style="margin:1rem 0">' +
        linkIf(o.pdfURL, "Interior PDF") +
        linkIf(o.coverURL, "Cover PDF") +
        linkIf(stripe, "Stripe payment") +
        '<a href="' + (o.isFulfillmentIncident
          ? firestoreIncidentLink(o.orderId)
          : firestoreOrderLink(o.userId, o.orderId)) + '" target="_blank" rel="noopener">Firestore</a>' +
        '<a href="' + luluJobsLink() + '" target="_blank" rel="noopener">Lulu portal</a>' +
      "</div>" +
      '<div id="drawer-actions"></div>';
    const actions = $("drawer-actions");
    if (o.needsPrintAction) {
      const b = document.createElement("button");
      b.className = "btn btn-cta btn-block";
      b.textContent = "Print — send to Lulu";
      b.onclick = () => runPrint(o.orderId, o.userId, b);
      actions.appendChild(b);
    }
    if (o.luluPrintJobId) {
      const s = document.createElement("button");
      s.className = "btn btn-ghost btn-block";
      s.style.marginTop = "0.5rem";
      s.textContent = "Sync status from Lulu";
      s.onclick = () => runSync(o.orderId, o.userId, s);
      actions.appendChild(s);
      const p = document.createElement("p");
      p.className = "meta-line";
      p.textContent = "Lulu job: " + o.luluPrintJobId;
      actions.appendChild(p);
      if (o.luluTrackingUrl) {
        actions.insertAdjacentHTML("beforeend", linkIf(o.luluTrackingUrl, "Tracking link"));
      }
    }
    $("user-id-input").value = o.userId || "";
    $("drawer-backdrop").classList.add("open");
  }

  function closeDrawer() {
    $("drawer-backdrop").classList.remove("open");
  }

  function bindOrderActions(root) {
    root.querySelectorAll(".print-btn").forEach((btn) => {
      btn.onclick = (e) => {
        e.stopPropagation();
        runPrint(btn.getAttribute("data-oid"), btn.getAttribute("data-uid"), btn);
      };
    });
    root.querySelectorAll(".sync-btn").forEach((btn) => {
      btn.onclick = (e) => {
        e.stopPropagation();
        runSync(btn.getAttribute("data-oid"), btn.getAttribute("data-uid"), btn);
      };
    });
    root.querySelectorAll(".detail-link").forEach((a) => {
      a.onclick = (e) => {
        e.preventDefault();
        const id = a.getAttribute("data-oid");
        const o = state.orders.find((x) => x.orderId === id);
        if (o) openDrawer(o);
      };
    });
  }

  // ── PDF Download helper ───────────────────────────────────────────────────

  const PDF_PROXY_URL = "https://admingetorderpdf-6gimnq7eba-uc.a.run.app";

  async function downloadOrderPdf(orderId, userId, type) {
    const user = auth.currentUser;
    if (!user) { toast("Not signed in", "err"); return; }
    const token = await user.getIdToken();
    const url = `${PDF_PROXY_URL}?orderId=${encodeURIComponent(orderId)}&userId=${encodeURIComponent(userId)}&type=${type}`;
    const a = document.createElement("a");
    a.href = url;
    a.target = "_blank";
    a.rel = "noopener";
    // Attach token via fetch + blob so the browser sends the Authorization header
    toast("Fetching " + type + " PDF…");
    try {
      const resp = await fetch(url, { headers: { Authorization: "Bearer " + token } });
      if (!resp.ok) {
        const txt = await resp.text();
        toast("Download failed: " + txt, "err");
        return;
      }
      const blob = await resp.blob();
      const blobUrl = URL.createObjectURL(blob);
      const dl = document.createElement("a");
      dl.href = blobUrl;
      dl.download = type + ".pdf";
      document.body.appendChild(dl);
      dl.click();
      dl.remove();
      setTimeout(() => URL.revokeObjectURL(blobUrl), 10000);
    } catch (e) {
      toast("Download failed: " + (e.message || e), "err");
    }
  }

  // ── PDF Verify Modal ──────────────────────────────────────────────────────

  let _verifyOrderId = null;
  let _verifyUserId = null;
  let _verifyAllPass = false;
  let _verifyData = null;

  function fmtBytes(n) {
    if (n == null) return "—";
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB";
    return (n / (1024 * 1024)).toFixed(2) + " MB";
  }

  window.__verifyDownload = (type) => {
    if (_verifyOrderId && _verifyUserId) {
      downloadOrderPdf(_verifyOrderId, _verifyUserId, type);
    }
  };

  function openVerifyModal(orderId, userId) {
    _verifyOrderId = orderId;
    _verifyUserId = userId;
    _verifyAllPass = false;

    const body = $("verify-modal-body");
    const footer = $("verify-modal-footer");
    const confirmBtn = $("verify-confirm-btn");
    body.innerHTML = '<div class="verify-loading"><span class="spinner"></span> Checking PDFs…</div>';
    footer.style.display = "none";
    confirmBtn.disabled = true;
    $("verify-modal-backdrop").style.display = "flex";

    verifyPdfsFn({ orderId, userId }).then((res) => {
      const d = res.data || {};
      _verifyData = d;
      renderVerifyResults(d);
    }).catch((e) => {
      body.innerHTML = '<div class="alert">' + esc(e.message || String(e)) + "</div>";
      footer.style.display = "flex";
      confirmBtn.disabled = true;
      confirmBtn.style.opacity = "0.45";
      confirmBtn.style.cursor = "not-allowed";
      confirmBtn.textContent = "Checks failed";
    });
  }

  function renderVerifyResults(d) {
    const dimCheck = d.coverDimensionCheck || {};
    const interiorOk = d.interiorExists;
    const coverOk = d.coverExists;
    const dimPass = dimCheck.pass === true;
    _verifyAllPass = interiorOk && coverOk && dimPass;

    let html = "";

    // Interior PDF block
    html += '<div class="verify-check">';
    html += '<div class="verify-check-head">';
    html += "<strong>Interior PDF</strong>";
    html += d.interiorExists
      ? '<span class="badge-pass">EXISTS</span>'
      : '<span class="badge-fail">MISSING</span>';
    html += "</div>";
    html += '<table class="verify-table">';
    html += "<tr><td>File size</td><td>" + fmtBytes(d.interiorFileSizeBytes) + "</td></tr>";
    html += "<tr><td>Pages (PDF)</td><td>" + (d.interiorPageCount != null ? d.interiorPageCount : "—") + "</td></tr>";
    html += "<tr><td>Pages (order)</td><td>" + (d.pageCount != null ? d.pageCount : "—") + "</td></tr>";
    html += "<tr><td>POD package</td><td>" + esc(d.podPackageId || "—") + "</td></tr>";
    html += "</table>";
    if (d.interiorExists) {
      html += '<button type="button" class="btn btn-ghost btn-sm" style="margin-top:0.5rem" onclick="window.__verifyDownload(\'interior\')">↓ Download interior PDF</button>';
    } else {
      html += '<p class="verify-missing">Interior PDF missing from storage — cannot fulfill.</p>';
    }
    html += "</div>";

    // Cover PDF block
    html += '<div class="verify-check">';
    html += '<div class="verify-check-head">';
    html += "<strong>Cover PDF</strong>";
    html += d.coverExists
      ? '<span class="badge-pass">EXISTS</span>'
      : '<span class="badge-fail">MISSING</span>';
    if (d.coverExists) {
      html += dimPass ? '<span class="badge-pass">DIMS OK</span>' : '<span class="badge-fail">DIMS FAIL</span>';
    }
    html += "</div>";
    html += '<table class="verify-table">';
    html += "<tr><td>File size</td><td>" + fmtBytes(d.coverFileSizeBytes) + "</td></tr>";
    if (dimCheck.error) {
      html += '<tr><td>Dimension check</td><td class="verify-missing">' + esc(dimCheck.error) + "</td></tr>";
    } else if (dimCheck.expectedWidth != null) {
      html += "<tr><td>Expected (Lulu)</td><td>" +
        dimCheck.expectedWidth + " × " + dimCheck.expectedHeight + " in</td></tr>";
      html += "<tr><td>Actual (PDF)</td><td>" +
        dimCheck.actualWidth + " × " + dimCheck.actualHeight + " in</td></tr>";
      html += "<tr><td>Tolerance</td><td>± " + dimCheck.toleranceIn + " in</td></tr>";
      html += "<tr><td>Lulu env</td><td>" + esc(dimCheck.luluEnvironment || "—") + "</td></tr>";
    }
    html += "</table>";
    if (d.coverExists) {
      html += '<button type="button" class="btn btn-ghost btn-sm" style="margin-top:0.5rem" onclick="window.__verifyDownload(\'cover\')">↓ Download cover PDF</button>';
    } else {
      html += '<p class="verify-missing">Cover PDF missing from storage — cannot fulfill.</p>';
    }
    if (!dimPass && d.coverExists && !dimCheck.error) {
      html += '<p style="color:var(--danger);font-size:0.82rem;margin-top:0.5rem">Cover dimensions do not match Lulu\'s spec. The print job will be rejected. Regenerate the cover PDF before sending.</p>';
    }
    html += "</div>";

    // Cost section
    html += '<div class="verify-check">';
    html += '<div class="verify-check-head"><strong>Cost estimate</strong></div>';
    html += '<table class="verify-table">';
    if (d.customerPaidCents != null) {
      html += "<tr><td>Customer paid you</td><td><strong>" + money(d.customerPaidCents, d.customerCurrency) + "</strong></td></tr>";
    }
    const est = d.luluCostEstimate || {};
    if (est.error) {
      html += '<tr><td>Lulu charge</td><td class="verify-missing">' + esc(est.error) + "</td></tr>";
    } else if (est.totalCostInclTax != null) {
      const luluTotal = parseFloat(est.totalCostInclTax);
      html += "<tr><td>Lulu charge (you pay)</td><td><strong>" + est.currency + " " + luluTotal.toFixed(2) + "</strong></td></tr>";
      if (est.lineItemCostDollars != null) html += "<tr><td>Print cost</td><td>" + est.currency + " " + est.lineItemCostDollars + "</td></tr>";
      if (est.shippingCostDollars != null) html += "<tr><td>Shipping</td><td>" + est.currency + " " + est.shippingCostDollars + "</td></tr>";
      if (d.customerPaidCents != null) {
        const margin = (d.customerPaidCents / 100) - luluTotal;
        const marginStyle = margin >= 0 ? "color:var(--success);font-weight:600" : "color:var(--danger);font-weight:600";
        html += '<tr><td>Your margin</td><td style="' + marginStyle + '">' + (margin >= 0 ? "+" : "") + margin.toFixed(2) + " " + est.currency.toUpperCase() + "</td></tr>";
      }
      if (est.luluEnvironment) html += "<tr><td>Lulu env</td><td>" + esc(est.luluEnvironment) + "</td></tr>";
    } else {
      html += "<tr><td>Lulu charge</td><td>—</td></tr>";
    }
    html += "</table></div>";

    // Summary line
    if (_verifyAllPass) {
      html += '<div style="background:var(--success-bg);color:var(--success);border-radius:8px;padding:0.75rem 1rem;font-weight:600;font-size:0.9rem">All checks passed — ready to send to Lulu.</div>';
    } else {
      html += '<div style="background:var(--danger-bg);color:var(--danger);border-radius:8px;padding:0.75rem 1rem;font-weight:600;font-size:0.9rem">One or more checks failed. Sending to Lulu will likely result in a rejected print job.</div>';
    }

    $("verify-modal-body").innerHTML = html;
    $("verify-modal-footer").style.display = "flex";
    const confirmBtn = $("verify-confirm-btn");
    confirmBtn.disabled = !_verifyAllPass;
    confirmBtn.style.opacity = _verifyAllPass ? "1" : "0.45";
    confirmBtn.style.cursor = _verifyAllPass ? "pointer" : "not-allowed";
    confirmBtn.textContent = _verifyAllPass ? "Send to Lulu →" : "Checks failed";
  }

  function closeVerifyModal() {
    $("verify-modal-backdrop").style.display = "none";
    _verifyOrderId = null;
    _verifyUserId = null;
    _verifyAllPass = false;
    _verifyData = null;
  }

  async function runPrint(orderId, userId, btn) {
    openVerifyModal(orderId, userId);
  }

  function showProfitCelebration(profitDollars) {
    const overlay = $("profit-overlay");
    const amountEl = $("profit-amount");
    const coinsEl = $("profit-coins");

    amountEl.textContent = (profitDollars >= 0 ? "+" : "") +
      new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(profitDollars);

    // Spawn floating coin emojis
    coinsEl.innerHTML = "";
    const symbols = ["💵", "💚", "🤑", "💸", "✨"];
    for (let i = 0; i < 18; i++) {
      const coin = document.createElement("span");
      coin.className = "coin";
      coin.textContent = symbols[i % symbols.length];
      coin.style.left = (5 + Math.random() * 90) + "%";
      coin.style.bottom = (Math.random() * 15) + "%";
      const dur = (1.4 + Math.random() * 1.4).toFixed(2) + "s";
      const delay = (Math.random() * 0.8).toFixed(2) + "s";
      coin.style.animation = `coin-float ${dur} ${delay} ease-out forwards`;
      coinsEl.appendChild(coin);
    }

    overlay.style.display = "flex";
    // Reset animation
    overlay.style.animation = "none";
    overlay.offsetHeight; // reflow
    overlay.style.animation = "";

    setTimeout(() => { overlay.style.display = "none"; }, 2900);
  }

  async function doFulfill() {
    const orderId = _verifyOrderId;
    const userId = _verifyUserId;
    const confirmBtn = $("verify-confirm-btn");
    const orig = confirmBtn.textContent;
    confirmBtn.disabled = true;
    confirmBtn.innerHTML = '<span class="spinner"></span> Sending…';
    try {
      const res = await fulfillFn({ orderId, userId });
      const d = res.data || {};
      const statusStr = (typeof d.status === "string") ? d.status : "ok";
      toast("Sent to Lulu. Job " + (d.luluJobId || "—") + " · " + statusStr, "ok");
      // Compute profit from the verify data captured before submission
      const vd = _verifyData || {};
      const est = vd.luluCostEstimate || {};
      if (vd.customerPaidCents != null && est.totalCostInclTax != null) {
        const profitDollars = (vd.customerPaidCents / 100) - parseFloat(est.totalCostInclTax);
        closeVerifyModal();
        closeDrawer();
        showProfitCelebration(profitDollars);
      } else {
        closeVerifyModal();
        closeDrawer();
      }
      await refreshAll(true);
    } catch (e) {
      toast("Print failed: " + (e.message || e), "err");
      confirmBtn.disabled = false;
      confirmBtn.textContent = orig;
    }
  }

  async function runSync(orderId, userId, btn) {
    const orig = btn.textContent;
    btn.disabled = true;
    btn.textContent = "Syncing…";
    try {
      await syncLuluFn({ orderId, userId });
      toast("Lulu status synced", "ok");
      await refreshAll();
    } catch (e) {
      toast("Sync failed: " + (e.message || e), "err");
    } finally {
      btn.disabled = false;
      btn.textContent = orig;
    }
  }

  async function refreshAll(pulseProfit) {
    try {
      await loadOrders();
      renderStats(pulseProfit);
      renderPendingLists();
      renderOrdersTable();
    } catch (e) {
      toast("Load failed: " + (e.message || e), "err");
    }
  }

  let browserEpoch = 0;
  let usersRequest = 0;
  let contentRequest = 0;
  let usersLoaded = false;
  let users = [];
  let usersCursor = null;
  let usersLoading = false;
  let usersRetryAppend = false;
  let selectedUser = null;
  const content = {
    books: { items: [], cursor: null, loading: false, retryAppend: false, request: 0 },
    memories: { items: [], cursor: null, loading: false, retryAppend: false, request: 0 }
  };

  function mergeItems(previous, incoming, key) {
    const byId = new Map(previous.map((item) => [item[key], item]));
    incoming.forEach((item) => byId.set(item[key], item));
    return [...byId.values()];
  }

  function newestFirst(items, key) {
    return [...items].sort((a, b) => {
      const aDate = Date.parse(a.createdAt) || 0;
      const bDate = Date.parse(b.createdAt) || 0;
      return bDate - aDate || String(a[key]).localeCompare(String(b[key]));
    });
  }

  function renderUsers() {
    $("users-tbody").innerHTML = users.map((user) => '<tr' + (selectedUser?.userId === user.userId ? ' class="selected"' : '') + '><td>' +
      '<button type="button" class="user-open" data-uid="' + esc(user.userId) + '">' + esc(user.displayName || user.email || (user.isAnonymous ? "Guest account" : user.userId)) + '</button>' +
      '<div class="meta-line">' + esc(user.email || user.userId) + '</div></td><td>' + esc(formatDate(user.createdAt)) + '</td><td>' + esc(formatDate(user.lastActiveAt)) + '</td></tr>').join("");
    $("users-tbody").querySelectorAll(".user-open").forEach((button) => {
      button.onclick = () => openUser(users.find((user) => user.userId === button.dataset.uid));
    });
  }

  async function loadUsers(append = false) {
    if (append && usersLoading) return;
    const request = ++usersRequest;
    const epoch = browserEpoch;
    const sort = $("user-sort").value;
    usersLoading = true;
    usersRetryAppend = append;
    $("more-users").hidden = true;
    $("retry-users").hidden = true;
    $("users-status").textContent = "Loading users…";
    if (!append) { users = []; usersCursor = null; renderUsers(); }
    try {
      const result = await listUsersFn({ sort, limit: 25, ...(append && usersCursor ? { cursor: usersCursor } : {}) });
      if (epoch !== browserEpoch || request !== usersRequest) return;
      users = mergeItems(append ? users : [], result.data?.users || [], "userId");
      usersCursor = result.data?.nextCursor || null;
      usersLoaded = true;
      renderUsers();
      $("users-status").textContent = users.length ? "" : "No accounts found.";
      $("more-users").hidden = !usersCursor;
    } catch (error) {
      if (epoch !== browserEpoch || request !== usersRequest) return;
      $("users-status").textContent = "Could not load users: " + (error.message || String(error));
      $("retry-users").hidden = false;
    } finally {
      if (epoch === browserEpoch && request === usersRequest) usersLoading = false;
    }
  }

  function renderUserContent(kind) {
    const items = newestFirst(content[kind].items, kind === "books" ? "bookVersionId" : "memoryId");
    if (kind === "books") {
      $("books-list").innerHTML = items.map((book) => '<div class="book-row"><div><strong>' + esc(book.printTitle || book.bookDisplayName || book.bookVersionId) + '</strong>' +
        '<p class="meta-line">' + esc(formatDate(book.createdAt)) + '</p><p class="meta-line">' + esc(book.renderStatus || "Unknown status") + (book.hasPaidOrder ? " · paid" : "") + '</p>' +
        '<p class="meta-line">' + esc(book.bookVersionId) + '</p></div><div class="link-row">' + linkIf(book.pdfURL, "PDF") + linkIf(book.coverURL, "Cover") + '</div></div>').join("");
    } else {
      $("memories-list").innerHTML = items.map((memory) => '<details class="memory-row"><summary>' + esc(memory.prompt || "Saved memory") + '<span class="meta-line memory-date">' + esc(formatDate(memory.createdAt)) + (memory.profileName ? ' · ' + esc(memory.profileName) : '') + (memory.chapter ? ' · ' + esc(memory.chapter) : '') + '</span></summary>' +
        '<div class="memory-text">' + esc(memory.text || "No transcript saved.") + '</div>' + (memory.textTruncated ? '<p class="meta-line">This preview is shortened. ' + linkIf('https://console.firebase.google.com/project/memoirai-7db06/firestore/databases/-default-/data/~2Fusers~2F' + encodeURIComponent(selectedUser.userId) + '~2Fmemories~2F' + encodeURIComponent(memory.memoryId), 'View full memory in Firebase') + '</p>' : '') + '</details>').join("");
    }
  }

  async function loadUserContent(kind, append = false) {
    if (!selectedUser || (append && content[kind].loading)) return;
    const page = content[kind];
    const request = ++page.request;
    const selection = contentRequest;
    const epoch = browserEpoch;
    const uid = selectedUser.userId;
    page.loading = true;
    page.retryAppend = append;
    $("more-" + kind).hidden = true;
    $("retry-" + kind).hidden = true;
    $(kind + "-status").textContent = "Loading " + kind + "…";
    if (!append) { page.items = []; page.cursor = null; renderUserContent(kind); }
    try {
      const callable = kind === "books" ? listBooksFn : listMemoriesFn;
      const result = await callable({ userId: uid, limit: 25, ...(append && page.cursor ? { cursor: page.cursor } : {}) });
      if (epoch !== browserEpoch || selection !== contentRequest || request !== page.request) return;
      page.items = mergeItems(append ? page.items : [], result.data?.[kind] || [], kind === "books" ? "bookVersionId" : "memoryId");
      page.cursor = result.data?.nextCursor || null;
      renderUserContent(kind);
      $(kind + "-status").textContent = page.items.length ? "" : "No " + kind + " saved for this account.";
      $("more-" + kind).hidden = !page.cursor;
    } catch (error) {
      if (epoch !== browserEpoch || selection !== contentRequest || request !== page.request) return;
      $(kind + "-status").textContent = "Could not load " + kind + ": " + (error.message || String(error));
      $("retry-" + kind).hidden = false;
    } finally {
      if (epoch === browserEpoch && selection === contentRequest && request === page.request) page.loading = false;
    }
  }

  function openUser(user) {
    if (!user?.userId) return;
    selectedUser = user;
    contentRequest++;
    $("user-id-input").value = user.userId;
    $("selected-user-name").textContent = user.displayName || user.email || (user.isAnonymous ? "Guest account" : "User details");
    $("selected-user-id").textContent = user.userId;
    $("user-detail").hidden = false;
    $("user-selection-hint").hidden = true;
    $("user-detail").scrollIntoView({ behavior: "smooth", block: "start" });
    renderUsers();
    loadUserContent("books");
    loadUserContent("memories");
  }

  function loadUserBooks() {
    const uid = $("user-id-input").value.trim();
    if (!uid) { toast("Enter a user ID", "err"); return; }
    openUser(users.find((user) => user.userId === uid) || { userId: uid });
  }

  function resetUserBrowser() {
    browserEpoch++;
    usersRequest++;
    contentRequest++;
    users = [];
    usersCursor = null;
    usersLoaded = false;
    usersLoading = false;
    selectedUser = null;
    $("user-sort").value = "newest";
    $("user-id-input").value = "";
    $("user-detail").hidden = true;
    $("user-selection-hint").hidden = false;
    $("selected-user-name").textContent = "";
    $("selected-user-id").textContent = "";
    $("users-status").textContent = "";
    $("more-users").hidden = true;
    $("retry-users").hidden = true;
    renderUsers();
    for (const kind of ["books", "memories"]) {
      content[kind] = { items: [], cursor: null, loading: false, retryAppend: false, request: 0 };
      $(kind + "-list").innerHTML = "";
      $(kind + "-status").textContent = "";
      $("more-" + kind).hidden = true;
      $("retry-" + kind).hidden = true;
    }
  }

  function showView(name) {
    if (name === "users" && !usersLoaded && !usersLoading && auth.currentUser) loadUsers();
    document.querySelectorAll(".nav-btn").forEach((b) => {
      b.classList.toggle("active", b.getAttribute("data-view") === name);
    });
    document.querySelectorAll(".view").forEach((v) => {
      v.classList.toggle("active", v.id === "view-" + name);
    });
  }

  function showApp(user) {
    $("login-page").style.display = "none";
    $("app").classList.add("active");
    $("sidebar-email").textContent = user.email || user.uid;
    refreshAll();
  }

  $("google-sign-in").onclick = async () => {
    $("auth-error").textContent = "";
    const btn = $("google-sign-in");
    btn.disabled = true;
    try {
      const provider = new firebase.auth.GoogleAuthProvider();
      provider.setCustomParameters({ prompt: "select_account" });
      await auth.signInWithPopup(provider);
    } catch (err) {
      $("auth-error").textContent = err.message || String(err);
      btn.disabled = false;
    }
  };

  $("login-form").onsubmit = async (e) => {
    e.preventDefault();
    $("auth-error").textContent = "";
    const email = $("email").value.trim();
    const password = $("password").value;
    if (!email || !password) {
      $("auth-error").textContent = "Enter email and password, or use Google sign-in.";
      return;
    }
    try {
      await auth.signInWithEmailAndPassword(email, password);
    } catch (err) {
      $("auth-error").textContent = err.message || String(err);
    }
  };

  $("verify-modal-close").onclick = closeVerifyModal;
  $("verify-cancel-btn").onclick = closeVerifyModal;
  $("verify-confirm-btn").onclick = doFulfill;
  $("verify-modal-backdrop").onclick = (e) => {
    if (e.target === $("verify-modal-backdrop")) closeVerifyModal();
  };

  $("sign-out").onclick = () => auth.signOut();
  $("refresh-all").onclick = refreshAll;
  $("refresh-queue").onclick = refreshAll;
  $("refresh-orders").onclick = refreshAll;
  $("order-search").oninput = renderOrdersTable;
  $("order-filter").onchange = renderOrdersTable;
  $("load-books-btn").onclick = loadUserBooks;
  $("user-id-input").onkeydown = (event) => { if (event.key === "Enter") loadUserBooks(); };
  $("user-sort").onchange = () => loadUsers();
  $("refresh-users").onclick = () => loadUsers();
  $("more-users").onclick = () => loadUsers(true);
  $("retry-users").onclick = () => loadUsers(usersRetryAppend);
  $("refresh-user-content").onclick = () => { if (selectedUser) openUser(selectedUser); };
  for (const kind of ["books", "memories"]) {
    $("more-" + kind).onclick = () => loadUserContent(kind, true);
    $("retry-" + kind).onclick = () => loadUserContent(kind, content[kind].retryAppend);
  }
  $("drawer-close").onclick = closeDrawer;
  $("drawer-backdrop").onclick = (e) => {
    if (e.target === $("drawer-backdrop")) closeDrawer();
  };

  document.querySelectorAll(".nav-btn").forEach((btn) => {
    btn.onclick = () => showView(btn.getAttribute("data-view"));
  });
  document.querySelectorAll("[data-goto]").forEach((el) => {
    el.onclick = () => showView(el.getAttribute("data-goto"));
  });

  auth.onAuthStateChanged((user) => {
    resetUserBrowser();
    if (user) {
      showApp(user);
      if ($("view-users").classList.contains("active")) loadUsers();
    }
    else {
      $("login-page").style.display = "";
      $("app").classList.remove("active");
    }
  });
})();
