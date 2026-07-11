import sys
import os
import json
import hashlib
import subprocess

SESSIONS_FILE = os.path.expanduser("~/.sioyek_claude_sessions.json")

def clean_path(path):
    path = path.strip().strip("'\"")
    if not os.path.exists(path):
        dirname, basename = os.path.split(path)
        if basename.startswith('.') and basename.endswith('-wrapped'):
            unwrapped = os.path.join(dirname, basename[1:].removesuffix('-wrapped'))
            if os.path.exists(unwrapped):
                return unwrapped
    return path

def set_status(sioyek_path, message):
    subprocess.run([sioyek_path, "--execute-command", f"set_status_string {message}"],
                   capture_output=True)

def get_pdf_hash(file_path):
    return hashlib.md5(file_path.encode('utf-8')).hexdigest()

def load_sessions():
    if os.path.exists(SESSIONS_FILE):
        with open(SESSIONS_FILE) as f:
            return json.load(f)
    return {}

def save_sessions(sessions):
    with open(SESSIONS_FILE, 'w') as f:
        json.dump(sessions, f)

def main():
    sioyek_path = clean_path(sys.argv[1])
    selected_text = sys.argv[2]
    document_path = sys.argv[3]

    set_status(sioyek_path, "Contacting Claude...")

    pdf_id = get_pdf_hash(document_path)
    sessions = load_sessions()
    doc_name = os.path.basename(document_path)

    if pdf_id not in sessions:
        system_prompt = (
            f"You are a research assistant helping the user read '{doc_name}'. "
            "The user highlights text segments as they read. Explain each snippet deeply, "
            "building on prior context from this document. Be concise."
        )
        user_msg = f"Please explain my first highlighted snippet:\n\n\"{selected_text}\""
        cmd = [
            "claude", "-p", user_msg,
            "--system-prompt", system_prompt,
            "--output-format", "json",
        ]
    else:
        session_id = sessions[pdf_id]
        user_msg = f"Next highlighted snippet:\n\n\"{selected_text}\""
        cmd = [
            "claude", "-p", user_msg,
            "--resume", session_id,
            "--output-format", "json",
        ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            set_status(sioyek_path, f"Error: {result.stderr.strip()[:120]}")
            return

        data = json.loads(result.stdout)
        session_id = data.get("session_id", "")
        response_text = data.get("result", "No response text")

        if session_id:
            sessions[pdf_id] = session_id
            save_sessions(sessions)

        set_status(sioyek_path, f"Claude: {response_text}")

    except subprocess.TimeoutExpired:
        set_status(sioyek_path, "Timed out after 120s")
    except json.JSONDecodeError:
        set_status(sioyek_path, "Error: could not parse Claude output")
    except FileNotFoundError:
        set_status(sioyek_path, "Error: 'claude' not found in PATH")
    except Exception as e:
        set_status(sioyek_path, f"Error: {str(e)[:100]}")

if __name__ == '__main__':
    main()
