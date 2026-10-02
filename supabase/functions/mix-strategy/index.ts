// Supabase Edge Function — 미디어 믹스 전략 어시스턴트
// 브라우저가 Claude 키를 보지 못하도록 이 함수가 프록시 역할을 한다.
// 모델·시스템프롬프트·max_tokens 를 고정해 일반 챗봇 악용을 막는다.
//
// 배포 전 Supabase 비밀값 설정:  ANTHROPIC_API_KEY
// JWT 검증은 켜 둔다(로그인 사용자만 호출).

const MODEL = "claude-sonnet-5";
const MAX_TOKENS = 1500;

const SYSTEM = `당신은 한국 디지털 광고 미디어 플래너다.
주어진 [데이터](전월·전년 동월 매체별 성과, 현재 믹스안)를 근거로 다음 달 미디어 믹스 전략을 제안한다.

규칙:
- 한국어, 20줄 내외로 간결하게. 불릿 위주.
- 데이터에 없는 수치를 지어내지 말 것. 근거는 제공된 값만 사용.
- 매체별로 늘릴지/줄일지와 그 이유(ROAS·전환·추세)를 분명히.
- 마지막에 '제안 배분' 한 줄로 매체별 비중(%)을 요약.
- 그 다음 줄에 기계용 한 줄을 반드시 추가: [MIX] 매체코드=비중, ... (예: [MIX] Meta_sponsored=40, Naver_brand=40, Google_SA=20). 코드는 [데이터]의 '사용 가능한 매체 코드' 목록 값만 쓰고, 합은 100이 되게.
- 총예산이 '미입력'이면 전월 집행액을 참고해 합리적 총예산을 제안하고, 기계용 줄 [TOTAL] 숫자(원) 를 한 줄 더 추가. (예: [TOTAL] 30000000)
- 사용자가 수정 요청을 하면 반영해 다시 제시.`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST")
    return new Response("Method not allowed", { status: 405, headers: cors });

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key)
    return json({ error: "ANTHROPIC_API_KEY 비밀값이 설정되지 않았습니다." }, 500);

  let body: { context?: string; messages?: { role: string; content: string }[] };
  try { body = await req.json(); } catch { return json({ error: "잘못된 요청" }, 400); }

  const messages = (body.messages || [])
    .filter((m) => (m.role === "user" || m.role === "assistant") && m.content)
    .slice(-12);                                   // 최근 12턴만 (토큰 절약)
  if (!messages.length) return json({ error: "메시지가 없습니다." }, 400);

  const system = SYSTEM + "\n\n[데이터]\n" + (body.context || "(없음)");

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      thinking: { type: "disabled" },              // 짧은 전략 요약 — 속도·비용 우선
      output_config: { effort: "low" },
      system,
      messages,
    }),
  });

  const data = await r.json();
  if (!r.ok) return json({ error: data?.error?.message || "Claude 호출 실패" }, r.status);

  const text = (data.content || [])
    .filter((b: { type: string }) => b.type === "text")
    .map((b: { text: string }) => b.text).join("\n").trim();
  return json({ text });
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...cors, "content-type": "application/json" },
  });
}
