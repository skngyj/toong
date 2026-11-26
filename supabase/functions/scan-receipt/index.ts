// 영수증 사진을 Gemini로 읽어 메뉴·수량·금액·할인·총액을 돌려주는 Edge Function.
//
// - 로그인한(익명 포함) 사용자만 호출할 수 있다. 함수 설정의 JWT 검증을 켜 둔다.
// - 사용자당 하루 호출 횟수를 consume_toong_scan()으로 센다.
// - 사진과 인식 결과는 저장하지 않는다.
//
// 비밀 값: GEMINI_API_KEY (필수), GEMINI_MODEL (선택, 기본 gemini-3.5-flash-lite)
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  ALLOWED_MIME_TYPES,
  buildGeminiRequest,
  DEFAULT_MODEL,
  MAX_IMAGE_BASE64,
  parseGeminiResponse,
} from "./receipt.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const FAILED = "영수증을 읽지 못했어요. 잠시 후 다시 시도하거나 직접 입력해주세요.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST로 요청해주세요." }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "로그인이 필요합니다." }, 401);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "영수증 인식이 설정되지 않았어요." }, 503);

  let image: string;
  let mimeType: string;
  try {
    const body = await req.json();
    image = String(body.image ?? "");
    mimeType = String(body.mimeType ?? "image/jpeg");
  } catch {
    return json({ error: "요청 형식이 올바르지 않아요." }, 400);
  }
  if (!image || !ALLOWED_MIME_TYPES.includes(mimeType)) {
    return json({ error: "사진을 다시 선택해주세요." }, 400);
  }
  if (image.length > MAX_IMAGE_BASE64) {
    return json({ error: "사진이 너무 커요. 다시 찍어주세요." }, 413);
  }

  // 호출한 사용자의 권한으로 횟수를 센다. auth.uid()가 이 사용자로 잡힌다.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );
  const { error: quotaError } = await supabase.rpc("consume_toong_scan");
  if (quotaError) {
    if (quotaError.code === "TG429") return json({ error: quotaError.message }, 429);
    // 정리된 익명 사용자. 앱은 이 code를 보고만 새 익명 사용자로 다시 로그인한다.
    if (quotaError.code === "TG401") {
      return json({ error: quotaError.message, code: "session_gone" }, 401);
    }
    console.error("quota", quotaError);
    return json({ error: FAILED }, 500);
  }

  const { url, init } = buildGeminiRequest({
    apiKey,
    model: Deno.env.get("GEMINI_MODEL") || DEFAULT_MODEL,
    imageBase64: image,
    mimeType,
  });
  try {
    // Gemini가 일시적으로 붐비면(500·503) 잠깐 쉬고 한 번 더 시도한다. 횟수는 한 번만 센다.
    const deadline = AbortSignal.timeout(25_000);
    let response = await fetch(url, { ...init, signal: deadline });
    if (response.status === 500 || response.status === 503) {
      console.error("gemini retry", response.status);
      await response.body?.cancel();
      await new Promise((resolve) => setTimeout(resolve, 1500));
      response = await fetch(url, { ...init, signal: deadline });
    }
    if (!response.ok) {
      console.error("gemini", response.status, (await response.text()).slice(0, 500));
      return json({ error: FAILED }, 502);
    }
    const receipt = parseGeminiResponse(await response.json());
    if (receipt.items.length === 0) {
      return json({ error: "영수증에서 메뉴를 찾지 못했어요. 직접 입력해주세요." }, 422);
    }
    return json(receipt);
  } catch (error) {
    console.error("scan", error);
    return json({ error: FAILED }, 502);
  }
});
