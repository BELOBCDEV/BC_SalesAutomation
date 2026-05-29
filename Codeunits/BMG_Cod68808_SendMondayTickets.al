codeunit 68808 SendMondayTickets
{
    trigger OnRun()
    begin
        SendTicketsForMissingStatements(WorkDate());
    end;

    procedure SendTicketsForMissingStatements(pDate: Date)
    var
        recTransHeader: Record "LSC Transaction Header";
        recStoreCheck: Record "LSC Transaction Header";
        MondayMgt: Codeunit BMGMondayDotComMgt;
        recMondayTicket: Record BMGMondayTickets;
        CurrentStore: Code[10];
        HasMissing: Boolean;
        TicketCount: Integer;
    begin
        if pDate = 0D then
            Error('Please provide a valid date.');

        recTransHeader.Reset();
        recTransHeader.SetCurrentKey("Store No.", Date);
        recTransHeader.SetRange(Date, pDate);

        while recTransHeader.FindFirst() do begin
            CurrentStore := recTransHeader."Store No.";
            HasMissing := false;

            // Check if this store has any transaction on pDate without a Posted Statement No.
            recStoreCheck.Reset();
            recStoreCheck.SetRange("Store No.", CurrentStore);
            recStoreCheck.SetRange(Date, pDate);
            recStoreCheck.SetAutoCalcFields("Posted Statement No.");
            if recStoreCheck.FindSet() then
                repeat
                    if recStoreCheck."Posted Statement No." = '' then
                        HasMissing := true;
                until HasMissing or (recStoreCheck.Next() = 0);

            if HasMissing then begin
                CreateMissingStatementTicket(CurrentStore, pDate, MondayMgt);
                TicketCount += 1;
            end;

            // Advance to next distinct store
            recTransHeader.SetFilter("Store No.", '>%1', CurrentStore);
        end;

        /*
        if TicketCount = 0 then
            Message('No stores with missing Posted Statement No. found on %1.', pDate)
        else
            Message('%1 ticket(s) submitted to Monday.com for stores missing Posted Statement No. on %2.', TicketCount, pDate);
        */
    end;

    local procedure CreateMissingStatementTicket(pStoreNo: Code[10]; pDate: Date; var pMondayMgt: Codeunit BMGMondayDotComMgt)
    var
        recMondayTicket: Record BMGMondayTickets;
        recSalesSetup: Record "Sales & Receivables Setup";
        Subject: Text[100];
        Description: Text[2048];
        Comment: Text[2048];
    begin
        Subject := CopyStr(StrSubstNo('Missing Posted Statement - Store %1 on %2', pStoreNo, pDate), 1, 100);
        Description := CopyStr(
            StrSubstNo('Store %1 has transactions on %2 that are not yet posted to a Statement. Please review and post the statement.',
                pStoreNo, pDate), 1, 2048);
        Comment := 'If this is not resolved before 10:00 AM, it will delay the distribution of sales reports to leaders.';

        recMondayTicket.Init();
        recMondayTicket.Insert(true);  // OnInsert auto-fills Name and Email from current user

        recMondayTicket."BMG Subject" := Subject;
        recMondayTicket."BMG Description" := Description;
        recMondayTicket."Type of Request" := recMondayTicket."Type of Request"::Incident;
        recMondayTicket."BMG Priority" := recMondayTicket."BMG Priority"::High;
        recMondayTicket."BMG Location" := recMondayTicket."BMG Location"::"Head Office - Finance";
        recMondayTicket."BMG Comment" := Comment;
        recMondayTicket.Validate("BMG Assignee User", Enum::BMGMondayAssignees::"Rommel Marquez");
        recMondayTicket.Modify();

        recSalesSetup.Get();

        pMondayMgt.SetApiToken(recSalesSetup."API Key 2");
        pMondayMgt.ComposeTicket(
            recMondayTicket."BMG Subject",
            recMondayTicket."BMG Comment",
            Format(recMondayTicket."Type of Request"),
            Format(recMondayTicket."BMG Priority"),
            Format(recMondayTicket."BMG Location"),
            recMondayTicket."BMG Description",
            recMondayTicket);
        Clear(pMondayMgt);
    end;
}
