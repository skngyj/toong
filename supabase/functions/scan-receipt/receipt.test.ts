// node --experimental-strip-types --test supabase/functions/scan-receipt/receipt.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildGeminiRequest,
  normalizeMenu,
  normalizeReceipt,
  parseGeminiResponse,
} from "./receipt.ts";

function geminiPayload(result: unknown, thought?: string) {
  const parts = [] as { text: string; thought?: boolean }[];
  if (thought) parts.push({ text: thought, thought: true });
  parts.push({ text: JSON.stringify(result) });
  return { candidates: [{ content: { parts } }] };
}

test("요청에 이미지, 키, JSON 응답 형식을 담는다", () => {
  const { url, init } = buildGeminiRequest({
    apiKey: "key",
    model: "gemini-3.5-flash-lite",
    imageBase64: "AAAA",
    mimeType: "image/jpeg",
  });
  assert.equal(
    url,
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent",
  );
  assert.equal((init.headers as Record<string, string>)["x-goog-api-key"], "key");
  const body = JSON.parse(init.body as string);
  assert.equal(body.contents[0].parts[0].inline_data.data, "AAAA");
  assert.equal(body.generationConfig.responseMimeType, "application/json");
  assert.deepEqual(body.generationConfig.responseSchema.required, ["items", "discounts", "total"]);
});

test("모델 응답에서 메뉴·할인·총액을 꺼낸다", () => {
  const receipt = parseGeminiResponse(geminiPayload({
    storeName: "카페 퉁퉁 신촌점",
    items: [
      { name: "아이스아메리카노", quantity: 3, unitPrice: 4500, amount: 13500 },
      { name: "카페라떼", quantity: 2, unitPrice: 5000, amount: 10000 },
    ],
    discounts: [{ name: "쿠폰할인", amount: -2000 }],
    total: 21500,
  }, "생각 요약"));
  assert.equal(receipt.storeName, "카페 퉁퉁 신촌점");
  assert.equal(receipt.items.length, 2);
  assert.deepEqual(receipt.discounts, [{ name: "쿠폰할인", amount: 2000 }]);
  assert.equal(receipt.total, 21500);
});

test("합계·세금·결제 줄과 잘못된 금액을 거르고 값을 보정한다", () => {
  const receipt = normalizeReceipt({
    storeName: "  퉁   분식  ",
    items: [
      { name: "김치찌개", quantity: 2, unitPrice: 9000, amount: "18,000" },
      { name: "공기밥", quantity: 3, unitPrice: 1000, amount: 0 },
      { name: "합계", quantity: 1, amount: 21000 },
      { name: "부가세", quantity: 1, amount: 1909 },
      { name: "신용카드 결제", quantity: 1, amount: 21000 },
      { name: "", quantity: 1, amount: 500 },
      { name: "서비스", quantity: 1, amount: 0 },
      { name: "아주 긴 이름".repeat(10), quantity: 0, amount: 100 },
    ],
    discounts: [{ name: "", amount: 0 }, { name: "", amount: 500 }],
    total: "21,000원",
  });
  assert.equal(receipt.storeName, "퉁 분식");
  assert.deepEqual(receipt.items.map((i) => [i.name.length <= 40, i.quantity, i.amount]), [
    [true, 2, 18000],
    [true, 3, 3000],
    [true, 1, 100],
  ]);
  assert.deepEqual(receipt.discounts, [{ name: "할인", amount: 500 }]);
  assert.equal(receipt.total, 21000);
});

test("읽지 못한 값은 null, 빈 응답은 예외", () => {
  const receipt = normalizeReceipt({ items: [], discounts: [], total: null, storeName: null });
  assert.deepEqual(receipt, { storeName: null, items: [], discounts: [], total: null });
  assert.throws(() => parseGeminiResponse({ candidates: [] }));
  assert.throws(() => parseGeminiResponse({ candidates: [{ content: { parts: [{ text: "{" }] } }] }));
});

test("메뉴판 모드는 메뉴판 프롬프트와 스키마를 쓴다", () => {
  const { init } = buildGeminiRequest({
    apiKey: "key",
    model: "m",
    imageBase64: "AAAA",
    mimeType: "image/jpeg",
    mode: "menu",
  });
  const body = JSON.parse(init.body as string);
  assert.match(body.contents[0].parts[1].text, /메뉴판/);
  assert.deepEqual(body.generationConfig.responseSchema.required, ["items"]);
});

test("메뉴판 결과를 수량 1, 가격 그대로인 항목으로 정리한다", () => {
  const menu = parseGeminiResponse(geminiPayload({
    storeName: "분식 퉁퉁",
    items: [
      { name: "떡볶이", price: 5000 },
      { name: "떡볶이", price: 5000 },
      { name: "아메리카노(L)", price: "4,500원" },
      { name: "", price: 3000 },
      { name: "김밥", price: 0 },
    ],
  }), "menu");
  assert.equal(menu.storeName, "분식 퉁퉁");
  assert.deepEqual(menu.items, [
    { name: "떡볶이", quantity: 1, unitPrice: 5000, amount: 5000 },
    { name: "아메리카노(L)", quantity: 1, unitPrice: 4500, amount: 4500 },
  ]);
  assert.deepEqual(menu.discounts, []);
  assert.equal(menu.total, null);
  assert.deepEqual(normalizeMenu(null).items, []);
});
