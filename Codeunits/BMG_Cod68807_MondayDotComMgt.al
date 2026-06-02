codeunit 68807 BMGMondayDotComMgt
{
    trigger OnRun()
    var
        NewItemId: Text;
        TempBlob: Codeunit "Temp Blob";
        FileStream: InStream;
        OutStr: OutStream;
        SampleText: Text;
    begin
        SetApiToken('eyJhbGciOiJIUzI1NiJ9.eyJ0aWQiOjY2MDY3NjUyNSwiYWFpIjoxMSwidWlkIjo5ODQ1ODc0NywiaWFkIjoiMjAyNi0wNS0yMFQwMTozODo1NS4wMDBaIiwicGVyIjoibWU6d3JpdGUiLCJhY3RpZCI6MzIzNTg5NTQsInJnbiI6ImFwc2UyIn0.teXDBjaZm5ch2Ix6e7uXp09BMLfivnVnuCcbUM3xTqo');
        //NewItemId := ComposeTicket('Sample Ticket being created from BC', 'This is a test comment from Business Central.', 'Incident', 'Medium', 'Head Office - ICT', 'Full description of the issue goes here.');

        // Attach a file — replace with your actual file source (e.g. from record attachment)
        SampleText := 'This is a sample text file attached from Business Central.';
        TempBlob.CreateOutStream(OutStr);
        OutStr.WriteText(SampleText);
        TempBlob.CreateInStream(FileStream);
        AddFileToTicket(NewItemId, 'files', 'sample.txt', FileStream);

        Message('Ticket %1 created with attachment.', NewItemId);
    end;

    /// <summary>
    /// Creates an item on a Monday.com board.
    /// Returns the new item's ID, or empty text if creation failed silently.
    ///
    /// pBoardId      - Monday.com board ID (found in the board URL)
    /// pGroupId      - Group ID within the board (e.g. 'topics', 'new_group')
    /// pItemName     - Name/title of the new ticket
    /// pColumnValues - Stringified JSON of column values, e.g.:
    ///                 '{"status":{"label":"Working on it"},"text":"some notes"}'
    ///                 Pass empty text to skip.
    /// </summary>

    procedure ComposeTicket(pSubject: Text; pComment: Text; pTypeOfRequest: Text; pPriority: Text; pLocation: Text; pDescription: Text; var pRecMondayTicket: Record BMGMondayTickets; pIntBoard: Integer): Text
    var
        recUser: Record User;
        recSalesSetup: Record "Sales & Receivables Setup";
        ColValues: Text;
        RequesterName: Text;
        RequesterEmail: Text;
        NewItemId: Text[50];
        IctTicketNo: Text;
        BoardID: Text[50];
    begin
        recUser.Reset();
        recUser.SetRange("User Name", UserId);
        if recUser.FindFirst() then begin
            RequesterName := recUser."Full Name";
            RequesterEmail := recUser."Authentication Email";
        end;

        if pRecMondayTicket."BMG Assignee ID" = '' then
            if GuiAllowed then
                Error('Please select an Assignee before submitting.');

        ColValues :=
            '{"person":{"personsAndTeams":[{"id":' + pRecMondayTicket."BMG Assignee ID" + ',"kind":"person"}]}' +
            ',"short_textk4s2qy1k":"' + EscapeJson(RequesterName) + '"' +
            ',"long_text_mm1z55c4":{"text":"' + EscapeJson(pComment) + '"}' +
            ',"long_text":{"text":"' + EscapeJson(pDescription) + '"}' +
            ',"single_selectd87kj7c":{"label":"' + EscapeJson(pTypeOfRequest) + '"}' +
            ',"status_1":{"label":"' + EscapeJson(pPriority) + '"}' +
            ',"single_selectyi1k98z":{"label":"' + EscapeJson(pLocation) + '"}' +
            ',"dropdown_mm1d8yh0":{"labels":["Application - Business Central"]}' +
            ',"email_mm02gjqa":{"email":"' + EscapeJson(RequesterEmail) + '","text":"' + EscapeJson(RequesterEmail) + '"}}';

        recSalesSetup.Get();
        //'5026308475'
        case pIntBoard of
            1:
                BoardID := recSalesSetup."Corp IT Ticket Board ID";
            2:
                BoardID := recSalesSetup."Cross-Dept Request Board ID";
        end;

        NewItemId := CreateTicket(BoardID, 'topics', pSubject, ColValues, IctTicketNo);

        pRecMondayTicket."BMG Monday Item ID" := NewItemId;
        pRecMondayTicket."BMG Ticket ID" := FetchColumnText(NewItemId, 'pulse_id_mm02vm99');
        pRecMondayTicket."BMG Assignee" := FetchColumnText(NewItemId, 'person');
        pRecMondayTicket."BMG Requestor Email" := RequesterEmail;
        pRecMondayTicket."Date Submitted" := CurrentDateTime;
        pRecMondayTicket.Modify();
        if GuiAllowed then
            Message('Ticket Number %1 with Ticket ID %2 has been created.', pRecMondayTicket."BMG Ticket ID", NewItemId);
        exit(NewItemId);
    end;

    procedure AddFileToTicket(pItemId: Text; pFileColumnId: Text; pFileName: Text; var pFileStream: InStream)
    var
        HttpClient: HttpClient;
        HttpRequest: HttpRequestMessage;
        HttpResponse: HttpResponseMessage;
        HttpContent: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        TempBlobBody: Codeunit "Temp Blob";
        BodyOutStr: OutStream;
        BodyInStr: InStream;
        Boundary: Text;
        ResponseBody: Text;
        CRLF: Text[2];
    begin
        CRLF[1] := 13;
        CRLF[2] := 10;
        Boundary := 'BMGBoundary' + Format(CurrentDateTime, 0, '<Day,2><Month,2><Year4><Hours24,2><Minutes,2><Seconds,2>');

        TempBlobBody.CreateOutStream(BodyOutStr);

        // Part 1: query
        BodyOutStr.WriteText('--' + Boundary + CRLF);
        BodyOutStr.WriteText('Content-Disposition: form-data; name="query"' + CRLF + CRLF);
        BodyOutStr.WriteText('mutation ($file: File!) { add_file_to_column (item_id: ' + pItemId +
            ', column_id: "' + pFileColumnId + '", file: $file) { id } }' + CRLF);

        // Part 2: variables
        BodyOutStr.WriteText('--' + Boundary + CRLF);
        BodyOutStr.WriteText('Content-Disposition: form-data; name="variables"' + CRLF + CRLF);
        BodyOutStr.WriteText('{"file": null}' + CRLF);

        // Part 3: map
        BodyOutStr.WriteText('--' + Boundary + CRLF);
        BodyOutStr.WriteText('Content-Disposition: form-data; name="map"' + CRLF + CRLF);
        BodyOutStr.WriteText('{"file": ["variables.file"]}' + CRLF);

        // Part 4: file binary
        BodyOutStr.WriteText('--' + Boundary + CRLF);
        BodyOutStr.WriteText('Content-Disposition: form-data; name="file"; filename="' + pFileName + '"' + CRLF);
        BodyOutStr.WriteText('Content-Type: application/octet-stream' + CRLF + CRLF);
        CopyStream(BodyOutStr, pFileStream);
        BodyOutStr.WriteText(CRLF + '--' + Boundary + '--');

        TempBlobBody.CreateInStream(BodyInStr);
        HttpContent.WriteFrom(BodyInStr);
        HttpContent.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'multipart/form-data; boundary=' + Boundary);

        HttpRequest.Method := 'POST';
        HttpRequest.SetRequestUri(MondayApiUrlTok);
        HttpRequest.Content := HttpContent;
        HttpRequest.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', 'Bearer ' + GetApiToken());
        RequestHeaders.Add('API-Version', '2023-10');

        if not HttpClient.Send(HttpRequest, HttpResponse) then
            Error(ConnectionErrLbl);

        HttpResponse.Content.ReadAs(ResponseBody);
        if not HttpResponse.IsSuccessStatusCode() then
            Error(ApiErrLbl, HttpResponse.HttpStatusCode, ResponseBody);
    end;

    procedure CreateTicket(pBoardId: Text; pGroupId: Text; pItemName: Text; pColumnValues: Text; var pIctTicketNo: Text): Text
    var
        HttpClient: HttpClient;
        HttpRequest: HttpRequestMessage;
        HttpResponse: HttpResponseMessage;
        HttpContent: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        JRequest: JsonObject;
        JVariables: JsonObject;
        JToken: JsonToken;
        RequestBody: Text;
        ResponseBody: Text;
    begin
        JVariables.Add('boardId', pBoardId);
        JVariables.Add('groupId', pGroupId);
        JVariables.Add('itemName', pItemName);
        if pColumnValues <> '' then
            JVariables.Add('columnValues', pColumnValues);

        JRequest.Add('query', BuildMutationQuery(pColumnValues <> ''));
        JRequest.Add('variables', JVariables);
        JRequest.WriteTo(RequestBody);

        HttpContent.WriteFrom(RequestBody);
        HttpContent.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        HttpRequest.Method := 'POST';
        HttpRequest.SetRequestUri(MondayApiUrlTok);
        HttpRequest.Content := HttpContent;
        HttpRequest.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', 'Bearer ' + GetApiToken());
        RequestHeaders.Add('API-Version', '2023-10');

        if not HttpClient.Send(HttpRequest, HttpResponse) then
            Error(ConnectionErrLbl);

        HttpResponse.Content.ReadAs(ResponseBody);
        if not HttpResponse.IsSuccessStatusCode() then
            Error(ApiErrLbl, HttpResponse.HttpStatusCode, ResponseBody);

        exit(ParseItemId(ResponseBody, pIctTicketNo));
    end;

    /// <summary>
    /// Convenience wrapper — builds column_values JSON from the most common fields.
    /// Pass empty text for fields you don't need.
    /// Column IDs ('status', 'text', 'date4') must match your board's actual column IDs.
    /// </summary>
    procedure CreateTicketSimple(pBoardId: Text; pGroupId: Text; pItemName: Text; pStatus: Text; pDescription: Text; pDueDate: Date): Text
    var
        ColBuilder: TextBuilder;
        DateStr: Text;
        FirstField: Boolean;
        IctTicketNo: Text;
    begin
        FirstField := true;
        ColBuilder.Append('{');

        if pStatus <> '' then begin
            ColBuilder.Append('"status":{"label":"');
            ColBuilder.Append(EscapeJson(pStatus));
            ColBuilder.Append('"}');
            FirstField := false;
        end;

        if pDescription <> '' then begin
            if not FirstField then ColBuilder.Append(',');
            ColBuilder.Append('"text":"');
            ColBuilder.Append(EscapeJson(pDescription));
            ColBuilder.Append('"');
            FirstField := false;
        end;

        if pDueDate <> 0D then begin
            if not FirstField then ColBuilder.Append(',');
            DateStr := Format(pDueDate, 0, '<Year4>-<Month,2>-<Day,2>');
            ColBuilder.Append('"date4":{"date":"');
            ColBuilder.Append(DateStr);
            ColBuilder.Append('"}');
        end;

        ColBuilder.Append('}');

        exit(CreateTicket(pBoardId, pGroupId, pItemName, ColBuilder.ToText(), IctTicketNo));
    end;

    procedure ShowBoardColumns(pBoardId: Text)
    var
        HttpClient: HttpClient;
        HttpRequest: HttpRequestMessage;
        HttpResponse: HttpResponseMessage;
        HttpContent: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        JRequest: JsonObject;
        JToken: JsonToken;
        JArray: JsonArray;
        JColToken: JsonToken;
        RequestBody: Text;
        ResponseBody: Text;
        ColList: TextBuilder;
        ColId: Text;
        ColTitle: Text;
        ColType: Text;
    begin
        JRequest.Add('query', '{ boards(ids: ' + pBoardId + ') { columns { id title type } } }');
        JRequest.WriteTo(RequestBody);

        HttpContent.WriteFrom(RequestBody);
        HttpContent.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        HttpRequest.Method := 'POST';
        HttpRequest.SetRequestUri(MondayApiUrlTok);
        HttpRequest.Content := HttpContent;
        HttpRequest.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', 'Bearer ' + GetApiToken());
        RequestHeaders.Add('API-Version', '2023-10');

        if not HttpClient.Send(HttpRequest, HttpResponse) then
            Error(ConnectionErrLbl);

        HttpResponse.Content.ReadAs(ResponseBody);
        if not HttpResponse.IsSuccessStatusCode() then
            Error(ApiErrLbl, HttpResponse.HttpStatusCode, ResponseBody);

        // Parse: data.boards[0].columns[]
        if not JToken.ReadFrom(ResponseBody) then
            Error('Failed to parse response.');
        if not JToken.AsObject().Get('data', JToken) then
            Error('No data in response.');
        if not JToken.AsObject().Get('boards', JToken) then
            Error('No boards in response.');
        JArray := JToken.AsArray();
        if not JArray.Get(0, JToken) then
            Error('Board not found.');
        if not JToken.AsObject().Get('columns', JToken) then
            Error('No columns in response.');
        JArray := JToken.AsArray();

        ColList.Append('ID | Title | Type\n');
        ColList.Append('--------------------\n');
        foreach JColToken in JArray do begin
            ColId := '';
            ColTitle := '';
            ColType := '';
            if JColToken.AsObject().Get('id', JToken) then ColId := JToken.AsValue().AsText();
            if JColToken.AsObject().Get('title', JToken) then ColTitle := JToken.AsValue().AsText();
            if JColToken.AsObject().Get('type', JToken) then ColType := JToken.AsValue().AsText();
            ColList.Append(ColId + ' | ' + ColTitle + ' | ' + ColType + '\n');
        end;

        Message(ColList.ToText());
    end;

    procedure FetchAssignee(pItemId: Text): Text
    begin
        exit(FetchColumnText(pItemId, 'person'));
    end;

    procedure FetchRequestorEmail(pItemId: Text): Text
    begin
        exit(FetchColumnText(pItemId, 'email_mm02gjqa'));
    end;

    procedure UpdateAssigneeFields(pAssigneeText: Text; var pRec: Record BMGMondayTickets)
    begin
        case pAssigneeText of
            'jtenoso@belomed.com', 'jtenoso':
                pRec.Validate("BMG Assignee User", Enum::BMGMondayAssignees::jtenoso);
            'Marlon Rubir':
                pRec.Validate("BMG Assignee User", Enum::BMGMondayAssignees::"Marlon Rubir");
            'Rommel Marquez':
                pRec.Validate("BMG Assignee User", Enum::BMGMondayAssignees::"Rommel Marquez");
            'tfernandez@belomed.com', 'tfernandez':
                pRec.Validate("BMG Assignee User", Enum::BMGMondayAssignees::tfernandez);
            'Victor Michael Buenavista':
                pRec.Validate("BMG Assignee User", Enum::BMGMondayAssignees::"Victor Michael Buenavista");
        end;
    end;

    procedure GetTicketStatus(pItemId: Text): Text
    var
        HttpClient: HttpClient;
        HttpRequest: HttpRequestMessage;
        HttpResponse: HttpResponseMessage;
        HttpContent: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        JRequest: JsonObject;
        JToken: JsonToken;
        JArray: JsonArray;
        RequestBody: Text;
        ResponseBody: Text;
    begin
        JRequest.Add('query', '{ items(ids: [' + pItemId + ']) { column_values(ids: ["status"]) { text } } }');
        JRequest.WriteTo(RequestBody);

        HttpContent.WriteFrom(RequestBody);
        HttpContent.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        HttpRequest.Method := 'POST';
        HttpRequest.SetRequestUri(MondayApiUrlTok);
        HttpRequest.Content := HttpContent;
        HttpRequest.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', 'Bearer ' + GetApiToken());
        RequestHeaders.Add('API-Version', '2023-10');

        if not HttpClient.Send(HttpRequest, HttpResponse) then
            Error(ConnectionErrLbl);

        HttpResponse.Content.ReadAs(ResponseBody);
        if not HttpResponse.IsSuccessStatusCode() then
            Error(ApiErrLbl, HttpResponse.HttpStatusCode, ResponseBody);

        // Parse: data.items[0].column_values[0].text
        if not JToken.ReadFrom(ResponseBody) then
            exit('');
        if not JToken.IsObject() then
            exit('');
        if not JToken.AsObject().Get('data', JToken) then
            exit('');
        if not JToken.IsObject() then
            exit('');
        if not JToken.AsObject().Get('items', JToken) then
            exit('');
        if not JToken.IsArray() then
            exit('');
        JArray := JToken.AsArray();
        if not JArray.Get(0, JToken) then
            exit('');
        if not JToken.IsObject() then
            exit('');
        if not JToken.AsObject().Get('column_values', JToken) then
            exit('');
        if not JToken.IsArray() then
            exit('');
        JArray := JToken.AsArray();
        if not JArray.Get(0, JToken) then
            exit('');
        if not JToken.IsObject() then
            exit('');
        if JToken.AsObject().Get('text', JToken) then
            exit(JToken.AsValue().AsText());
        exit('');
    end;

    local procedure FetchColumnText(pItemId: Text; pColumnId: Text): Text
    var
        HttpClient: HttpClient;
        HttpRequest: HttpRequestMessage;
        HttpResponse: HttpResponseMessage;
        HttpContent: HttpContent;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        JRequest: JsonObject;
        JToken: JsonToken;
        JArray: JsonArray;
        RequestBody: Text;
        ResponseBody: Text;
    begin
        JRequest.Add('query', '{ items(ids: [' + pItemId + ']) { column_values(ids: ["' + pColumnId + '"]) { text } } }');
        JRequest.WriteTo(RequestBody);

        HttpContent.WriteFrom(RequestBody);
        HttpContent.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        HttpRequest.Method := 'POST';
        HttpRequest.SetRequestUri(MondayApiUrlTok);
        HttpRequest.Content := HttpContent;
        HttpRequest.GetHeaders(RequestHeaders);
        RequestHeaders.Add('Authorization', 'Bearer ' + GetApiToken());
        RequestHeaders.Add('API-Version', '2023-10');

        if not HttpClient.Send(HttpRequest, HttpResponse) then
            exit('');
        HttpResponse.Content.ReadAs(ResponseBody);
        if not HttpResponse.IsSuccessStatusCode() then
            exit('');

        // Parse: data.items[0].column_values[0].text
        if not JToken.ReadFrom(ResponseBody) then exit('');
        if not JToken.IsObject() then exit('');
        if not JToken.AsObject().Get('data', JToken) then exit('');
        if not JToken.IsObject() then exit('');
        if not JToken.AsObject().Get('items', JToken) then exit('');
        if not JToken.IsArray() then exit('');
        JArray := JToken.AsArray();
        if not JArray.Get(0, JToken) then exit('');
        if not JToken.IsObject() then exit('');
        if not JToken.AsObject().Get('column_values', JToken) then exit('');
        if not JToken.IsArray() then exit('');
        JArray := JToken.AsArray();
        if not JArray.Get(0, JToken) then exit('');
        if not JToken.IsObject() then exit('');
        if JToken.AsObject().Get('text', JToken) then
            exit(JToken.AsValue().AsText());
        exit('');
    end;

    procedure SetApiToken(pToken: Text)
    begin
        IsolatedStorage.Set(ApiTokenKeyTok, pToken, DataScope::Module);
    end;

    local procedure GetApiToken(): Text
    var
        ApiToken: Text;
    begin
        if not IsolatedStorage.Get(ApiTokenKeyTok, DataScope::Module, ApiToken) then
            Error(NoTokenErrLbl);
        exit(ApiToken);
    end;

    local procedure BuildMutationQuery(pIncludeColumnValues: Boolean): Text
    var
        IctColId: Text;
    begin
        IctColId := 'pulse_id_mm02vm99';
        if pIncludeColumnValues then
            exit('mutation ($boardId: ID!, $groupId: String!, $itemName: String!, $columnValues: JSON) ' +
                 '{ create_item (board_id: $boardId, group_id: $groupId, item_name: $itemName, column_values: $columnValues) ' +
                 '{ id column_values(ids: ["' + IctColId + '"]) { text } } }');

        exit('mutation ($boardId: ID!, $groupId: String!, $itemName: String!) ' +
             '{ create_item (board_id: $boardId, group_id: $groupId, item_name: $itemName) ' +
             '{ id column_values(ids: ["' + IctColId + '"]) { text } } }');
    end;

    local procedure ParseItemId(pResponseBody: Text; var pIctTicketNo: Text): Text
    var
        JResponse: JsonObject;
        JToken: JsonToken;
        JItemObj: JsonObject;
        JField: JsonToken;
        JColToken: JsonToken;
        ItemId: Text;
    begin
        JResponse.ReadFrom(pResponseBody);
        if not JResponse.Get('data', JToken) then exit('');
        if not JToken.IsObject() then exit('');
        if not JToken.AsObject().Get('create_item', JToken) then exit('');
        if not JToken.IsObject() then exit('');
        JItemObj := JToken.AsObject();

        if JItemObj.Get('id', JField) then
            ItemId := JField.AsValue().AsText();

        if JItemObj.Get('column_values', JField) then
            if JField.IsArray() then
                if JField.AsArray().Get(0, JColToken) then
                    if JColToken.IsObject() then
                        if JColToken.AsObject().Get('text', JField) then
                            pIctTicketNo := JField.AsValue().AsText();

        exit(ItemId);
    end;

    local procedure EscapeJson(pInput: Text): Text
    var
        LF: Text[1];
        CR: Text[1];
        TAB: Text[1];
    begin
        LF[1] := 10;
        CR[1] := 13;
        TAB[1] := 9;
        pInput := pInput.Replace('\', '\\');
        pInput := pInput.Replace('"', '\"');
        pInput := pInput.Replace(LF, '\n');
        pInput := pInput.Replace(CR, '\r');
        pInput := pInput.Replace(TAB, '\t');
        exit(pInput);
    end;

    var
        MondayApiUrlTok: Label 'https://api.monday.com/v2', Locked = true;
        ApiTokenKeyTok: Label 'BMGMondayApiToken', Locked = true;
        ConnectionErrLbl: Label 'Could not connect to Monday.com. Verify network access and the API URL.';
        ApiErrLbl: Label 'Monday.com API error (HTTP %1):\n%2', Comment = '%1=HTTP status code, %2=response body';
        NoTokenErrLbl: Label 'Monday.com API token is not set. Run SetApiToken() once to store it.';
}
