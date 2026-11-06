const OWNER = "Aboumansour111";
const REPO = "VPN13";
const FILE_PATH = "config/servers.json";
const BRANCH = "main";
const ALLOWED_ORIGIN = "https://aboumansour111.github.io";

function reply(data, status, origin) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": origin || ALLOWED_ORIGIN,
      "access-control-allow-methods": "POST, OPTIONS",
      "access-control-allow-headers": "content-type, x-vpn13-key",
      "vary": "Origin"
    }
  });
}

function decodeBase64Utf8(value) {
  const binary = atob(value.replace(/\n/g, ""));
  const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function encodeBase64Utf8(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

async function githubRequest(url, token, options = {}) {
  return fetch(url, {
    ...options,
    headers: {
      "accept": "application/vnd.github+json",
      "authorization": `Bearer ${token}`,
      "x-github-api-version": "2022-11-28",
      "user-agent": "VPN13-Config-Publisher",
      ...(options.headers || {})
    }
  });
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin") || "";
    if (origin !== ALLOWED_ORIGIN) return reply({ error: "Origin not allowed" }, 403, ALLOWED_ORIGIN);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": ALLOWED_ORIGIN,
          "access-control-allow-methods": "POST, OPTIONS",
          "access-control-allow-headers": "content-type, x-vpn13-key",
          "access-control-max-age": "86400",
          "vary": "Origin"
        }
      });
    }

    if (request.method !== "POST" || new URL(request.url).pathname !== "/push") {
      return reply({ error: "Not found" }, 404, ALLOWED_ORIGIN);
    }
    if (!env.GITHUB_TOKEN || !env.ADMIN_KEY) {
      return reply({ error: "Worker secrets are not configured" }, 500, ALLOWED_ORIGIN);
    }
    if (request.headers.get("x-vpn13-key") !== env.ADMIN_KEY) {
      return reply({ error: "کد مدیریت اشتباه است." }, 401, ALLOWED_ORIGIN);
    }

    try {
      const raw = await request.text();
      if (raw.length > 1500000) return reply({ error: "حجم اطلاعات بیش از حد مجاز است." }, 413, ALLOWED_ORIGIN);
      const body = JSON.parse(raw);
      if (!Array.isArray(body.servers) || body.servers.length < 1 || body.servers.length > 100) {
        return reply({ error: "لیست کانفیگ‌ها نامعتبر است یا تعداد آن‌ها خارج از محدوده است." }, 400, ALLOWED_ORIGIN);
      }

      const incoming = body.servers.map((item, index) => {
        if (!item || typeof item !== "object" || typeof item.config !== "string") {
          throw new Error("ساختار کانفیگ شماره " + (index + 1) + " نامعتبر است.");
        }
        const config = JSON.parse(item.config);
        const allowed = ["shadowsocks", "vless", "vmess", "trojan", "socks", "http"];
        if (!allowed.includes(config.type) || !config.server || !Number.isInteger(Number(config.server_port))) {
          throw new Error("اطلاعات سرور شماره " + (index + 1) + " کامل یا معتبر نیست.");
        }
        return {
          name: String(item.name || ("Server " + (index + 1))).slice(0, 80),
          description: String(item.description || "Added via VPN13").slice(0, 160),
          config: JSON.stringify(config)
        };
      });

      const apiBase = `https://api.github.com/repos/${OWNER}/${REPO}/contents/${FILE_PATH}`;
      const getResponse = await githubRequest(apiBase + "?ref=" + BRANCH, env.GITHUB_TOKEN);
      let current = { version: 1, servers: [] };
      let sha;
      if (getResponse.ok) {
        const file = await getResponse.json();
        sha = file.sha;
        current = JSON.parse(decodeBase64Utf8(file.content));
        if (!Array.isArray(current.servers)) current.servers = [];
      } else if (getResponse.status !== 404) {
        const detail = await getResponse.text();
        return reply({ error: "خواندن فایل GitHub ناموفق بود: " + detail.slice(0, 400) }, 502, ALLOWED_ORIGIN);
      }

      const seen = new Set(current.servers.map(s => s && s.config).filter(Boolean));
      const maxId = current.servers.reduce((max, s) => Math.max(max, Number(s && s.id) || 0), 0);
      const additions = [];
      for (const item of incoming) {
        if (seen.has(item.config)) continue;
        seen.add(item.config);
        additions.push({ id: maxId + additions.length + 1, ...item });
      }

      if (additions.length === 0) {
        return reply({ added: 0, duplicates: incoming.length, total: current.servers.length, message: "همه کانفیگ‌ها از قبل وجود داشتند." }, 200, ALLOWED_ORIGIN);
      }

      const updated = { version: 1, servers: [...current.servers, ...additions] };
      const putBody = {
        message: "Add " + additions.length + " VPN13 server config(s)",
        content: encodeBase64Utf8(JSON.stringify(updated, null, 2)),
        branch: BRANCH,
        ...(sha ? { sha } : {})
      };
      const putResponse = await githubRequest(apiBase, env.GITHUB_TOKEN, {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(putBody)
      });
      if (!putResponse.ok) {
        const detail = await putResponse.text();
        return reply({ error: "ثبت در GitHub ناموفق بود: " + detail.slice(0, 500) }, 502, ALLOWED_ORIGIN);
      }

      return reply({
        added: additions.length,
        duplicates: incoming.length - additions.length,
        total: updated.servers.length,
        message: additions.length + " کانفیگ با موفقیت به GitHub اضافه شد."
      }, 200, ALLOWED_ORIGIN);
    } catch (error) {
      return reply({ error: error.message || "خطای ناشناخته" }, 400, ALLOWED_ORIGIN);
    }
  }
};
