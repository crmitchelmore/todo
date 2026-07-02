import { Report } from "../src/harness/report.js";
import { config } from "../src/harness/env.js";
import { judge, type RubricCriterion } from "../src/harness/llm.js";
import { interviewPromptFor } from "../../worker/src/autoResearch.js";
import { runAgentResearch } from "../../worker/src/handoffResearch.js";
import { enrich } from "../../worker/src/enrich.js";
import type { TaskDiscovery } from "../../worker/src/discovery.js";

/**
 * LLM-as-judge evals for the non-deterministic agentic steps. They drive the WORKER'S REAL prompt
 * code (runAgentResearch, interviewPromptFor, enrich) so the eval measures shipping behaviour, then
 * grade the output against the rubrics in acceptance/features/agentic.md. Generation + judging both
 * need ACCEPTANCE_LLM_*; without it, LLM parts are skipped (structural checks still run).
 */

function discoveryFixture(over: Partial<TaskDiscovery> & { title: string }): TaskDiscovery {
  return {
    taskId: "00000000-0000-4000-8000-000000000001",
    title: over.title,
    query: over.query ?? over.title,
    location: over.location ?? { source: "unavailable", label: null, latitude: null, longitude: null, timeZone: null },
    web: over.web ?? { source: "not_configured", query: over.title, results: [] },
    memories: over.memories ?? [],
    nextActions: over.nextActions ?? ["Clarify the desired outcome", "Identify a first concrete step"],
    confidence: over.confidence ?? 0.4,
  };
}

const RUBRICS: Record<string, RubricCriterion[]> = {
  research: [
    { id: "relevance", description: "Brief is directly relevant to the task title/intent." },
    { id: "grounded", description: "Uses only the provided context; no invented external state/facts." },
    { id: "actionable", description: "Next actions are concrete, safe, and genuinely useful." },
    { id: "concise", description: "Reasoning is concise but useful (not padded)." },
    { id: "calibrated", description: "Stated confidence matches the strength of available evidence." },
  ],
  interview: [
    { id: "options_relevant", description: "Offered options are relevant to resolving the task." },
    { id: "asks_missing", description: "The question targets the actual missing context." },
    { id: "freetext_fit", description: "Free-text fallback is appropriate and not redundant with options." },
    { id: "no_redundant", description: "Options are distinct, not near-duplicates." },
    { id: "concise", description: "Question and options are concise and understandable." },
  ],
  enrichment: [
    { id: "category_fit", description: "Suggested category fits the capture." },
    { id: "due_validity", description: "Suggested due date is valid and sensibly resolved from any relative date." },
    { id: "tags_priority", description: "Tags and priority are reasonable for the item." },
    { id: "recurrence", description: "Recurrence (if any) is sensible; none invented spuriously." },
    { id: "calibrated", description: "Confidence is calibrated to the signal in the text." },
  ],
};

const CASES = {
  research: [
    { title: "Plan a 3-day Lisbon trip in October under £600", instructions: "Focus on flights + neighbourhoods." },
    { title: "Migrate the billing service off the deprecated Stripe API", instructions: null },
    { title: "Buy a birthday present for my sister who likes pottery", instructions: null },
  ],
  interview: [
    { title: "Sort out the thing for Dave", confidence: 0.2 },
    { title: "Research options", confidence: 0.25 },
  ],
  enrichment: [
    "email Kate the Q3 report tomorrow 2pm",
    "dentist appointment next tuesday",
    "water the plants every monday",
    "refactor the auth module",
  ],
};

