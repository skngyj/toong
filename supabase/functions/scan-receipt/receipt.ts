// 영수증 인식의 순수 로직: Gemini 요청 만들기와 응답 정리.
// Deno(Edge Function)와 Node(테스트) 양쪽에서 쓰므로 런타임 전용 API를 쓰지 않는다.

export const DEFAULT_MODEL = "gemini-3.5-flash-lite";

/** base64 문자열 기준 최대 크기. 약 5MB 사진. 앱은 긴 변 1600px로 줄여 보낸다. */
export const MAX_IMAGE_BASE64 = 7_000_000;

export const ALLOWED_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
];

/** 서버 저장 함수(save_toong_room)의 제한과 맞춘다. */
const MAX_NAME = 40;
const MAX_ITEMS = 100;
const MAX_AMOUNT = 100_000_000;

export interface ReceiptItem {
  name: string;
  quantity: number;
  unitPrice: number | null;
  amount: number;
}

export interface ReceiptDiscount {
  name: string;
  amount: number;
}

export interface ScannedReceipt {
  storeName: string | null;
  items: ReceiptItem[];
  discounts: ReceiptDiscount[];
  total: number | null;
}

const PROMPT = [
  "이 영수증 사진에서 주문한 메뉴를 읽어 주세요. 규칙:",
  "1) items에는 실제 주문한 메뉴만 넣습니다. 합계, 소계, 과세물품가액, 부가세, 봉사료, 카드·현금 결제, 거스름돈 줄은 넣지 않습니다.",
  "2) amount는 그 메뉴 줄의 합계 금액(단가×수량)이고 unitPrice는 단가입니다. 단가가 안 보이면 amount를 quantity로 나눈 값을 넣습니다.",
  "3) 할인·쿠폰·포인트 사용 줄은 discounts에 넣고 amount는 양수로 적습니다.",
  "4) 금액은 쉼표 없는 원 단위 정수입니다. total은 영수증에 적힌 최종 결제 금액입니다.",
  "5) 읽을 수 없는 값은 지어내지 말고 null로 둡니다. 영수증이 아니면 items를 빈 배열로 둡니다.",
].join(" ");

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    storeName: { type: "STRING", nullable: true },
    items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          name: { type: "STRING" },
          quantity: { type: "INTEGER" },
          unitPrice: { type: "INTEGER", nullable: true },
          amount: { type: "INTEGER" },
        },
        required: ["name", "quantity", "amount"],
      },
    },
    discounts: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          name: { type: "STRING" },
          amount: { type: "INTEGER" },
        },
        required: ["name", "amount"],
      },
    },
    total: { type: "INTEGER", nullable: true },
  },
  required: ["items", "discounts", "total"],
};

/** Gemini generateContent 요청을 만든다. */
export function buildGeminiRequest(options: {
  apiKey: string;
  model: string;
  imageBase64: string;
  mimeType: string;
}): { url: string; init: RequestInit } {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${options.model}:generateContent`;
  const body = {
    contents: [{
      parts: [
        { inline_data: { mime_type: options.mimeType, data: options.imageBase64 } },
        { text: PROMPT },
      ],
    }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
      temperature: 0,
    },
  };
  return {
    url,
    init: {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": options.apiKey,
      },
      body: JSON.stringify(body),
    },
  };
}

/** Gemini 응답 본문에서 모델이 만든 JSON을 꺼내 정리한다. 형식이 맞지 않으면 예외를 던진다. */
export function parseGeminiResponse(payload: unknown): ScannedReceipt {
  const parts = (payload as {
    candidates?: { content?: { parts?: { text?: string; thought?: boolean }[] } }[];
  })?.candidates?.[0]?.content?.parts ?? [];
  const text = parts.filter((p) => !p.thought && typeof p.text === "string")
    .map((p) => p.text).join("");
  if (!text) throw new Error("empty model response");
  return normalizeReceipt(JSON.parse(text));
}

/** 기호가 섞이거나 문자열로 온 숫자도 정수로 바꾼다. 바꿀 수 없으면 null. */
function toInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string") {
    const digits = value.replace(/[^0-9-]/g, "");
    if (/^-?\d+$/.test(digits)) return Number(digits);
  }
  return null;
}

function cleanName(value: unknown): string {
  return typeof value === "string"
    ? value.replace(/\s+/g, " ").trim().slice(0, MAX_NAME)
    : "";
}

/** 메뉴로 잘못 들어온 합계·세금·결제 줄을 거른다. */
const NOT_A_MENU =
  /^(합\s*계|소\s*계|총\s*액|총\s*금액|받을\s*금액|결제\s*금액|과세|면세|부가세|봉사료|신용\s*카드|카드|현금|거스름)/;

/** 모델이 돌려준 값을 앱이 쓸 수 있는 범위로 정리한다. */
export function normalizeReceipt(raw: unknown): ScannedReceipt {
  const data = (raw ?? {}) as Record<string, unknown>;
  const items: ReceiptItem[] = [];
  for (const entry of Array.isArray(data.items) ? data.items : []) {
    const row = (entry ?? {}) as Record<string, unknown>;
    const name = cleanName(row.name);
    if (!name || NOT_A_MENU.test(name)) continue;
    const quantity = Math.max(1, toInt(row.quantity) ?? 1);
    const unitPrice = toInt(row.unitPrice);
    let amount = toInt(row.amount);
    if ((amount === null || amount <= 0) && unitPrice !== null && unitPrice > 0) {
      amount = unitPrice * quantity;
    }
    if (amount === null || amount < 1 || amount > MAX_AMOUNT) continue;
    items.push({
      name,
      quantity,
      unitPrice: unitPrice !== null && unitPrice > 0 ? unitPrice : null,
      amount,
    });
    if (items.length === MAX_ITEMS) break;
  }
  const discounts: ReceiptDiscount[] = [];
  for (const entry of Array.isArray(data.discounts) ? data.discounts : []) {
    const row = (entry ?? {}) as Record<string, unknown>;
    const amount = Math.abs(toInt(row.amount) ?? 0);
    if (amount < 1 || amount > MAX_AMOUNT) continue;
    discounts.push({ name: cleanName(row.name) || "할인", amount });
  }
  const total = toInt(data.total);
  const storeName = cleanName(data.storeName);
  return {
    storeName: storeName || null,
    items,
    discounts,
    total: total !== null && total > 0 && total <= MAX_AMOUNT ? total : null,
  };
}
