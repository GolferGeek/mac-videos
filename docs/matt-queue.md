# Matt's queue

Everything waiting on Matt in this project, **most important first**. Deadlines come first, then items blocking other work, then the rest.

- **Matt:** say "give me your top issue" (or "the next one") and you get the first item that is not yet Answered. Answer it in a line.
- **Status** (every item has one):
  - **Waiting**: in the queue, not yet asked.
  - **Asked (date)**: put to Matt.
  - **Answered (date)**: Matt replied; his answer is written in the item, word for word.
  - **Processed**: acted on. Move the item to `docs/matt-queue-archive.md` (newest first) and renumber the queue.
- **Agents:** when you need Matt to decide or do something, add it here with **Status: Waiting**, in priority order, in the format below. Never leave an ask only in chat: Matt reads in bursts, runs several agents at once, and doesn't carry context between messages. After his answer:
  1. set Answered with his words;
  2. act on it and record the decision where this project keeps decisions;
  3. set Processed and move the item to the archive.
- **Format** (each item must read cold, with no shorthand from earlier conversations, and no PR numbers or internal names as the explanation):
  - title (with a deadline if any);
  - **Status**;
  - **What** (plain words);
  - **Why it matters**;
  - **Options**, if more than one;
  - **Recommendation**;
  - **Reply** (the exact words to say);
  - **Answer** (added when Answered).
- **grokbot** reads this file (and the same file in Matt's other projects) to answer "what are my top issues?". It lists items that are Waiting or Asked.

## 1. Grant recorder permissions and try a short recording
- **Status:** Waiting
- **What:** mac-videos builds and launches locally. Follow the README to grant Screen Recording, Camera and Microphone access, choose the USB mic and camera, and record a short clip while speaking and dragging the bubble. Stop with Shift–Command–S and play it in QuickTime. Also try the external SSD folder when available.
- **Why it matters:** Build/unit tests and source-picker inspection cannot prove real microphone sound, camera compositing, control-window exclusion, global stopping or SSD writes without interactive consent and connected hardware.
- **Recommendation:** Run the README's manual smoke test before using the app for a real walkthrough. The default folder is ~/Movies/mac-videos; the report gives the already-built app path too.
- **Reply:** "mac-videos recording smoke test passed" (or describe what failed)