async function main() {
  const report = new Report("evals");
  const llmOn = config.llm.enabled();
  report.log(`evals · LLM ${llmOn ? `ON (${config.llm.model})` : "OFF — quality judging skipped; structural checks only"}`);

  // Make the worker's enrich() (which reads process.env) use the acceptance model creds.
  if (llmOn) {
    process.env.OPENAI_API_KEY = config.llm.apiKey;
    process.env.OPENAI_BASE_URL = config.llm.baseUrl;
    process.env.ENRICH_LLM_MODEL = config.llm.model;
  }
  const env = { OPENAI_API_KEY: config.llm.apiKey, OPENAI_BASE_URL: config.llm.baseUrl, HANDOFF_LLM_MODEL: config.llm.model };

  // --- L3 interview: deterministic generation -> structural checks (always) + judge (if LLM) ---
  for (const c of CASES.interview) {
    const name = `interview:${c.title.slice(0, 24)}`;
    try {
      const prompt = interviewPromptFor(discoveryFixture({ title: c.title, confidence: c.confidence }), "insufficient context");
      const structural = Boolean(prompt.question) && prompt.options.length >= 2 && prompt.allowFreeText === true;
      if (!structural) {
        report.record({ name: `${name} [structure]`, status: "fail", detail: `q=${!!prompt.question} opts=${prompt.options.length} free=${prompt.allowFreeText}` });
        continue;
      }
      report.record({ name: `${name} [structure]`, status: "pass", detail: `${prompt.options.length} options, free-text on` });
      if (!llmOn) {
        report.record({ name: `${name} [quality]`, status: "skip", detail: "no ACCEPTANCE_LLM_API_KEY" });
        continue;
      }
      const output = `Question: ${prompt.question}\nOptions:\n${prompt.options.map((o) => `- ${o.label}: ${o.value}`).join("\n")}\nFree text allowed: ${prompt.allowFreeText}`;
      const j = await judge({ task: `Interview prompt for capture: "${c.title}"`, output, rubric: RUBRICS.interview });
      report.record({ name: `${name} [quality]`, status: j.pass ? "pass" : "fail", detail: `avg ${j.average.toFixed(2)} — ${j.rationale}` });
    } catch (err) {
      report.record({ name, status: "fail", detail: err instanceof Error ? err.message : String(err) });
    }
  }

  // --- L1 research + L4 enrichment: require the model to GENERATE, then judge ---
  if (!llmOn) {
    report.record({ name: "research [all]", status: "skip", detail: "no ACCEPTANCE_LLM_API_KEY" });
    report.record({ name: "enrichment [all]", status: "skip", detail: "no ACCEPTANCE_LLM_API_KEY" });
    return report.finish();
  }

  for (const c of CASES.research) {
    const name = `research:${c.title.slice(0, 24)}`;
    try {
      const brief = await runAgentResearch(
        c.title,
        { requestId: "00000000-0000-4000-8000-000000000abc", mode: "research", instructions: c.instructions },
        discoveryFixture({ title: c.title }),
        { env }
      );
      const output = `Brief: ${brief.body}\nNext actions:\n${brief.nextActions.map((a) => `- ${a}`).join("\n")}\nConfidence: ${brief.confidence}`;
      const j = await judge({ task: `Auto-research brief for: "${c.title}" (instructions: ${c.instructions ?? "none"})`, output, rubric: RUBRICS.research });
      report.record({ name, status: j.pass ? "pass" : "fail", detail: `avg ${j.average.toFixed(2)} — ${j.rationale}` });
    } catch (err) {
      report.record({ name, status: "fail", detail: err instanceof Error ? err.message : String(err) });
    }
  }

  for (const title of CASES.enrichment) {
    const name = `enrichment:${title.slice(0, 24)}`;
    try {
      const e = await enrich(title, new Date());
      const output = JSON.stringify({ category: e.suggestedCategory, due_at: e.suggestedDueAt, priority: e.suggestedPriority, tags: e.suggestedTags, recurrence: e.recurrence, confidence: e.confidence, source: e.source });
      const j = await judge({ task: `Enrichment suggestion for capture: "${title}"`, output, rubric: RUBRICS.enrichment });
      report.record({ name, status: j.pass ? "pass" : "fail", detail: `${e.source} avg ${j.average.toFixed(2)} — ${j.rationale}` });
    } catch (err) {
      report.record({ name, status: "fail", detail: err instanceof Error ? err.message : String(err) });
    }
  }

  return report.finish();
}

main().then((c) => process.exit(c && c.fail > 0 ? 1 : 0));
