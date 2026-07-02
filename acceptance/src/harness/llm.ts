import { config } from "./env.js";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

/** Minimal OpenAI-compatible chat client. Returns the assistant message content. */
export async function chat(messages: ChatMessage[], opts: { temperature?: number; model?: string } = {}): Promise<string> {
  if (!config.llm.enabled()) throw new Error("LLM not configured (set ACCEPTANCE_LLM_API_KEY)");
  const res = await fetch(`${config.llm.baseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.llm.apiKey}` },
    body: JSON.stringify({
      model: opts.model ?? config.llm.model,
      temperature: opts.temperature ?? 0,
      messages,
    }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`LLM ${res.status}: ${text.slice(0, 300)}`);
  const json = JSON.parse(text) as { choices?: Array<{ message?: { content?: string } }> };
  return json.choices?.[0]?.message?.content ?? "";
}

export interface RubricCriterion {
  id: string;
  description: string;
}

export interface JudgeResult {
  scores: Record<string, number>;
  average: number;
  rationale: string;
  pass: boolean;
}

/**
 * LLM-as-judge: grade `output` against a rubric (each criterion 1-5). Returns per-criterion
 * scores + average + a pass flag (average >= threshold). Deterministic-ish (temperature 0).
 */
export async function judge(input: {
  task: string;
  output: string;
  rubric: RubricCriterion[];
  threshold?: number;
}): Promise<JudgeResult> {
  const threshold = input.threshold ?? 3.5;
  const rubricText = input.rubric.map((c, i) => `${i + 1}. [${c.id}] ${c.description}`).join("\n");
  const system =
    "You are a strict but fair evaluator of an AI assistant's output for a task-management app. " +
    "Score each rubric criterion from 1 (poor) to 5 (excellent). Respond with ONLY compact JSON: " +
    `{"scores":{"<criterion_id>":<1-5>,...},"rationale":"<=60 words"}. Use the exact criterion ids.`;
  const user = `TASK CONTEXT:\n${input.task}\n\nAI OUTPUT TO GRADE:\n${input.output}\n\nRUBRIC (score each 1-5):\n${rubricText}`;
  const raw = await chat([{ role: "system", content: system }, { role: "user", content: user }]);
  const parsed = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1)) as { scores: Record<string, number>; rationale: string };
  const scores = parsed.scores ?? {};
  const values = input.rubric.map((c) => Number(scores[c.id]) || 0);
  const average = values.reduce((a, b) => a + b, 0) / (values.length || 1);
  return { scores, average, rationale: parsed.rationale ?? "", pass: average >= threshold };
}
