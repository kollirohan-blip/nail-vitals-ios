// Nail Vitals assistant server (Cloudflare Worker).
//
// The app's "Ask about this result" screen posts here; this Worker adds the
// instructions below and asks Google Gemini. The Gemini API key lives only
// in Cloudflare as the GEMINI_API_KEY secret -- never in the app, never in
// git. APP_TOKEN (another secret) is a shared password so only the app can
// use this server.
//
//   POST /ask     {question, context, history: [{role, text}]} -> {answer}
//   GET  /models  which Gemini models the key can use (for choosing one)
//
// The app sends the question, the result numbers and recent chat. It never
// sends the finger photo.

const SYSTEM_PROMPT = `You are the help assistant inside Nail Vitals, a student-built screening app (a HOSA Medical Innovation project). From a side photo of the index finger, the app measures three signs of finger clubbing:
- Profile (Lovibond) angle, at the cuticle between the nail and the skin fold. Clubbing is considered above 176 degrees.
- Hyponychial angle, at the cuticle between a line to the last knuckle and a line to the nail's free edge. Healthy average about 179 degrees; clubbing is considered above 192 degrees.
- Phalangeal depth ratio, finger thickness at the nail base divided by thickness at the last knuckle. Healthy about 0.9; clubbing is considered above 1.0.
(Cut-offs from Myers and Farquhar, JAMA 2001, and Husarik et al., 2002.) The app says "worth discussing with a doctor" when two or more signs are above their cut-offs, "measure again" when one is above or two are close to their cut-offs, and "typical range" otherwise (one sign just under its cut-off on its own counts as typical). After three readings it uses the middle value of each sign.

Rules:
- Give general, educational information only. Never diagnose. Never say the person has or doesn't have a disease, never estimate their chance of a specific disease, and never advise on medicines or treatment.
- Clubbing is a physical sign, not a disease. It can go along with lung, heart, liver or digestive conditions, and it can also run in families and be harmless. Only a doctor can work out the cause.
- If the result is "worth discussing with a doctor", encourage seeing a doctor, calmly and without alarm. For any result, suggest a doctor if the person has symptoms or worries.
- If the person mentions severe or sudden symptoms (such as trouble breathing, chest pain, coughing up blood, fainting or blue lips), tell them to get urgent medical care or call emergency services now.
- Be honest about the app's limits: photo measurements shift by a few degrees if the finger is turned or bent, and the app has only been tested on a small number of people.
- Politely decline questions that aren't about nails, fingers, clubbing, this app or seeing a doctor about them.
- Write plain sentences for a general audience, under 120 words. No markdown, headings, bullet symbols or tables.`;

const MAX_QUESTION = 600;
const MAX_CONTEXT = 800;
const MAX_TURN = 1500;
const MAX_TURNS = 8;

export default {
  async fetch(request, env) {
    if (!env.APP_TOKEN || request.headers.get("x-app-token") !== env.APP_TOKEN) {
      return json({ error: "unauthorized" }, 401);
    }
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/models") return listModels(env);
    if (request.method === "POST" && url.pathname === "/ask") return ask(request, env);
    return json({ error: "not found" }, 404);
  },
};

async function ask(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const question = String(body?.question ?? "").trim().slice(0, MAX_QUESTION);
  if (!question) return json({ error: "empty question" }, 400);
  const context = String(body?.context ?? "").trim().slice(0, MAX_CONTEXT);
  const history = Array.isArray(body?.history) ? body.history.slice(-MAX_TURNS) : [];

  // Gemini wants user/model turns that alternate and start with the user.
  const contents = [];
  for (const turn of history) {
    if (!turn || typeof turn.text !== "string" || !["user", "assistant"].includes(turn.role)) continue;
    addTurn(contents, turn.role === "user" ? "user" : "model", turn.text.slice(0, MAX_TURN));
  }
  const prompt = (context ? `My result from the app: ${context}\n\n` : "") + `My question: ${question}`;
  addTurn(contents, "user", prompt);
  while (contents.length && contents[0].role !== "user") contents.shift();

  const models = [env.GEMINI_MODEL, env.GEMINI_FALLBACK_MODEL].filter(Boolean);
  let response;
  for (const model of models) {
    response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents,
        generationConfig: { temperature: 0.4, maxOutputTokens: 2048 },
      }),
    });
    // A model name that doesn't exist (any more) gives 404: try the next.
    if (response.status !== 404) break;
  }
  if (!response.ok) {
    console.log("gemini error", response.status, (await response.text()).slice(0, 300));
    return json({ error: "upstream", status: response.status }, 502);
  }
  const data = await response.json();
  const answer = (data.candidates?.[0]?.content?.parts ?? [])
    .filter((part) => !part.thought && typeof part.text === "string")
    .map((part) => part.text)
    .join("")
    .trim();
  if (!answer) {
    console.log("gemini empty", data.candidates?.[0]?.finishReason, data.promptFeedback?.blockReason);
    return json({ error: "no answer" }, 502);
  }
  return json({ answer });
}

async function listModels(env) {
  const response = await fetch("https://generativelanguage.googleapis.com/v1beta/models?pageSize=200", {
    headers: { "x-goog-api-key": env.GEMINI_API_KEY },
  });
  if (!response.ok) return json({ error: "upstream", status: response.status }, 502);
  const data = await response.json();
  const models = (data.models ?? [])
    .filter((m) => (m.supportedGenerationMethods ?? []).includes("generateContent"))
    .map((m) => m.name.replace(/^models\//, ""));
  return json({ configured: env.GEMINI_MODEL, fallback: env.GEMINI_FALLBACK_MODEL, models });
}

function addTurn(contents, role, text) {
  const last = contents[contents.length - 1];
  if (last && last.role === role) last.parts[0].text += `\n\n${text}`;
  else contents.push({ role, parts: [{ text }] });
}

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
