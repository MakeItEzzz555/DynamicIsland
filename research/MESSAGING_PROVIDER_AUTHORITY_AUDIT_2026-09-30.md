# Messaging provider authority audit — 2026-09-30

Environment: macOS 15.7.4 (24G517), Xcode SDK 26.2. DynamicIsland is unsandboxed, has the
`com.apple.security.automation.apple-events` entitlement and `NSAppleEventsUsageDescription`.
Read-only investigation: no messages were sent, no AppleScript was run against Messages,
no private databases (`~/Library/Messages/chat.db`) were opened, no permissions were requested.

## Evidence

### Apple Messages
- `sdef /System/Applications/Messages.app` (172 lines): one "Messages Suite" plus CocoaStandard.
  Classes: `participant`, `account`, `chat`, `file transfer`. **No message class, no body,
  timestamp or unread properties, and no "Event Handlers" suite** (no message-received handler).
- `send` command:
  ```xml
  <command name="send" code="ichtsend" description="Sends a message to a participant or to a chat.">
      <direct-parameter><type type="file"/><type type="text"/></direct-parameter>
      <parameter name="to" code="TO  "><type type="participant"/><type type="chat"/></parameter>
  </command>
  ```
  **No `<result>`**: it returns no message id and no delivery/sent status. A normal return only
  means the Apple Event was accepted; only reference/permission errors are observable.
- `chat.id` is documented only as "A guid identifier for this chat" (opaque).
- URL schemes in Messages' Info.plist: `sms`, `sms-private`, `imessage`, `iChat`, `Messages`, `im`,
  `itms-messages(s)`. `sms:<handle>` opens a conversation with a known handle; none of them send.
- Other apps' notifications are not readable: `UNUserNotificationCenter` returns only the calling
  app's own notifications; the Notification Center database is private; `InstantMessage.framework`
  is deprecated (10.5–10.9) and covers presence only; `INSendMessageIntent` on macOS is for apps that
  handle/donate the intent, `INSearchForMessagesIntent` is unavailable on macOS.

### WhatsApp / Telegram
- Not installed on this Mac (`mdfind` for `net.whatsapp.WhatsApp`, `desktop.WhatsApp`,
  `ru.keepcoder.Telegram`, `org.telegram.desktop` returned nothing; nothing in `/Applications` or
  `~/Applications`).
- Documented (not locally verified) deep links open a pre-filled compose or chat
  (`whatsapp://send?phone=&text=`, `tg://resolve?domain=`, `tg://msg?text=`); the user must press
  Send and nothing reports a result. Neither desktop app is known to ship a scripting dictionary.
  Business/Bot server APIs act as a business or bot account, not the user's client.

## Capability matrix

| | Apple Messages | WhatsApp | Telegram |
|---|---|---|---|
| Incoming observation (public) | None | None | None |
| Exact conversation identity from incoming | No | No | No |
| Exact sender / body from incoming | No | No | No |
| Open conversation | Only with a known handle (`sms:`); none is available from incoming | Deep link (documented) | Deep link (documented) |
| Send | AppleScript `send … to chat id` exists | No (pre-fill only) | No (pre-fill only) |
| Send result confirmable | **No** (`send` has no result) | No | No |
| Permission | Automation (Apple Events) prompt for Messages | — | — |
| Fallback | Open Messages | Open app (if installed) | Open app (if installed) |

## Classification (implemented in Phase 14)

- **Apple Messages** — Incoming: **Blocked by macOS/API constraints**. Reply: **not offered**
  (no exact target can be derived from any incoming source and sends cannot be confirmed; an
  AppleScript send would be at best an unconfirmed hand-off to a chat chosen some other way).
  Open: **Open-App fallback** via `MessagesAppAdapter` (activates Messages, no Automation permission).
- **WhatsApp** — **Not installed**; if installed, at most **Open-App fallback**. No adapter shipped.
- **Telegram** — **Not installed**; if installed, at most **Open-App fallback**. No adapter shipped.

Approaches that would change this and therefore **Require Approval** (stop boundaries):
reading the Notification Center UI through Accessibility, reading `chat.db` (Full Disk Access /
private database), or UI-scripting message sends. Even with Accessibility, notification banners
expose only display names, which are not an exact reply target.
