import type { TaskDiscovery } from './discovery.js';
import type { AgentResearchBrief } from './handoffResearch.js';

export interface InterviewOption {
  id: string;
  label: string;
  value: string;
}

export interface InterviewPrompt {
  question: string;
  options: InterviewOption[];
  allowFreeText: boolean;
  reason: string;
}

export interface InterviewResume {
  selectedOptionId: string | null;
  selectedOptionLabel: string | null;
  answer: string;
  freeText: string | null;
}

export function needsInterview(discovery: TaskDiscovery, brief: AgentResearchBrief | null, error?: unknown): boolean {
  if (error) return true;
  if (!brief) return true;
  if (brief.confidence < 0.62) return true;
  if (discovery.confidence < 0.5 && discovery.memories.length === 0) return true;
  const hasContext = discovery.memories.length > 0
    || discovery.location.source !== 'unavailable'
    || discovery.web.results.length > 0;
  if (!hasContext && discovery.web.source !== 'configured_endpoint') {
    return true;
  }
  return false;
}

export function interviewPromptFor(discovery: TaskDiscovery, reason = 'insufficient context'): InterviewPrompt {
  const options: InterviewOption[] = [
    {
      id: 'use-title-only',
      label: 'Use the task title only',
      value: `Proceed using only: ${discovery.title}`,
    },
    {
      id: 'clarify-outcome',
      label: 'Clarify the desired outcome',
      value: 'Ask what a good completed outcome looks like before researching further.',
    },
    {
      id: 'clarify-deadline',
      label: 'Clarify timing or deadline',
      value: 'Ask when this needs to happen and whether there are urgency constraints.',
    },
  ];

  if (discovery.location.source === 'unavailable' && locationLikelyUseful(discovery.query)) {
    options.splice(1, 0, {
      id: 'add-location',
      label: 'Add location/context',
      value: 'Ask for the relevant location or local context before comparing options.',
    });
  }
  if (discovery.web.source !== 'configured_endpoint') {
    options.push({
      id: 'provide-source',
      label: 'Provide a source/link',
      value: 'Ask for a useful website, document, repo, or source to research from.',
    });
  }
  if (discovery.memories.length > 0) {
    options.push({
      id: 'apply-known-preferences',
      label: 'Apply known preferences',
      value: `Use known context: ${discovery.memories.slice(0, 3).map((memory) => memory.content).join(' | ')}`,
    });
  }

  return {
    question: `I can research "${discovery.title}", but I need one more bit of context first. What should I optimise for?`,
    options: dedupeOptions(options).slice(0, 6),
    allowFreeText: true,
    reason,
  };
}

export function parseInterviewResumePayload(value: unknown): InterviewResume | null {
  if (!isRecord(value)) return null;
  const selected = isRecord(value.selected_option) ? value.selected_option : {};
  const selectedOptionId = stringValue(selected.id);
  const selectedOptionLabel = stringValue(selected.label);
  const selectedValue = stringValue(selected.value);
  const freeText = stringValue(value.free_text);
  const answer = selectedValue ?? freeText;
  if (!answer) return null;
  return {
    selectedOptionId,
    selectedOptionLabel,
    answer,
    freeText,
  };
}

export function instructionsFromInterview(resume: InterviewResume): string {
  const parts = [
    resume.selectedOptionLabel ? `Selected option: ${resume.selectedOptionLabel}` : null,
    `User context: ${resume.answer}`,
    resume.freeText ? `Free text: ${resume.freeText}` : null,
  ].filter(Boolean);
  return parts.join('\n').slice(0, 1000);
}

function dedupeOptions(options: InterviewOption[]): InterviewOption[] {
  const seen = new Set<string>();
  const out: InterviewOption[] = [];
  for (const option of options) {
    if (seen.has(option.id)) continue;
    seen.add(option.id);
    out.push(option);
  }
  return out;
}

function locationLikelyUseful(query: string): boolean {
  return /\b(near|nearby|local|closest|shop|restaurant|cafe|doctor|dentist|gym|pharmacy|school|route|commute)\b/i.test(query);
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim().slice(0, 1000) : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
