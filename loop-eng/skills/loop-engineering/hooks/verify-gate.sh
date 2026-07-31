#!/usr/bin/env bash
# verify-gate.sh — Claude Code Stop hook
# stdin: JSON from harness (fields: cwd, stop_hook_active, hook_event_name, session_id[任意])
# stdout: nothing (allow) / {"decision":"block","reason":"..."} (block)
#         / {"systemMessage":"..."} (allow だが安全弁作動を画面に警告)
# exit: always 0 (hook protocol requires exit 0)
set -u

input="$(cat)"

# ----------------------------------------------------------------
# stop_hook_active の正確な意味:
# 「Stop hook が1回 block した直後の、次の停止試行」から true になる合図であり、
# 「何度も(8連続)block したら自動 true になる」わけではない
# (公式 docs: "already continuing as a result of a stop hook")。
# そのためこの値だけを見て allow を確定させない。
# ハーネス本体側には8連続 block でターン強制打ち切りになる上限があるため
# (env CLAUDE_CODE_STOP_HOOK_BLOCK_CAP、既定8。二次情報源)、
# 本スクリプトはそれより手前の5回で自前の安全弁を開く(下記カウンタ参照)。
# ----------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // empty')"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
else
  # jq 無し: true/false をシンプルに grep
  active="$(printf '%s' "$input" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*[a-z]*' | grep -o '[a-z]*$')"
  session_id="$(printf '%s' "$input" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')"
fi

# ----------------------------------------------------------------
# cwd を取り出す
# ----------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
else
  # jq 無し: "cwd":"..." を取り出す（値にエスケープが無い通常パス前提）
  cwd="$(printf '%s' "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/')"
fi

if [ -z "$cwd" ]; then
  exit 0
fi

# ----------------------------------------------------------------
# セッションキーを決める（自前のブロック回数記録のキー）。
# Stop hook の入力に session_id が常に含まれるとは限らない(harness/バージョン依存)ため、
# 取れた場合はそれを使い、取れない場合は cwd のハッシュ(cksum)で代替する。
# → session_id がある環境ではセッション単位で正確に分離でき、
#   無い環境でも cwd 単位で回数管理でき、無限ブロックを防げる。
# ----------------------------------------------------------------
if [ -n "$session_id" ]; then
  session_key="$session_id"
else
  session_key="cwd-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
fi
# ファイル名に使えない文字を潰す(念のためのサニタイズ)
session_key="$(printf '%s' "$session_key" | tr -c 'A-Za-z0-9_-' '_')"

state_dir="${TMPDIR:-/tmp}"
count_file="${state_dir%/}/verify-gate-${session_key}.count"
log_file="${state_dir%/}/verify-gate-${session_key}.log"

# ----------------------------------------------------------------
# E1: VISION ファイルの有無を判定
# VISION.md または docs/VISION-*.md または docs/vision/*.md が1つ以上あれば VISION あり
# ----------------------------------------------------------------
vision_found=0
if [ -f "$cwd/VISION.md" ]; then
  vision_found=1
else
  # docs/VISION-*.md をチェック（glob で1件以上ヒットするか）
  for f in "$cwd/docs/VISION-"*.md; do
    if [ -f "$f" ]; then
      vision_found=1
      break
    fi
  done
fi

if [ "$vision_found" -eq 0 ]; then
  # docs/vision/*.md をチェック（glob で1件以上ヒットするか）
  for f in "$cwd/docs/vision/"*.md; do
    if [ -f "$f" ]; then
      vision_found=1
      break
    fi
  done
fi

if [ "$vision_found" -eq 0 ]; then
  # E1: VISION なし → 許可
  exit 0
fi

# ----------------------------------------------------------------
# verify コマンドを解決（3段構え・この順）
# ----------------------------------------------------------------
verify_cmd=""

_has_script() {
  # package.json の scripts に指定キーがあるか
  local pkg="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    local val
    val="$(jq -r ".scripts.${key} // empty" "$pkg" 2>/dev/null)"
    [ -n "$val" ]
  else
    # jq 無し: python3 または node で .scripts.<key> を精密に判定
    # どちらも無ければ grep を最終手段として使う（壊さない）
    if command -v python3 >/dev/null 2>&1; then
      local val
      val="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("yes" if (d.get("scripts") or {}).get(sys.argv[2]) else "no")' "$pkg" "$key" 2>/dev/null)"
      [ "$val" = "yes" ]
    elif command -v node >/dev/null 2>&1; then
      local val
      val="$(node -e 'var d=JSON.parse(require("fs").readFileSync(process.argv[1])); console.log(((d.scripts||{})[process.argv[2]])?"yes":"no")' "$pkg" "$key" 2>/dev/null)"
      [ "$val" = "yes" ]
    else
      # 最終手段: 旧来の grep（誤検出の可能性があるが python3/node が無い環境向け）
      grep -q "\"${key}\"[[:space:]]*:" "$pkg" 2>/dev/null
    fi
  fi
}

if [ -f "$cwd/package.json" ]; then
  if _has_script "$cwd/package.json" "verify"; then
    verify_cmd="npm run verify"
  elif _has_script "$cwd/package.json" "test"; then
    verify_cmd="npm test"
  fi
