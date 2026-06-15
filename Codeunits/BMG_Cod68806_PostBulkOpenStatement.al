codeunit 68806 BMGPostBulkOpenStatement
{
    trigger OnRun()
    var
        recGItem: Record Item;
        recGCustomer: Record Customer;
    begin
        recItem.DeleteAll();
        recItem2.DeleteAll();
        recTempStatement.DeleteAll();
        recTempStatement2.DeleteAll();
        recTempStatement3.DeleteAll();

        recOpenStatement.Reset();
        recOpenStatement.SetRange("Posting Date", WorkDate());

        if recOpenStatement.FindFirst() then
            repeat
                recLSCTransStatus.Reset();
                recLSCTransStatus.SetRange("Statement No.", recOpenStatement."No.");

                if recLSCTransStatus.FindFirst() then
                    repeat
                        bolErrorFound := false;
                        if recLSCTransStatus."No. of Blank UOM Item" <> 0 then begin
                            bolErrorFound := true;
                            recItem2.Init();
                            recItem2."No." := recOpenStatement."No." + '_1';
                            recItem2."Gen. Prod. Posting Group" := recOpenStatement."Store No.";
                            if recItem2.Insert() then;
                        end;
                        if recLSCTransStatus."Serial/Lot No. Not Valid" <> 0 then begin
                            bolErrorFound := true;
                            recItem2.Init();
                            recItem2."No." := recOpenStatement."No." + '_2';
                            recItem2."Gen. Prod. Posting Group" := recOpenStatement."Store No.";
                            if recItem2.Insert() then;
                        end;
                        if recLSCTransStatus."Items/Barc. Not on File" <> 0 then begin
                            bolErrorFound := true;
                            recItem2.Init();
                            recItem2."No." := recOpenStatement."No." + '_3';
                            recItem2."Gen. Prod. Posting Group" := recOpenStatement."Store No.";
                            if recItem2.Insert() then;
                        end;
                        if recLSCTransStatus."Blocked Customer" = true then begin
                            ResolveBlockedCustomer(recOpenStatement."Store No.");
                            /*
                            bolErrorFound := true;
                            recItem2.Init();
                            recItem2."No." := recOpenStatement."No." + '_4';
                            recItem2."Gen. Prod. Posting Group" := recOpenStatement."Store No.";
                            if recItem2.Insert() then;
                            */
                        end;
                        if recLSCTransStatus."Items Blocked" <> 0 then begin
                            ResolveBlockedItems(recOpenStatement."Store No.");
                            /*
                            bolErrorFound := true;
                            recItem2.Init();
                            recItem2."No." := recOpenStatement."No." + '_5';
                            recItem2."Gen. Prod. Posting Group" := recOpenStatement."Store No.";
                            if recItem2.Insert() then;
                            */
                        end;
                    until (recLSCTransStatus.Next() = 0) OR (bolErrorFound = true);

                recOpenStatementLine2.Reset();
                recOpenStatementLine2.SetRange("Statement No.", recOpenStatement."No.");
                recOpenStatementLine2.SetRange("Tender Type Name", 'CASH');

                intStatementCtr := 0;

                if recOpenStatementLine2.FindFirst() then
                    repeat
                        if (recOpenStatementLine2."Difference Amount" <> 0) and (recOpenStatementLine2."Counted Amount" <> 0) then
                            intStatementCtr += 1;
                    until recOpenStatementLine2.Next() = 0;

                recOpenStatementLine.Reset();
                recOpenStatementLine.SetRange("Statement No.", recOpenStatement."No.");
                recOpenStatementLine.SetRange("Tender Type Name", 'CASH');

                intLineCtr := 0;

                if recOpenStatementLine.FindFirst() then
                    repeat
                        if (recOpenStatementLine."Difference Amount" <> 0) and (recOpenStatementLine."Counted Amount" <> 0) then begin
                            recTenderDecl.Reset();
                            recTenderDecl.SetRange(Date, WorkDate());
                            recTenderDecl.SetRange("Store No.", recOpenStatementLine."Store No.");
                            recTenderDecl.SetRange("POS Terminal No.", recOpenStatementLine."POS Terminal No.");

                            decAmountTendered := 0;

                            if recTenderDecl.FindFirst() then
                                repeat
                                    decAmountTendered += recTenderDecl."Amount Tendered";
                                until recTenderDecl.Next() = 0;

                            if (decAmountTendered = recOpenStatementLine."Counted Amount") then begin
                                intLineCtr += 1;
                                //store date, store/branch, difference amt
                                recTempStatement.Init();
                                recTempStatement."Store No." := recOpenStatementLine."Store No.";
                                recTempStatement."No." := Format(intLineCtr);
                                recTempStatement.Date := WorkDate();
                                recTempStatement."BMG Difference Amount" := recOpenStatementLine."Difference Amount";
                                if recTempStatement.Insert() then;

                            end else
                                bolErrorFound := true;
                        end;
                    until (recOpenStatementLine.Next() = 0) OR (bolErrorFound = true);

                if (intLineCtr = intStatementCtr) and (intLineCtr >= 1) then begin
                    //ticket the treasury informing there is diffrenece amount
                    //Message('Store No. %1\StatementCtr %2\LineCtr %3', recOpenStatement."Store No.", intStatementCtr, intLineCtr);
                    recSalesSetup.Get();

                    if recSalesSetup."Enable Sending to Monday" then begin
                        recStore.Reset();
                        recStore.SetRange("No.", recOpenStatement."Store No.");
                        if recStore.FindFirst() then
                            txtStoreName := recStore.Name;

                        recTempStatement.Reset();
                        recTempStatement.SetRange(Date, WorkDate());
                        recTempStatement.SetRange("Store No.", recOpenStatement."Store No.");

                        decDifferenceAmount := 0;

                        if recTempStatement.FindFirst() then
                            repeat
                                decDifferenceAmount += recTempStatement."BMG Difference Amount";
                            until recTempStatement.Next() = 0;

                        txtSubject := txtStoreName + ' ' + Format(WorkDate()) + ' Shortage Amount - ' + Format(decDifferenceAmount);

                        recMondayTicket.Reset();
                        if recMondayTicket.FindLast() then begin
                            recMondayTicket2.Init();
                            recMondayTicket2."Entry No." := recMondayTicket."Entry No." + 1;
                            recMondayTicket2."BMG Assignee ID" := '100473531'; //RM- '98458747';
                            recMondayTicket2."BMG Subject" := txtSubject;
                            recMondayTicket2."BMG Comment" := StrSubstNo('May we request your assistance in reviewing %1 dated %2', recOpenStatement."Store No.", WorkDate());
                            recMondayTicket2."Type of Request" := recMondayTicket2."Type of Request"::Incident;
                            recMondayTicket2."BMG Priority" := recMondayTicket2."BMG Priority"::Low;
                            recMondayTicket2."BMG Location" := recMondayTicket2."BMG Location"::"Head Office - Finance";
                            recMondayTicket2."BMG Description" := 'We noted entries posted to Accounts Receivable - Shortages and Charges\' +
                                                                  'due to variances between the POS sales amount and the declared amount.';
                            if recMondayTicket2.Insert() then;
                        end;

                        codMondayMgt.SetApiToken(recSalesSetup."API Key 2");
                        codMondayMgt.ComposeTicket(recMondayTicket2."BMG Subject",
                             recMondayTicket2."BMG Comment",
                             Format(recMondayTicket2."Type of Request"),
                             Format(recMondayTicket2."BMG Priority"),
                             Format(recMondayTicket2."BMG Location"),
                             recMondayTicket2."BMG Description",
                             recMondayTicket2, 2);

                        //codMondayMgt.ComposeTicket(txtSubject,
                        //StrSubstNo('The Statement No. %1 has been posted even though there is a difference amount.', recOpenStatement."No."),
                        //'Incident', 'LOW', 'Head Office - Finance', 'This ticket was auto-created via business central.', recMondayTicket2);
                        Clear(codMondayMgt);
                    end;
                end;

                If not bolErrorFound then begin
                    if HasStatementLines(recOpenStatement."No.") then begin
                        recItem.Init();
                        recItem."No." := recOpenStatement."No.";
                        if recItem.Insert() then;
                    end;
                    //Message('Statement No. %1 has been included for posting', recItem."No.");
                end;

            until recOpenStatement.Next() = 0;

        recItem.Reset();
        if recItem.FindFirst() then
            repeat
                //Message('Posting Statement No. %1', recItem."No.");
                recOpenStatement.Reset();
                recOpenStatement.SetRange("No.", recItem."No.");

                if recOpenStatement.FindFirst() then begin
                    codPostOpenStatement.PostStatement(recOpenStatement, recStore, BatchPostingStatus, BatchPosting);
                    Clear(codPostOpenStatement);
                end;

                //block the item that was unblock before posting
                recTempStatement2.Reset();
                recTempStatement2.SetRange("No.", recItem."No.");

                if recTempStatement2.FindFirst() then
                    repeat
                        recGItem.Reset();
                        recGItem.SetRange("No.", recTempStatement2."No. Series.");

                        if recGItem.FindFirst() then begin
                            recGItem.Blocked := true;
                            recGItem.Modify();
                        end;
                    until recTempStatement2.Next() = 0;

                //block the customer that was unblock before posting
                recTempStatement3.Reset();
                recTempStatement3.SetRange("No.", recItem."No.");

                if recTempStatement2.FindFirst() then begin
                    recGCustomer.Reset();
                    recGCustomer.SetRange("No.", recTempStatement3."No. Series.");

                    if recGCustomer.FindFirst() then begin
                        recGCustomer.Blocked := recGCustomer.Blocked::All;
                        recGCustomer.Modify();
                    end;
                end;

            until recItem.Next() = 0;

        recSalesSetup.Get();

        if recSalesSetup."Enable Sending to Monday" then begin
            recItem2.Reset();
            if recItem2.FindFirst() then
                repeat
                    //Message('Statement No. %1 has an error.', recItem2."No.");
                    recStore.Reset();
                    recStore.SetRange("No.", recItem2."Gen. Prod. Posting Group");
                    if recStore.FindFirst() then
                        txtStoreName := recStore.Name;
                    txtSubject := 'URGENT: ' + Format(WorkDate()) + ' INVENTORY ERROR - ' + txtStoreName;

                    recMondayTicket.Reset();
                    if recMondayTicket.FindLast() then begin
                        recMondayTicket2.Init();
                        recMondayTicket2."Entry No." := recMondayTicket."Entry No." + 1;
                        recMondayTicket2."BMG Assignee ID" := '98458747'; //trina - 100473531';                        recMondayTicket2."BMG Subject" := txtSubject;
                        recMondayTicket2."BMG Comment" := 'If this is not resolved before 10:00 AM, it will delay the distribution of sales reports to leaders.';
                        recMondayTicket2."Type of Request" := recMondayTicket2."Type of Request"::Incident;
                        recMondayTicket2."BMG Priority" := recMondayTicket2."BMG Priority"::High;
                        recMondayTicket2."BMG Location" := recMondayTicket2."BMG Location"::"Head Office - Finance";

                        case true of
                            STRPOS(recItem2."No.", '_1') <> 0:
                                txtMondayDescription := 'No. of Blank UOM Item count is > 0.';
                            STRPOS(recItem2."No.", '_2') <> 0:
                                txtMondayDescription := 'Serial/Lot No. Not Invalid count is > 0.';
                            STRPOS(recItem2."No.", '_3') <> 0:
                                txtMondayDescription := 'Items/Barc. Not on File count is > 0.';
                            STRPOS(recItem2."No.", '_4') <> 0:
                                txtMondayDescription := 'Blocked Customer count is > 0.';
                            STRPOS(recItem2."No.", '_5') <> 0:
                                txtMondayDescription := 'Items Blocked count is > 0.';
                        end;

                        recMondayTicket2."BMG Description" := txtMondayDescription;
                        if recMondayTicket2.Insert() then;
                        Commit();
                    end;

                    codMondayMgt.SetApiToken(recSalesSetup."API Key 2");
                    codMondayMgt.ComposeTicket(recMondayTicket2."BMG Subject",
                             recMondayTicket2."BMG Comment",
                             Format(recMondayTicket2."Type of Request"),
                             Format(recMondayTicket2."BMG Priority"),
                             Format(recMondayTicket2."BMG Location"),
                             recMondayTicket2."BMG Description",
                             recMondayTicket2, 1);
                    //codMondayMgt.ComposeTicket(txtSubject,
                    //'If this is not resolved before 10:00 AM, it will delay the distribution of sales reports to leaders.',
                    //'Incident', 'HIGH', 'Head Office - Finance', txtMondayDescription, recMondayTicket2);
                    Clear(codMondayMgt);
                until recItem2.Next() = 0;
        end;

    end;

    local procedure ResolveBlockedItems(pStoreNo: code[20])
    var
        recLSCTransSales: Record "LSC Trans. Sales Entry";
        recLSCTransStatus: Record "LSC Transaction Status";
        recLItem: Record Item;
        codLItem: Code[20];
    begin
        recLSCTransSales.Reset();
        recLSCTransSales.SetRange("Trans. Date", WorkDate());
        recLSCTransSales.SetRange("Store No.", pStoreNo);
        recLSCTransSales.SetRange("Transaction Code", recLSCTransSales."Transaction Code"::"Item Blocked");

        if recLSCTransSales.FindFirst() then
            repeat
                //Message('Item No. is %1', recLSCTransSales."Item No.");
                recLItem.Reset();
                recLItem.SetRange("No.", recLSCTransSales."Item No.");

                codLItem := '';

                if recLItem.FindFirst() then begin
                    if recLItem.Blocked then begin
                        recLItem.Blocked := false;
                        recLItem.Modify();

                        codLItem := recLItem."No.";
                    end;
                    //Message('Item no. %1 is blocked.', recLSCTransSales."Item No.");
                    //Message('Item no. %1 is not blocked.', recLSCTransSales."Item No.");
                    recLSCTransSales."Transaction Code" := recLSCTransSales."Transaction Code"::"Item on File";
                    recLSCTransSales.Modify();

                    recLSCTransStatus.Reset();
                    recLSCTransStatus.SetRange("Store No.", recLSCTransSales."Store No.");
                    recLSCTransStatus.SetRange("POS Terminal No.", recLSCTransSales."POS Terminal No.");
                    recLSCTransStatus.SetRange("Transaction No.", recLSCTransSales."Transaction No.");

                    if recLSCTransStatus.FindFirst() then begin
                        recLSCTransStatus."Items Blocked" := recLSCTransStatus."Items Blocked" - 1;
                        recLSCTransStatus.Modify();

                        recTempStatement2.Init();
                        recTempStatement2."Store No." := recLSCTransSales."Store No.";
                        recTempStatement2."No." := recLSCTransStatus."Statement No.";
                        recTempStatement2."No. Series." := codLItem;
                        if recTempStatement2.Insert() then;
                    end;

                end;
            until recLSCTransSales.Next() = 0;
    end;

    local procedure ResolveBlockedCustomer(pStoreNo: Code[10])
    var
        recTransHeader: Record "LSC Transaction Header";
        recLSCTransStatus: Record "LSC Transaction Status";
        recCustomer: Record Customer;
        codLCustomer: Code[20];
    begin
        recTransHeader.Reset();
        recTransHeader.SetRange(Date, WorkDate());
        recTransHeader.SetRange("Store No.", pStoreNo);

        if recTransHeader.FindFirst() then
            repeat
                recCustomer.Reset();
                recCustomer.SetRange("No.", recTransHeader."Customer No.");

                if recCustomer.FindFirst() then begin
                    if recCustomer.IsBlocked() then begin
                        recCustomer.Blocked := recCustomer.Blocked::" ";
                        recCustomer.Modify();
                        codLCustomer := recCustomer."No.";
                    end;
                    recLSCTransStatus.Reset();
                    recLSCTransStatus.SetRange("Store No.", recTransHeader."Store No.");
                    recLSCTransStatus.SetRange("POS Terminal No.", recTransHeader."POS Terminal No.");
                    recLSCTransStatus.SetRange("Transaction No.", recTransHeader."Transaction No.");

                    if recLSCTransStatus.FindFirst() then begin
                        recLSCTransStatus."Blocked Customer" := false;
                        recLSCTransStatus.Modify();

                        recTempStatement3.Init();
                        recTempStatement3."Store No." := recTransHeader."Store No.";
                        recTempStatement3."No." := recLSCTransStatus."Statement No.";
                        recTempStatement3."No. Series." := codLCustomer;
                        if recTempStatement3.Insert() then;
                    end;
                end;
            until recTransHeader.Next() = 0;
    end;

    procedure HasStatementLines(pStatementNo: Code[20]): Boolean
    var
        recStmtLine: Record "LSC Statement Line";
    begin
        recStmtLine.Reset();
        recStmtLine.SetRange("Statement No.", pStatementNo);
        exit(recStmtLine.FindFirst());
    end;

    var
        recStore: Record "LSC Store";
        recOpenStatement: Record "LSC Statement";
        recTempStatement: Record "LSC Statement" temporary;
        recTempStatement2: Record "LSC Statement" temporary;
        recTempStatement3: Record "LSC Statement" temporary;
        recOpenStatementLine: Record "LSC Statement Line";
        recOpenStatementLine2: Record "LSC Statement Line";
        recLSCTransStatus: Record "LSC Transaction Status";
        recItem: Record Item temporary;
        recItem2: Record Item temporary;
        recMondayTicket: Record BMGMondayTickets;
        recMondayTicket2: Record BMGMondayTickets;
        recSalesSetup: Record "Sales & Receivables Setup";
        recTransHeader: Record "LSC Transaction Header";
        recTenderDecl: Record "LSC Trans. Tender Declar. Entr";
        codPostOpenStatement: Codeunit "BMG LSC Statement-Post";
        BatchPostingStatus: Text[30];
        BatchPosting: Codeunit "LSC Batch Posting";
        bolErrorFound: Boolean;
        bolWithDiff: Boolean;
        bolWithError: Boolean;
        txtSubject: Text;
        txtStoreName: Text[100];
        codMondayMgt: Codeunit BMGMondayDotComMgt;
        intStatementCtr: Integer;
        intLineCtr: Integer;
        decAmountTendered: Decimal;
        txtMondayDescription: Text;
        decDifferenceAmount: Decimal;
}