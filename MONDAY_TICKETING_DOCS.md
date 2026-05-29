# BMG Monday.com Ticketing System — Technical Documentation

**Extension:** BMG Sales Automation  
**Module:** Monday.com IT Ticketing Integration  
**Platform:** Microsoft Dynamics 365 Business Central (AL)  
**Last Updated:** 2026-05-22

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Module Map](#2-module-map)
3. [Ticket Data Model — Table 68802](#3-ticket-data-model--table-68802)
4. [User Interface](#4-user-interface)
   - 4.1 [Card Page 68807 — Monday Ticket](#41-card-page-68807--monday-ticket)
   - 4.2 [List Page 68808 — Monday Ticket List](#42-list-page-68808--monday-ticket-list)
5. [Location Enum 68800](#5-location-enum-68800)
6. [API Integration Layer — Codeunit 68807](#6-api-integration-layer--codeunit-68807)
   - 6.1 [Authentication](#61-authentication)
   - 6.2 [ComposeTicket](#62-composeticket)
   - 6.3 [CreateTicket](#63-createticket)
   - 6.4 [CreateTicketSimple](#64-createticketsimple)
   - 6.5 [GetTicketStatus](#65-getticketstatus)
   - 6.6 [AddFileToTicket](#66-addfiletoticket)
   - 6.7 [ShowBoardColumns](#67-showboardcolumns)
   - 6.8 [SetApiToken / GetApiToken](#68-setapitoken--getapitoken)
   - 6.9 [FetchColumnText (local)](#69-fetchcolumntext-local)
   - 6.10 [BuildMutationQuery (local)](#610-buildmutationquery-local)
   - 6.11 [ParseItemId (local)](#611-parseitemid-local)
   - 6.12 [EscapeJson (local)](#612-escapejson-local)
7. [Monday.com Board Configuration](#7-mondaycom-board-configuration)
8. [End-to-End Flow](#8-end-to-end-flow)
9. [Status Color Coding](#9-status-color-coding)
10. [Known Technical Notes](#10-known-technical-notes)

---

## 1. System Overview

The BMG Monday.com Ticketing module allows Business Central users to submit IT support tickets directly to a Monday.com board without leaving BC. It handles:

- **Ticket creation** — user fills in a BC form, clicks *Submit to Monday.com*, and the ticket is created on the Monday.com board with all relevant columns populated.
- **Status monitoring** — users can refresh the current ticket status from Monday.com at any time.
- **File attachments** — files can be attached to an already-submitted ticket using the *Attach File* action.
- **Scoped visibility** — the ticket list only shows tickets created by the currently logged-in user.

---

## 2. Module Map

```
BMG Sales Automation Extension
│
├── Table 68802          BMGMondayTickets          Ticket data storage
├── Page 68807           BMGMondayTickets           Ticket card (create/view)
├── Page 68808           BMGMondayTicketList        Ticket list (user-scoped)
├── Enum 68800           BMGMondayLocations         Location dropdown values
└── Codeunit 68807       BMGMondayDotComMgt         Monday.com API integration
```

---

## 3. Ticket Data Model — Table 68802

**Object:** `table 68802 BMGMondayTickets`  
**Lookup Page:** `BMGMondayTicketList`  
**Permissions:** `tabledata 68802 = RIMD`

| Field No. | Field Name | Type | Notes |
|---|---|---|---|
| 1 | Entry No. | Integer | Primary Key, AutoIncrement |
| 2 | BMG Subject | Text[100] | Ticket title / item name in Monday.com |
| 3 | BMG Comment | Text[2048] | Free-text comment mapped to Comment column |
| 4 | BMG Name | Text[80] | Auto-filled from logged-in user's Full Name on insert |
| 5 | Type of Request | Option | ` ,Request,Incident` |
| 6 | BMG Assignee | Text[100] | Hidden in UI; reserved for future use |
| 7 | BMG Category | Text[100] | Hidden in UI; hardcoded to "Application - Business Central" |
| 8 | BMG Priority | Option | ` ,High,Medium,Low,Critical` |
| 9 | BMG Location | Enum BMGMondayLocations | 34-value location enum |
| 10 | BMG Description | Text[2048] | Detailed description |
| 11 | Files | Blob | Reserved for file attachment data |
| 12 | BMG Requestor Email | Text[80] | Auto-filled from user's Contact Email on insert |
| 13 | BMG Ticket ID | Text[50] | Display value e.g. `TICKET-2184`; populated after submit |
| 14 | BMG Status | Text[100] | Current Monday.com status; Editable = false |
| 15 | BMG Monday Item ID | Text[50] | Numeric Monday.com item ID used for all API calls |

### OnInsert Trigger

When a new record is created, the table automatically populates the requester fields from the current BC user:

```al
trigger OnInsert()
var
    recUser: Record User;
begin
    recUser.Reset();
    recUser.SetRange("User Name", UserId);
    if recUser.FindFirst() then begin
        Rec."BMG Name" := recUser."Full Name";
        Rec."BMG Requestor Email" := recUser."Contact Email";
    end;
end;
```

> **Note:** `BMG Monday Item ID` stores the raw numeric Monday.com item ID (e.g., `8214792031`).  
> `BMG Ticket ID` stores the human-readable ICT ticket number (e.g., `TICKET-2184`).  
> Both are populated by `ComposeTicket` after the ticket is created.

---

## 4. User Interface

### 4.1 Card Page 68807 — Monday Ticket

**Object:** `page 68807 BMGMondayTickets`  
**Type:** Card | **Source Table:** BMGMondayTickets

#### Layout Groups

| Group | Fields |
|---|---|
| **General** | Subject, Type of Request, Priority, Location, *(Category — hidden)*, ICT Ticket Number *(read-only)*, Status *(color-coded, read-only)* |
| **Requester** | Requestor Name *(read-only)*, *(Assignee — hidden)*, Requestor Email |
| **Details** | Comment, Description |

> All editable fields are **locked** (`Enabled = false`) once the ticket has been submitted to Monday.com (`BMG Monday Item ID <> ''`).

#### Actions

| Action | Enabled Condition | Description |
|---|---|---|
| **Submit to Monday.com** | Always | Calls `ComposeTicket`, creates ticket, locks fields |
| **Refresh Status** | After submission | Calls `GetTicketStatus`, updates `BMG Status` |
| **Attach File** | After submission | Opens file picker, uploads file via `AddFileToTicket` |

#### Status Color Coding (Card Page)

| Status Value | StyleExpr | Color |
|---|---|---|
| Done | `Favorable` | Green |
| Stuck | `Unfavorable` | Red |
| Working on it | `Ambiguous` | Orange |
| *(anything else)* | `None` | Default |

---

### 4.2 List Page 68808 — Monday Ticket List

**Object:** `page 68808 BMGMondayTicketList`  
**Type:** List | **Source Table:** BMGMondayTickets | **Card Page:** BMGMondayTickets  
**Editable:** false

#### Columns

Entry No. · Subject · ICT Ticket Number · Comment · Requestor Name · Status *(color-coded)* · Type of Request · Priority · Location · Requestor Email · Description

#### Actions

| Action | Description |
|---|---|
| **New Ticket** | Opens card page in Create mode |
| **Refresh Status** | Updates status for selected ticket |
| **Attach File** | Attaches a file to selected ticket |

#### OnOpenPage — User Filtering

The list is automatically filtered to show only the current user's tickets:

```al
trigger OnOpenPage()
var
    recMondayTicket: Record BMGMondayTickets;
begin
    recMondayTicket.Reset();
    recMondayTicket.SetRange(SystemCreatedBy, UserSecurityId());
    CurrPage.SetTableView(recMondayTicket);
end;
```

#### Status Color Coding (List Page)

| Status Value | StyleExpr | Appearance |
|---|---|---|
| New | `Subordinate` | Gray |
| Working on it | `Ambiguous` | Orange |
| Waiting for Approval | `Attention` | Light Blue |
| Done | `Favorable` | Green |
| Pending | `Strong` | Dark Bold |
| *(anything else)* | `Standard` | Default |

---

## 5. Location Enum 68800

**Object:** `enum 68800 BMGMondayLocations`  
**Extensible:** true

| Value | Identifier | Caption |
|---|---|---|
| 0 | ` ` | *(blank)* |
| 1 | Cebu | Cebu |
| 2 | Alabang | Alabang |
| 3 | Clark | Clark |
| 4 | Conrad | Conrad |
| 5 | Greenbelt | Greenbelt |
| 6 | Davao | Davao |
| 7 | Fort | Fort |
| 8 | Greenhills | Greenhills |
| 9 | Head Office - CMD | Head Office - CMD |
| 10 | Head Office - Executive | Head Office - Executive |
| 11 | Head Office - Finance | Head Office - Finance |
| 12 | Head Office - GSD | Head Office - GSD |
| 13 | Head Office - HCM | Head Office - HCM |
| 14 | Head Office - ICT | Head Office - ICT |
| 15 | Head Office - Brand and Revenue | Head Office - Brand & Revenue |
| 16 | Head Office - Med Ops | Head Office - Med Ops |
| 17 | Head Office - Operations | Head Office - Operations |
| 18 | Head Office - SCM | Head Office - SCM |
| 19 | Head Office - Venn | Head Office - Venn |
| 20 | Megamall | Megamall |
| 21 | Morato | Morato |
| 22 | Nexa | Nexa |
| 23 | Rockwell | Rockwell |
| 24 | Shangrila | Shangrila |
| 25 | Trinoma | Trinoma |
| 26 | Medical Plaza - GSD | Medical Plaza - GSD |
| 27 | Medical Plaza - Venn | Medical Plaza - Venn |
| 28 | Medical Plaza - Medops | Medical Plaza - Medops |
| 29 | Warehouse - SCM | Warehouse - SCM |
| 30 | Head Office - Office of the CEO | Head Office - Office of the CEO |
| 31 | Head Office - None Med Ops | Head Office - None Med Ops |
| 32 | Proscenium - Xeva | Proscenium - Xeva |
| 33 | Tomas Morato | Tomas Morato |

> **Note:** Value 15 uses identifier `"Head Office - Brand and Revenue"` because `&` is not a valid character in AL identifiers, but the Caption displays the `&` correctly.

---

## 6. API Integration Layer — Codeunit 68807

**Object:** `codeunit 68807 BMGMondayDotComMgt`  
**API Endpoint:** `https://api.monday.com/v2`  
**API Version Header:** `2023-10`  
**Protocol:** GraphQL over HTTPS (POST)

---

### 6.1 Authentication

The API token is stored in **IsolatedStorage** with `DataScope::Module` — scoped to the extension, not per-user. It persists across sessions.

| Label | Value |
|---|---|
| Storage Key | `BMGMondayApiToken` |
| API URL | `https://api.monday.com/v2` |
| Auth Header | `Authorization: Bearer <token>` |

To set the token (run once during setup):
```al
MondayMgt.SetApiToken('your-monday-api-token-here');
```

---

### 6.2 ComposeTicket

```al
procedure ComposeTicket(
    pSubject: Text;
    pComment: Text;
    pTypeOfRequest: Text;
    pPriority: Text;
    pLocation: Text;
    pDescription: Text;
    var pRecMondayTicket: Record BMGMondayTickets
): Text
```

**Purpose:** Main entry point called by the *Submit to Monday.com* action. Builds the full `column_values` JSON, submits the ticket, then fetches the ICT ticket number.

**Steps:**
1. Looks up the current BC user to get `Full Name` and `Authentication Email`.
2. Builds `column_values` JSON mapping all columns.
3. Calls `CreateTicket` → returns numeric `NewItemId`.
4. Calls `FetchColumnText(NewItemId, 'pulse_id_mm02vm99')` to get the ICT Ticket Number.
5. Writes `BMG Monday Item ID` and `BMG Ticket ID` to the passed record and calls `Modify()`.
6. Shows confirmation message with the ICT Ticket Number.
7. Returns the numeric `NewItemId`.

**Column Values JSON Structure:**

```json
{
  "person": { "personsAndTeams": [{ "id": 98458747, "kind": "person" }] },
  "short_textk4s2qy1k": "Requestor Full Name",
  "long_text_mm1z55c4": { "text": "Comment text" },
  "long_text": { "text": "Description text" },
  "single_selectd87kj7c": { "label": "Request" },
  "status_1": { "label": "Medium" },
  "single_selectyi1k98z": { "label": "Head Office - ICT" },
  "dropdown_mm1d8yh0": { "labels": ["Application - Business Central"] },
  "email_mm02gjqa": { "email": "user@example.com", "text": "user@example.com" }
}
```

> **Hardcoded values:**
> - Assignee person ID: `98458747` (Rommel Marquez)
> - Category: `Application - Business Central`
> - Board ID: `5026308475`
> - Group ID: `topics`

---

### 6.3 CreateTicket

```al
procedure CreateTicket(
    pBoardId: Text;
    pGroupId: Text;
    pItemName: Text;
    pColumnValues: Text;
    var pIctTicketNo: Text
): Text
```

**Purpose:** Low-level procedure that sends the `create_item` GraphQL mutation.

**GraphQL Mutation (with column values):**
```graphql
mutation ($boardId: ID!, $groupId: String!, $itemName: String!, $columnValues: JSON) {
  create_item(board_id: $boardId, group_id: $groupId, item_name: $itemName, column_values: $columnValues) {
    id
    column_values(ids: ["pulse_id_mm02vm99"]) {
      text
    }
  }
}
```

**Returns:** Numeric Monday.com item ID (e.g., `"8214792031"`).

---

### 6.4 CreateTicketSimple

```al
procedure CreateTicketSimple(
    pBoardId: Text;
    pGroupId: Text;
    pItemName: Text;
    pStatus: Text;
    pDescription: Text;
    pDueDate: Date
): Text
```

**Purpose:** Convenience wrapper that builds a minimal `column_values` JSON (status, description text, due date) and calls `CreateTicket`. Useful for quick/simple ticket creation without the full form.

---

### 6.5 GetTicketStatus

```al
procedure GetTicketStatus(pItemId: Text): Text
```

**Purpose:** Queries Monday.com for the current status of a ticket by its numeric item ID.

**GraphQL Query:**
```graphql
{
  items(ids: [<pItemId>]) {
    column_values(ids: ["status"]) {
      text
    }
  }
}
```

**Returns:** Status text (e.g., `"Working on it"`, `"Done"`, `"Pending"`) or empty text if not found.

**JSON Parse Path:** `data → items[0] → column_values[0] → text`

---

### 6.6 AddFileToTicket

```al
procedure AddFileToTicket(
    pItemId: Text;
    pFileColumnId: Text;
    pFileName: Text;
    var pFileStream: InStream
)
```

**Purpose:** Attaches a file to an existing Monday.com ticket using the GraphQL multipart upload specification.

**GraphQL Mutation:**
```graphql
mutation ($file: File!) {
  add_file_to_column(item_id: <pItemId>, column_id: "<pFileColumnId>", file: $file) {
    id
  }
}
```

**Multipart Body Structure (4 parts):**

| Part | `name=` | Content |
|---|---|---|
| 1 | `query` | The GraphQL mutation string |
| 2 | `variables` | `{"file": null}` |
| 3 | `map` | `{"file": ["variables.file"]}` |
| 4 | `file` | Binary file content with `filename=` in Content-Disposition |

> **Implementation note:** Uses `TempBlob` + `OutStream`/`InStream` + `CopyStream` to combine text headers and binary file content into a single request body. The `CRLF` sequence is constructed using `CRLF[1] := 13; CRLF[2] := 10;` (AL has no `Chr()` function).

**Usage from action:**
```al
trigger OnAction()
var
    MondayMgt: Codeunit BMGMondayDotComMgt;
    FileStream: InStream;
    FileName: Text;
begin
    if not UploadIntoStream('Select file to attach', '', 'All Files (*.*)|*.*', FileName, FileStream) then
        exit;
    MondayMgt.AddFileToTicket(Rec."BMG Monday Item ID", 'files', FileName, FileStream);
    Message('File "%1" attached successfully.', FileName);
end;
```

---

### 6.7 ShowBoardColumns

```al
procedure ShowBoardColumns(pBoardId: Text)
```

**Purpose:** Development/diagnostic helper. Queries the Monday.com board and displays all column IDs, titles, and types in a BC Message dialog.

**GraphQL Query:**
```graphql
{ boards(ids: <pBoardId>) { columns { id title type } } }
```

**Output:** Message dialog showing `ID | Title | Type` for every column.

> **Note:** In the Message dialog output, each line starts with a `\n` escape that renders as `n` visually. The actual column IDs do **not** have a leading `n`. Used during development to discover column IDs.

---

### 6.8 SetApiToken / GetApiToken

```al
procedure SetApiToken(pToken: Text)
local procedure GetApiToken(): Text
```

**SetApiToken:** Stores the Monday.com API token in `IsolatedStorage` with `DataScope::Module`. Call this once during initial setup.

**GetApiToken:** Retrieves the token. Raises an error if no token has been stored:
> *"Monday.com API token is not set. Run SetApiToken() once to store it."*

---

### 6.9 FetchColumnText (local)

```al
local procedure FetchColumnText(pItemId: Text; pColumnId: Text): Text
```

**Purpose:** Generic follow-up query to read any column's text value from an existing item. Used after `CreateTicket` to fetch the ICT Ticket Number from the `pulse_id_mm02vm99` column (which is a read-only `item_id` type column not reliably included in the `create_item` mutation response).

**Called as:**
```al
pRecMondayTicket."BMG Ticket ID" := FetchColumnText(NewItemId, 'pulse_id_mm02vm99');
```

---

### 6.10 BuildMutationQuery (local)

```al
local procedure BuildMutationQuery(pIncludeColumnValues: Boolean): Text
```

**Purpose:** Builds the GraphQL mutation string for `create_item`. If `pIncludeColumnValues = true`, includes the `$columnValues: JSON` parameter and includes `column_values(ids: ["pulse_id_mm02vm99"]) { text }` in the response shape.

---

### 6.11 ParseItemId (local)

```al
local procedure ParseItemId(pResponseBody: Text; var pIctTicketNo: Text): Text
```

**Purpose:** Parses the JSON response from `create_item`. Extracts:
- `data.create_item.id` → returned as the numeric item ID
- `data.create_item.column_values[0].text` → written to `pIctTicketNo` (out parameter)

Uses `JToken.IsObject()` guards at each level to prevent `NavJsonToken → NavJsonObject` conversion errors.

---

### 6.12 EscapeJson (local)

```al
local procedure EscapeJson(pInput: Text): Text
```

**Purpose:** Escapes special characters for safe embedding in JSON string values.

| Character | Escaped As |
|---|---|
| `\` | `\\` |
| `"` | `\"` |
| Line Feed (10) | `\n` |
| Carriage Return (13) | `\r` |
| Tab (9) | `\t` |

> Uses `LF[1] := 10; CR[1] := 13; TAB[1] := 9;` character assignment pattern since AL has no `Chr()` function.

---

## 7. Monday.com Board Configuration

**Board ID:** `5026308475`  
**Default Group ID:** `topics`  
**Assignee User ID (Rommel Marquez):** `98458747`

### Column ID Reference

| BC Field | Column ID | Monday.com Type | JSON Format |
|---|---|---|---|
| Subject (item name) | *(item name — not a column)* | — | Passed as `item_name` in mutation |
| BMG Name (Requestor) | `short_textk4s2qy1k` | text | `"value"` |
| BMG Comment | `long_text_mm1z55c4` | long_text | `{"text":"..."}` |
| BMG Description | `long_text` | long_text | `{"text":"..."}` |
| BMG Status | `status` | status | `{"label":"..."}` |
| Type of Request | `single_selectd87kj7c` | status | `{"label":"..."}` |
| BMG Assignee | `person` | people | `{"personsAndTeams":[{"id":UID,"kind":"person"}]}` |
| BMG Category | `dropdown_mm1d8yh0` | dropdown | `{"labels":["..."]}` |
| BMG Priority | `status_1` | status | `{"label":"..."}` |
| BMG Location | `single_selectyi1k98z` | status | `{"label":"..."}` |
| BMG Requestor Email | `email_mm02gjqa` | email | `{"email":"...","text":"..."}` |
| BMG Ticket ID | `pulse_id_mm02vm99` | item_id | Read-only; fetched via follow-up query |
| Files | `files` | file | Multipart upload via `add_file_to_column` |

---

## 8. End-to-End Flow

```
User opens BC
    │
    ├─► Opens "BC Monday Ticket List" (Page 68808)
    │       └─► OnOpenPage filters to SystemCreatedBy = current user
    │
    ├─► Clicks "New Ticket" → Opens "Monday.com Ticket" card (Page 68807)
    │       └─► Table OnInsert auto-populates Name + Email from BC User record
    │
    ├─► User fills in: Subject, Type of Request, Priority, Location, Comment, Description
    │
    └─► Clicks "Submit to Monday.com"
            │
            ├─► ComposeTicket() called
            │       ├─► Looks up current user (Full Name, Authentication Email)
            │       ├─► Builds column_values JSON
            │       ├─► Calls CreateTicket() → POST GraphQL mutation to Monday.com API
            │       │       └─► Returns numeric item ID (e.g. "8214792031")
            │       ├─► Calls FetchColumnText(itemId, 'pulse_id_mm02vm99')
            │       │       └─► Returns "TICKET-2184" formatted number
            │       ├─► Writes BMG Monday Item ID + BMG Ticket ID to record
            │       ├─► Calls Rec.Modify()
            │       └─► Shows Message: "Ticket Number TICKET-2184 has been created."
            │
            └─► CurrPage.Update(false) — all fields now locked (Enabled = false)

After submission:
    ├─► "Refresh Status" → GetTicketStatus(BMG Monday Item ID) → updates BMG Status
    └─► "Attach File" → UploadIntoStream → AddFileToTicket (4-part multipart POST)
```

---

## 9. Status Color Coding

BC uses the `StyleExpr` property to color-code status fields. Color is set in `OnAfterGetRecord` and applied via `StyleExpr = StatusStyle`.

| Monday.com Status | StyleExpr Value | BC Color |
|---|---|---|
| New | `Subordinate` | Gray |
| Working on it | `Ambiguous` | Orange |
| Waiting for Approval | `Attention` | Light Blue |
| Done | `Favorable` | Green |
| Pending | `Strong` | Dark Bold |
| Stuck | `Unfavorable` | Red *(card page only)* |
| *(anything else)* | `Standard` / `None` | Default |

---

## 10. Known Technical Notes

### AL Language Constraints

| Issue | AL Workaround |
|---|---|
| No `Chr()` function | Use index assignment: `LF[1] := 10;` on a `Text[1]` variable |
| No `&&` / `\|\|` in strings | Use string concatenation |
| `#` treated as preprocessor | Avoid `#13#10` style; use the `CRLF[1]/CRLF[2]` pattern |
| `JSON to Object` conversion error | Always call `JToken.IsObject()` before `.AsObject()` |

### Dual ID Fields

Monday.com uses two different identifiers for the same item:

- **Numeric item ID** (e.g., `8214792031`) — returned by `create_item`, used in all API calls (`GetTicketStatus`, `AddFileToTicket`). Stored in `BMG Monday Item ID`.
- **ICT Ticket Number** (e.g., `TICKET-2184`) — a formatted read-only column of type `item_id` on the board. Must be fetched with a separate `FetchColumnText` query after creation. Stored in `BMG Ticket ID` for display to users.

### File Upload Format

The Monday.com GraphQL API requires the **GraphQL multipart request specification** for file uploads. A plain JSON POST will fail with `"map not found in multipart form"`. The correct structure requires exactly 4 parts:
1. `query` — the mutation string
2. `variables` — `{"file": null}`
3. `map` — `{"file": ["variables.file"]}`
4. `file` — the binary content

### API Token Security

The API token is stored in `IsolatedStorage` (not as a Setup table record or hardcoded label). This is BC's recommended approach for secrets. It is scoped to `DataScope::Module` — shared across all users of the extension on the same environment but not accessible outside the extension.

> ⚠️ The `OnRun` trigger in the codeunit contains a hardcoded `SetApiToken(...)` call for development/testing purposes. **This should be removed or replaced with a proper setup page before production deployment.**