fi

if [ -z "$verify_cmd" ]; then
  if [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/pytest.ini" ]; then
    verify_cmd="pytest"
  fi
fi

if [ -z "$verify_cmd" ]; then
  if [ -f "$cwd/go.mod" ]; then
    verify_cmd="go test ./..."
  fi
fi

if [ -z "$verify_cmd" ]; then
  if [ -f "$cwd/Cargo.toml" ]; then
    verify_cmd="cargo test"
  fi
fi

if [ -z "$verify_cmd" ] && [ -f "$cwd/Makefile" ]; then
  if grep -q '^verify:' "$cwd/Makefile" 2>/dev/null; then
    verify_cmd="make verify"
  elif grep -q '^test:' "$cwd/Makefile" 2>/dev/null; then
    verify_cmd="make test"
  fi
fi

if [ -z "$verify_cmd" ]; then
  # E2: verify コマンド解決不可 → 許可（推測で block しない）
  exit 0
fi

# ----------------------------------------------------------------
# ファイルの最終更新時刻(epoch秒)を取得する。BSD stat(macOS)とGNU stat(Linux)の
# 両方に対応する(片方が失敗したらもう片方を試す)。
# ----------------------------------------------------------------
_file_mtime_epoch() {
  local f="$1" v
  v="$(stat -f %m "$f" 2>/dev/null)"
  case "$v" in ''|*[!0-9]*) v="" ;; esac
  if [ -z "$v" ]; then
    v="$(stat -c %Y "$f" 2>/dev/null)"
    case "$v" in ''|*[!0-9]*) v="" ;; esac
  fi
  printf '%s' "$v"
}

# ----------------------------------------------------------------
# verify を実行（出力は握り潰さずログに残す）。
# 自前の時間制限(既定540秒、環境変数 VERIFY_GATE_VERIFY_TIMEOUT_SECONDS で上書き可)を設ける。
# macOS 標準には `timeout` コマンドが無いため、バックグラウンド実行+監視(watchdog)で代替する。
# 制限超過時は素通り(無音allow)ではなく、systemMessageで警告しつつ停止を許可する
# (未検証のまま許可したことを画面に残す)。
# ----------------------------------------------------------------
verify_timeout="${VERIFY_GATE_VERIFY_TIMEOUT_SECONDS:-540}"
case "$verify_timeout" in ''|*[!0-9]*) verify_timeout=540 ;; esac

verify_out_file="${state_dir%/}/verify-gate-out-$$-$RANDOM"
timeout_marker="${state_dir%/}/verify-gate-timeout-$$-$RANDOM"
rm -f "$verify_out_file" "$timeout_marker" 2>/dev/null

( cd "$cwd" && eval "$verify_cmd" ) >"$verify_out_file" 2>&1 &
verify_pid=$!

watchdog_start_epoch="$(date +%s 2>/dev/null)"
(
  sleep "$verify_timeout"
  # 本当に制限時間分眠りきったかを実測時間で確認する。
  # (verify が先に終わって後段の pkill で sleep を早期に止められた場合、ここに来ても
  #  経過時間は verify_timeout に届いていないので、誤ってタイムアウト扱いにしない)
  now_epoch_wd="$(date +%s 2>/dev/null)"
  elapsed_wd=0
  if [ -n "$watchdog_start_epoch" ] && [ -n "$now_epoch_wd" ]; then
    elapsed_wd=$((now_epoch_wd - watchdog_start_epoch))
  else
    elapsed_wd="$verify_timeout"
  fi
  if [ "$elapsed_wd" -ge "$verify_timeout" ]; then
    : > "$timeout_marker" 2>/dev/null
    kill -TERM "$verify_pid" 2>/dev/null
    if command -v pkill >/dev/null 2>&1; then
      pkill -TERM -P "$verify_pid" 2>/dev/null
    fi
    sleep 1
    kill -KILL "$verify_pid" 2>/dev/null
    if command -v pkill >/dev/null 2>&1; then
      pkill -KILL -P "$verify_pid" 2>/dev/null
    fi
  fi
) </dev/null >/dev/null 2>&1 &
watchdog_pid=$!
# ↑ watchdog はこのフック自身の標準出力/標準エラーを継承させない。
# 継承させたまま親(このフックスクリプト)が先に終了すると、呼び出し元が
# コマンド置換(`$(...)`)でこのフックの出力を読んでいる場合、
# watchdog(sleepしている間、pipeの書き込み端をまだ握っている)の分だけ
# EOFが来ず、verify_timeout秒経つまで呼び出し元がハングしてしまうため。

wait "$verify_pid" 2>/dev/null
verify_exit=$?

# verify が watchdog より先に終わっていれば、watchdog(と、その子である sleep)を止めて
# 孤立プロセスを残さない。
# 子(sleep)を先に止めても安全: 上の watchdog 本体は実測経過時間を確認してから
# marker作成/killに進むガードを入れてあるので、sleep が早期に止められて
# 「set -eしていないので次の行へ進んでしまう」場合でも、経過時間が足りず誤動作しない。
if command -v pkill >/dev/null 2>&1; then
  pkill -P "$watchdog_pid" 2>/dev/null
