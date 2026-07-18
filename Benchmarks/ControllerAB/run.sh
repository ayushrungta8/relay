#!/bin/zsh
set -euo pipefail

root_dir=${0:A:h}
codex_bin=/Applications/ChatGPT.app/Contents/Resources/codex
results_dir=${1:-"$root_dir/results"}
mkdir -p "$results_dir"

base_instruction='You are evaluating Relay task supervision. The authoritative current time is 2026-07-18T12:00:00Z. The default context window is the rolling preceding 24 hours and the age rule applies to every task. Never infer the current state of a task outside that window: return NEEDS_LOOKUP. Never claim a status not present in the newest in-window record. If a request can refer to multiple in-window tasks, return CLARIFY. A pending question always takes precedence over prose in the latest message. Return only the required JSON.'

questions='[
  {"case":"running","question":"Which tasks are running?"},
  {"case":"attention","question":"Does anything need me?"},
  {"case":"atlas","question":"What happened with Atlas? Copy the evidence token from its latest message into evidence."},
  {"case":"beacon","question":"Is Beacon still running?"},
  {"case":"old-task","question":"What is the status of Legacy cleanup from two days ago?"},
  {"case":"ambiguous","question":"What is the status of the migration?"}
]'

recent=$(jq -c '.recentTasks' "$root_dir/fixture.json")
old=$(jq -c '.oldTasks' "$root_dir/fixture.json")
expected=$(jq -c . "$root_dir/expected.json")

make_full_context() {
  jq -cn --argjson recent "$recent" --argjson old "$old" '
    def distractors($snapshot):
      [range(1;17) as $n | {
        id:("T-DISTRACTOR-" + ($n|tostring)),
        title:("Archived maintenance item " + ($n|tostring)),
        project:"/Work/archive",
        status:"idle",
        updatedAt:"2026-07-15T08:00:00Z",
        pendingQuestion:null,
        latestMessage:("Historical maintenance detail that is irrelevant to the current request. " * 9)
      }] + $snapshot;
    [
      {capturedAt:"2026-07-16T09:00:00Z", tasks:distractors($old + $recent)},
      {capturedAt:"2026-07-17T07:00:00Z", tasks:distractors($old + $recent)},
      {capturedAt:"2026-07-17T18:00:00Z", tasks:distractors($old + $recent)},
      {capturedAt:"2026-07-18T12:00:00Z", tasks:distractors($old + $recent)}
    ]'
}

make_lean_context() {
  jq -cn --argjson recent "$recent" '{capturedAt:"2026-07-18T12:00:00Z",tasks:$recent}'
}

make_terse_context() {
  jq -cn --argjson recent "$recent" '$recent | map({id,title,status,updatedAt,pendingQuestion,last:(.latestMessage[0:240])})'
}

run_one() {
  local variant=$1
  local model=$2
  local effort=$3
  local context_kind=$4
  local repetition=$5
  local context
  case "$context_kind" in
    full) context=$(make_full_context) ;;
    lean) context=$(make_lean_context) ;;
    terse) context=$(make_terse_context) ;;
    *) return 2 ;;
  esac

  local prompt
  prompt=$(jq -rn \
    --arg instruction "$base_instruction" \
    --arg context "$context" \
    --arg questions "$questions" \
    '$instruction + "\n\nTASK CONTEXT:\n" + $context + "\n\nQUESTIONS:\n" + $questions')

  local stem="$results_dir/${variant}-r${repetition}"
  local started ended
  print -r -- "running $variant repetition $repetition"
  started=$(python3 -c 'import time; print(time.time())')
  print -r -- "$prompt" | "$codex_bin" exec - \
    --ignore-user-config \
    --ignore-rules \
    --ephemeral \
    --skip-git-repo-check \
    --sandbox read-only \
    -C /tmp \
    -m "$model" \
    -c "model_reasoning_effort=\"$effort\"" \
    --output-schema "$root_dir/response-schema.json" \
    --json \
    > "$stem.events.jsonl" 2> "$stem.stderr"
  ended=$(python3 -c 'import time; print(time.time())')

  jq -r 'select(.type=="item.completed" and .item.type=="agent_message") | .item.text' \
    "$stem.events.jsonl" | tail -1 > "$stem.answer.json"
  jq -n \
    --arg variant "$variant" \
    --arg model "$model" \
    --arg effort "$effort" \
    --arg context "$context_kind" \
    --argjson repetition "$repetition" \
    --argjson duration "$(python3 -c "print($ended - $started)")" \
    --argjson input_chars "${#prompt}" \
    --argjson correct "$(jq -S --argjson expected "$expected" '
      def normalized:
        .results
        | map(
            if .case == "old-task"
            then .taskIds = []
            else .taskIds |= sort
            end
            | del(.evidence)
          );
      (normalized == ($expected | normalized))
      and
      ([.results[] | select(.case == "atlas") | .evidence]
        | any(contains("sigcert-4Q9")))
    ' "$stem.answer.json")" \
    --argjson usage "$(jq -c 'select(.type=="turn.completed") | .usage' "$stem.events.jsonl" | tail -1)" \
    '{variant:$variant,model:$model,effort:$effort,context:$context,repetition:$repetition,durationSeconds:$duration,inputCharacters:$input_chars,correct:$correct,usage:$usage}' \
    > "$stem.result.json"
}

variants=(
  'luna-medium-full|gpt-5.6-luna|medium|full'
  'terra-medium-full|gpt-5.6-terra|medium|full'
  'terra-low-full|gpt-5.6-terra|low|full'
  'terra-medium-lean|gpt-5.6-terra|medium|lean'
  'terra-low-lean|gpt-5.6-terra|low|lean'
  'terra-low-terse|gpt-5.6-terra|low|terse'
)

repetitions=(${=REPETITIONS:-"1 2"})
variant_filter=${VARIANT_FILTER:-}

for repetition in $repetitions; do
  for spec in $variants; do
    parts=(${(s:|:)spec})
    if [[ -n "$variant_filter" && "$parts[1]" != "$variant_filter" ]]; then
      continue
    fi
    run_one "$parts[1]" "$parts[2]" "$parts[3]" "$parts[4]" "$repetition"
  done
done

jq -s '
  group_by(.variant) |
  map({
    variant:.[0].variant,
    model:.[0].model,
    effort:.[0].effort,
    context:.[0].context,
    passed:all(.[]; .correct),
    runs:length,
    avgDurationSeconds:(map(.durationSeconds)|add/length),
    avgInputCharacters:(map(.inputCharacters)|add/length),
    avgInputTokens:(map(.usage.input_tokens)|add/length),
    avgCachedInputTokens:(map(.usage.cached_input_tokens)|add/length),
    avgOutputTokens:(map(.usage.output_tokens)|add/length)
  }) | sort_by(.avgDurationSeconds)
' "$results_dir"/*.result.json > "$results_dir/summary.json"

jq . "$results_dir/summary.json"
