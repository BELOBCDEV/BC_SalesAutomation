codeunit 68806 BMGPostBulkOpenStatement
{
    trigger OnRun()
    begin
        recItem.DeleteAll();

        recOpenStatement.Reset();
        recOpenStatement.SetRange("Posting Date", WorkDate());

        if recOpenStatement.FindFirst() then
            repeat
                recLSCTransStatus.Reset();
                recLSCTransStatus.SetRange("Statement No.", recOpenStatement."No.");

                if recLSCTransStatus.FindFirst() then
                    repeat
                        bolErrorFound := false;
                        if recLSCTransStatus."No. of Blank UOM Item" <> 0 then
                            bolErrorFound := true;
                        if recLSCTransStatus."Serial/Lot No. Not Valid" <> 0 then
                            bolErrorFound := true;
                        if recLSCTransStatus."Items/Barc. Not on File" <> 0 then
                            bolErrorFound := true;
                        if recLSCTransStatus."Blocked Customer" = true then
                            bolErrorFound := true;
                        if recLSCTransStatus."Items Blocked" <> 0 then
                            bolErrorFound := true;
                    until (recLSCTransStatus.Next() = 0) OR (bolErrorFound = true);

                recOpenStatementLine.Reset();
                recOpenStatementLine.SetRange("Statement No.", recOpenStatement."No.");
                recOpenStatementLine.SetFilter("Difference Amount", '<>%1', 0);

                if recOpenStatementLine.FindFirst() then
                    bolErrorFound := true;

                If not bolErrorFound then begin
                    recItem.Init();
                    recItem."No." := recOpenStatement."No.";
                    if recItem.Insert() then;
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

            until recItem.Next() = 0;


    end;


    var
        recStore: Record "LSC Store";
        recOpenStatement: Record "LSC Statement";
        recOpenStatementLine: Record "LSC Statement Line";
        recLSCTransStatus: Record "LSC Transaction Status";
        recItem: Record Item temporary;
        codPostOpenStatement: Codeunit "BMG LSC Statement-Post";
        BatchPostingStatus: Text[30];
        BatchPosting: Codeunit "LSC Batch Posting";
        bolErrorFound: Boolean;
        bolWithDiff: Boolean;
        bolWithError: Boolean;
}