fi
kill "$watchdog_pid" 2>/dev/null
wait "$watchdog_pid" 2>/dev/null

verify_output="$(cat "$verify_out_file" 2>/dev/null)"
rm -f "$verify_out_file"

timed_out=0
if [ -f "$timeout_marker" ]; then
  timed_out=1
fi
rm -f "$timeout_marker" 2>/dev/null

if [ "$timed_out" -eq 1 ]; then
  msg="⚠️ 検証が時間内に完了せず未検証のまま停止を許可（${verify_cmd}、制限${verify_timeout}秒）。出力が不完全な可能性があります。"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg m "$msg" '{"systemMessage":$m}'
  else
    safe_msg="$(printf '%s' "$msg" | tr -d '\n\r"')"
    printf '{"systemMessage":"%s"}\n' "$safe_msg"
  fi
  exit 0
fi

if [ "$verify_exit" -eq 0 ]; then
  # N2: 緑 → 状態ファイルを削除して許可（出力なし・従来どおり）
  rm -f "$count_file" "$log_file" 2>/dev/null
  exit 0
fi

# ----------------------------------------------------------------
# 赤: 出力をログに保存し、自前のブロック回数カウンタを進める
# ----------------------------------------------------------------
printf '%s\n' "$verify_output" > "$log_file" 2>/dev/null

# ----------------------------------------------------------------
# 古い状態の持ち越し防止: count ファイルの最終更新が古すぎる場合は無視して
# 1からカウントする(既定6時間=21600秒、環境変数 VERIFY_GATE_STATE_TTL_SECONDS で上書き可)。
# 前のセッション/エピソードの回数を新しい赤エピソードに持ち越さないための対策。
# ----------------------------------------------------------------
state_ttl="${VERIFY_GATE_STATE_TTL_SECONDS:-21600}"
case "$state_ttl" in ''|*[!0-9]*) state_ttl=21600 ;; esac

if [ -f "$count_file" ]; then
  file_mtime="$(_file_mtime_epoch "$count_file")"
  now_epoch="$(date +%s 2>/dev/null)"
  case "$now_epoch" in ''|*[!0-9]*) now_epoch="" ;; esac
  if [ -n "$file_mtime" ] && [ -n "$now_epoch" ]; then
    age=$((now_epoch - file_mtime))
    if [ "$age" -gt "$state_ttl" ]; then
      rm -f "$count_file" 2>/dev/null
    fi
  fi
fi

prev_count=0
if [ -f "$count_file" ]; then
  prev_count="$(cat "$count_file" 2>/dev/null)"
  case "$prev_count" in ''|*[!0-9]*) prev_count=0 ;; esac
fi
new_count=$((prev_count + 1))

state_writable=1
if ! printf '%s' "$new_count" > "$count_file" 2>/dev/null; then
  state_writable=0
fi

if [ "$state_writable" -eq 0 ]; then
  # 状態ファイルが書けない環境向けフォールバック(無限ブロック防止の安全弁):
  # 回数管理ができないので、旧来どおり stop_hook_active=true なら即 allow。
  if [ "$active" = "true" ]; then
    exit 0
  fi
  new_count=1
fi

tail_lines="$(printf '%s\n' "$verify_output" | tail -n 10)"

if [ "$state_writable" -eq 1 ] && [ "$new_count" -ge 6 ]; then
  # 安全弁: 自前カウンタで5回ブロック済み。本体側の8連続上限を待たず、
  # ここで停止を許可しつつ画面に警告を出す。
  # 安全弁の再武装: count ファイルをここでリセット(削除)する(ログは残す)。
  # これにより次の赤エピソードでは回数が引き継がれず、再び1回目から block される
  # (このリセットをしないと、安全弁が一度開いた後は二度と block に戻らない)。
  rm -f "$count_file" 2>/dev/null
  msg="⚠️ 検証(${verify_cmd})が赤のまま安全弁で停止を許可（5回ブロック後）。ログ: ${log_file}"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg m "$msg" '{"systemMessage":$m}'
  else
    safe_msg="$(printf '%s' "$msg" | tr -d '\n\r"')"
    printf '{"systemMessage":"%s"}\n' "$safe_msg"
  fi
  exit 0
fi

# 1〜5回目(または状態ファイル書き込み不可時): block
reason="検証(${verify_cmd})が失敗(exit ${verify_exit})。VISIONの合格条件が未達です。テストを緑にしてから停止してください。loop-engineering稼働中は赤の間、質問のための停止もblockされ進み続けます（止めない思想・意図通り）。失敗ログ(末尾約10行、フルパス:${log_file}):
${tail_lines}"

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg r "$reason" '{"decision":"block","reason":$r}'
else
  # jq 無し: reason に " や改行を含めない単純文字列として手組み（JSON を壊さない）
  safe_reason="$(printf '%s' "$reason" | tr '\n\r' '  ' | tr -d '"')"
  printf '{"decision":"block","reason":"%s"}\n' "$safe_reason"
fi

exit 0
